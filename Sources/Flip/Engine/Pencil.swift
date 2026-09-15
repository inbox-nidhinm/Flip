import CoreGraphics
import Foundation

/// A pencil mark as a **shape**: the stroke's outline eaten into along both
/// edges, with holes through it where the paper stood too high for graphite to
/// reach.
///
/// Geometry rather than pixels, which decides three things at once. It survives
/// the SVG export, since it is only a path. It stays crisp at any zoom, where a
/// mask is only ever as good as the resolution it was built at. And it costs
/// what a path costs — the raster version of this spent its whole budget
/// walking a bounding box that was mostly empty.
enum Pencil {
    /// The mark, ready to fill with the even-odd rule so the holes are holes.
    /// `nil` when the nib is a plain pen or the mark is too small to carry
    /// grain, which sends the caller back to an ordinary stroke.
    static func mark(_ path: CGPath, nib: Nib, width: CGFloat, seed: UInt64) -> CGPath? {
        guard nib.pencil != nil, width > 1e-3 else { return nil }
        // Built once and kept. The mark is a pure function of the line, the nib
        // and the paper, and none of those change when the pointer moves or a
        // panel opens — but a repaint does, and building a few thousand holes
        // on every one of them is most of what a pencil would otherwise cost.
        //
        // Keyed on the *centreline*, which is forty-odd points, not on the mark,
        // which is thousands. A boiling stroke changes every frame and will miss
        // every time; that is correct, and it is the only case that does.
        let key = Key(path: path, nib: nib, width: width, seed: seed)
        if let hit = cache.object(forKey: key) { return hit.path }
        guard let built = build(path, nib: nib, width: width, seed: seed) else { return nil }
        cache.setObject(Box(built), forKey: key)
        return built
    }

    /// `NSCache` for its own sake: it is thread-safe, and this is reached from
    /// the canvas on the main thread and from thumbnails on a background one.
    private static let cache: NSCache<Key, Box> = {
        let c = NSCache<Key, Box>()
        c.countLimit = 400
        return c
    }()

    final class Box { let path: CGPath; init(_ p: CGPath) { path = p } }

    final class Key: NSObject {
        private let digest: Int
        init(path: CGPath, nib: Nib, width: CGFloat, seed: UInt64) {
            var h = Hasher()
            h.combine(nib); h.combine(width); h.combine(seed)
            path.applyWithBlock { e in
                let p = e.pointee
                h.combine(p.type.rawValue)
                let n: Int
                switch p.type {
                case .addQuadCurveToPoint: n = 2
                case .addCurveToPoint:     n = 3
                case .closeSubpath:        n = 0
                default:                   n = 1
                }
                for i in 0..<n { h.combine(p.points[i].x); h.combine(p.points[i].y) }
            }
            digest = h.finalize()
        }
        override var hash: Int { digest }
        override func isEqual(_ other: Any?) -> Bool { (other as? Key)?.digest == digest }
    }

    private static func build(_ path: CGPath, nib: Nib, width: CGFloat, seed: UInt64) -> CGPath? {
        guard let dial = nib.pencil else { return nil }
        let half = width / 2
        // The tooth's own size in points. Everything else is measured against
        // it: bite deeper than a grain and the edge reads as torn rather than
        // as rough.
        let cell = max(0.7 / dial.grain, 0.35)

        let runs = runs(of: path, step: min(cell, half))
        // How many holes the mark may carry.
        //
        // Physically a grain is a fixed size and a wide line simply has more of
        // them — but the cost of a hole is a subpath the rasteriser has to scan
        // convert, and a long line at a fine grain wants tens of thousands. The
        // eye cannot count them past a few hundred; the rasteriser can. So the
        // grid is opened up until the mark fits its budget, which bounds what a
        // stroke costs however long or wide it is drawn.
        let wanted = runs.reduce(0) { $0 + $1.count } * max(Int(half * 2 / cell), 1)
        let relief = max(1, CGFloat(wanted) / CGFloat(budget))
        let holeCell = cell * sqrt(relief)

        let out = CGMutablePath()
        var any = false
        for run in runs where run.count >= 2 {
            edge(run, into: out, half: half, cell: cell, dial: dial, seed: seed)
            holes(run, into: out, half: half, cell: holeCell, step: cell,
                  dial: dial, seed: seed)
            any = true
        }
        return any ? out : nil
    }

    // MARK: The edge

    /// The two sides of the ribbon, each pushed in by the paper under it.
    ///
    /// Sampled at the *edge's own* position rather than the centreline's, so the
    /// two sides fray independently — moving one noise field in and out gives a
    /// ribbon that pulses evenly, which reads as a worm and not as a pencil.
    private static func edge(_ run: [Sample], into out: CGMutablePath, half: CGFloat,
                             cell: CGFloat, dial: Nib.Pencil, seed: UInt64) {
        var left: [CGPoint] = [], right: [CGPoint] = []
        left.reserveCapacity(run.count); right.reserveCapacity(run.count)
        // How far in the paper can eat. A light hand leaves graphite only on the
        // peaks, so its edge is bitten deeper.
        let depth = min(half * 0.75, cell * 3.2) * (1.35 - dial.press)
        for s in run {
            let l = CGPoint(x: s.p.x + s.n.x * half, y: s.p.y + s.n.y * half)
            let r = CGPoint(x: s.p.x - s.n.x * half, y: s.p.y - s.n.y * half)
            let bl = bite(at: l, cell: cell, seed: seed, dial: dial) * depth
            let br = bite(at: r, cell: cell, seed: seed, dial: dial) * depth
            left.append(CGPoint(x: l.x - s.n.x * bl, y: l.y - s.n.y * bl))
            right.append(CGPoint(x: r.x + s.n.x * br, y: r.y + s.n.y * br))
        }
        out.addLines(between: left + right.reversed())
        out.closeSubpath()
    }

    /// How much the paper takes out here, 0…1.
    private static func bite(at p: CGPoint, cell: CGFloat, seed: UInt64,
                             dial: Nib.Pencil) -> CGFloat {
        let t = Paper.tooth(p.x / cell, p.y / cell, grain: 1, seed: seed)
        // `bite` steepens it: a hard lead leaves a cleaner edge with deeper
        // notches, a soft one a more even fur.
        return min(max((t - 0.42) * dial.bite * 0.6 + 0.35, 0), 1)
    }

    // MARK: The holes

    /// Where the paper stands proud inside the mark, graphite skips it.
    ///
    /// Walked along the stroke and across its width rather than over a grid on
    /// the bounding box: a stroke is a thin ribbon and its box is mostly empty,
    /// which is the same thing that made the raster version slow.
    /// Holes per mark, near enough. Past this the grid opens up instead.
    private static let budget = 900

    private static func holes(_ run: [Sample], into out: CGMutablePath, half: CGFloat,
                              cell: CGFloat, step: CGFloat, dial: Nib.Pencil, seed: UInt64) {
        // Nothing to punch through a heavy line: the graphite has filled the
        // paper in, which is what pressing hard does.
        guard dial.press < 0.92, half > cell * 0.5 else { return }
        let across = max(Int((half * 2 / cell).rounded()), 1)
        let stride = max(Int((cell / step).rounded()), 1)
        var i = 0
        while i < run.count {
            defer { i += stride }
            let s = run[i]
            for k in 0...across {
                // Jittered off the lattice by most of a cell, in both
                // directions and from two unrelated fields. A regular grid of
                // holes is the one thing that gives this away instantly — it
                // reads as woven cloth, and no amount of getting the sizes
                // right rescues it.
                let jx = Paper.tooth(s.p.x / cell * 2.3, s.p.y / cell * 2.3,
                                     grain: 1, seed: seed &+ UInt64(k) &* 9151 &+ 331) - 0.5
                let jy = Paper.tooth(s.p.y / cell * 3.1, s.p.x / cell * 3.1,
                                     grain: 1, seed: seed &+ UInt64(k) &* 6113 &+ 977) - 0.5
                let u = (CGFloat(k) / CGFloat(across) - 0.5) * 2
                let off = u * half + jx * cell * 1.6
                guard abs(off) < half else { continue }
                let along = jy * cell * 1.6
                let c = CGPoint(x: s.p.x + s.n.x * off - s.n.y * along,
                                y: s.p.y + s.n.y * off + s.n.x * along)

                let t = Paper.tooth(c.x / cell, c.y / cell, grain: 1, seed: seed)
                // Higher toward the edges, so the fringe dissolves before the
                // core does — which is what makes a mark read as pressed on
                // rather than as stencilled.
                let edgeward = min(abs(off) / half, 1)
                let keep = dial.press * (1 - edgeward * 0.55)
                guard t > keep else { continue }
                // Small, and varying by a factor of three. Holes all one size
                // are as much of a tell as holes in rows.
                let r = cell * (0.16 + (t - keep) * 2.2)
                speck(c, min(r, cell * 0.75), jx, jy, into: out)
            }
        }
    }

    /// A four-sided speck with every corner pushed about, rather than a square.
    /// At a grain's size the shape hardly matters, but *sameness* does: identical
    /// squares tile the eye even when their positions do not.
    private static func speck(_ c: CGPoint, _ r: CGFloat, _ jx: CGFloat, _ jy: CGFloat,
                              into out: CGMutablePath) {
        guard r > 0.02 else { return }
        let a = r * (0.7 + jx), b = r * (0.7 + jy)
        let d = r * (0.7 - jy), e = r * (0.7 - jx)
        out.move(to: CGPoint(x: c.x - a, y: c.y - b))
        out.addLine(to: CGPoint(x: c.x + d, y: c.y - a))
        out.addLine(to: CGPoint(x: c.x + b, y: c.y + e))
        out.addLine(to: CGPoint(x: c.x - e, y: c.y + d))
        out.closeSubpath()
    }

    // MARK: Walking the path

    struct Sample { let p: CGPoint; let n: CGPoint }

    /// Each subpath as a run of points with the normal at each, `step` apart.
    private static func runs(of path: CGPath, step: CGFloat) -> [[Sample]] {
        var out: [[Sample]] = []
        var pts: [CGPoint] = []
        var start = CGPoint.zero, pen = CGPoint.zero

        func flush(closed: Bool) {
            defer { pts = [] }
            guard pts.count >= 2 else { return }
            var run: [Sample] = []
            run.reserveCapacity(pts.count)
            for i in pts.indices {
                let a = pts[i == 0 ? (closed ? pts.count - 1 : 0) : i - 1]
                let b = pts[i == pts.count - 1 ? (closed ? 0 : pts.count - 1) : i + 1]
                let t = CGPoint(x: b.x - a.x, y: b.y - a.y)
                let len = sqrt(t.x * t.x + t.y * t.y)
                guard len > 1e-9 else { continue }
                run.append(Sample(p: pts[i], n: CGPoint(x: -t.y / len, y: t.x / len)))
            }
            if run.count >= 2 { out.append(run) }
        }

        func sample(_ c: (CGPoint, CGPoint, CGPoint, CGPoint)) {
            let rough = dist(c.0, c.1) + dist(c.1, c.2) + dist(c.2, c.3)
            let n = max(1, Int((rough / step).rounded(.up)))
            for k in 1...n { pts.append(cubic(c, CGFloat(k) / CGFloat(n))) }
        }

        path.applyWithBlock { e in
            let p = e.pointee
            switch p.type {
            case .moveToPoint:
                flush(closed: false)
                start = p.points[0]; pen = start; pts = [start]
            case .addLineToPoint:
                let q = p.points[0]
                let n = max(1, Int((dist(pen, q) / step).rounded(.up)))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n)
                    pts.append(CGPoint(x: pen.x + (q.x - pen.x) * t, y: pen.y + (q.y - pen.y) * t))
                }
                pen = q
            case .addQuadCurveToPoint:
                let c = p.points[0], q = p.points[1]
                sample((pen, CGPoint(x: pen.x + 2.0 / 3 * (c.x - pen.x), y: pen.y + 2.0 / 3 * (c.y - pen.y)),
                        CGPoint(x: q.x + 2.0 / 3 * (c.x - q.x), y: q.y + 2.0 / 3 * (c.y - q.y)), q))
                pen = q
            case .addCurveToPoint:
                let q = p.points[2]
                sample((pen, p.points[0], p.points[1], q))
                pen = q
            case .closeSubpath:
                flush(closed: true); pen = start; pts = []
            @unknown default: break
            }
        }
        flush(closed: false)
        return out
    }

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }

    private static func cubic(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x,
                       y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
    }
}
