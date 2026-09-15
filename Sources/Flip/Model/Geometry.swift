import CoreGraphics
import Foundation

// MARK: - Point arithmetic

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static prefix func - (a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }

    var length: CGFloat { (x * x + y * y).squareRoot() }
    func dist(_ o: CGPoint) -> CGFloat { (self - o).length }
}

extension CGAffineTransform {
    /// `inner`, applied about `c` rather than about the origin. Every transform in
    /// this app turns or stretches something about a point that is not the
    /// artboard's corner, so this is the form they are all written in.
    static func about(_ c: CGPoint, _ inner: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(translationX: -c.x, y: -c.y)
            .concatenating(inner)
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
    }

    static func rotation(_ radians: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: radians)
    }

    /// The transform without its translation — what a handle takes, since a
    /// handle is an offset from its anchor rather than a place on the artboard.
    var linear: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0) }

    /// Negative when the transform mirrors.
    var determinant: CGFloat { a * d - b * c }
}

// MARK: - Path data

/// One on-curve point with its two handles. Handles are stored as **offsets**
/// from the anchor, so dragging the anchor carries its curvature along instead
/// of shearing the segment.
struct Anchor: Codable, Equatable {
    var p: CGPoint
    var inH: CGPoint = .zero
    var outH: CGPoint = .zero

    init(_ p: CGPoint, inH: CGPoint = .zero, outH: CGPoint = .zero) {
        self.p = p; self.inH = inH; self.outH = outH
    }
}

struct Subpath: Codable, Equatable {
    var anchors: [Anchor] = []
    var closed: Bool = false

    var isFillable: Bool { closed && anchors.count >= 3 }

    /// Positive for clockwise in a y-down space. Uses the anchor polygon, which
    /// is accurate enough to decide winding direction.
    var signedArea: CGFloat {
        guard anchors.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in anchors.indices {
            let a = anchors[i].p, b = anchors[(i + 1) % anchors.count].p
            sum += (a.x * b.y - b.x * a.y)
        }
        return sum / 2
    }

    mutating func reverse() {
        anchors.reverse()
        for i in anchors.indices {
            let a = anchors[i]
            anchors[i].inH = a.outH
            anchors[i].outH = a.inH
        }
    }

    /// Every subpath in a document is wound the same way, so a union can be a
    /// plain non-zero fill of the combined path rather than a real boolean.
    mutating func normalizeWinding() {
        if closed && signedArea < 0 { reverse() }
    }
}

struct Shape2D: Codable, Equatable {
    var subpaths: [Subpath] = []

    var isEmpty: Bool { subpaths.allSatisfy { $0.anchors.count < 2 } }
    var hasFillableArea: Bool { subpaths.contains { $0.isFillable } }

    var cgPath: CGPath {
        let path = CGMutablePath()
        for sp in subpaths where sp.anchors.count >= 2 {
            let a = sp.anchors
            let n = a.count
            path.move(to: a[0].p)
            let segments = sp.closed ? n : n - 1
            for i in 0..<segments {
                let from = a[i], to = a[(i + 1) % n]
                // A segment with no handles *is* a straight line, and saying so
                // is much cheaper than asking the rasteriser to flatten a cubic
                // that was never curved. A wandered line at the rough end of the
                // dial is hundreds of these in a row, and stating them as curves
                // was most of what it cost to paint.
                if from.outH == .zero, to.inH == .zero {
                    path.addLine(to: to.p)
                } else {
                    path.addCurve(to: to.p,
                                  control1: from.p + from.outH,
                                  control2: to.p + to.inH)
                }
            }
            if sp.closed { path.closeSubpath() }
        }
        return path
    }

    /// `d` attribute for SVG. Same traversal as `cgPath` so what you export is
    /// exactly what the canvas drew.
    var svgPathData: String {
        var out: [String] = []
        func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
        for sp in subpaths where sp.anchors.count >= 2 {
            let a = sp.anchors
            let n = a.count
            out.append("M \(f(a[0].p.x)) \(f(a[0].p.y))")
            let segments = sp.closed ? n : n - 1
            for i in 0..<segments {
                let from = a[i], to = a[(i + 1) % n]
                let c1 = from.p + from.outH, c2 = to.p + to.inH
                out.append("C \(f(c1.x)) \(f(c1.y)) \(f(c2.x)) \(f(c2.y)) \(f(to.p.x)) \(f(to.p.y))")
            }
            if sp.closed { out.append("Z") }
        }
        return out.joined(separator: " ")
    }

    mutating func translate(by d: CGPoint) {
        for i in subpaths.indices {
            for j in subpaths[i].anchors.indices { subpaths[i].anchors[j].p = subpaths[i].anchors[j].p + d }
        }
    }

    /// Apply an affine transform.
    ///
    /// The one primitive every stretch, turn and mirror in the app is built from.
    /// Handles are stored as offsets from their anchor, so they take the
    /// transform's **linear** part only — picking up its translation as well
    /// would fling every handle across the artboard.
    mutating func transform(by m: CGAffineTransform) {
        let linear = m.linear
        let mirrors = m.determinant < 0
        for i in subpaths.indices {
            for j in subpaths[i].anchors.indices {
                var a = subpaths[i].anchors[j]
                a.p = a.p.applying(m)
                a.inH = a.inH.applying(linear)
                a.outH = a.outH.applying(linear)
                subpaths[i].anchors[j] = a
            }
            // A mirrored path is wound the other way round, and every closed
            // subpath in a document has to agree about its winding or a union
            // stops being a plain non-zero fill of the combined path. A rotation
            // or a plain scale has a positive determinant and is left alone —
            // which matters, because re-winding renumbers the anchors.
            if mirrors { subpaths[i].normalizeWinding() }
        }
    }

    static func rect(_ r: CGRect) -> Shape2D {
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        var sp = Subpath(anchors: pts.map { Anchor($0) }, closed: true)
        sp.normalizeWinding()
        return Shape2D(subpaths: [sp])
    }

    /// Four-anchor ellipse. The 0.5523 handle length is the standard circular
    /// arc approximation, scaled to each radius.
    static func ellipse(_ r: CGRect) -> Shape2D {
        let c = CGPoint(x: r.midX, y: r.midY)
        let rx = r.width / 2, ry = r.height / 2
        let kx = rx * 0.55228, ky = ry * 0.55228
        var anchors = [
            Anchor(CGPoint(x: c.x, y: c.y - ry), inH: CGPoint(x: kx, y: 0), outH: CGPoint(x: -kx, y: 0)),
            Anchor(CGPoint(x: c.x - rx, y: c.y), inH: CGPoint(x: 0, y: -ky), outH: CGPoint(x: 0, y: ky)),
            Anchor(CGPoint(x: c.x, y: c.y + ry), inH: CGPoint(x: -kx, y: 0), outH: CGPoint(x: kx, y: 0)),
            Anchor(CGPoint(x: c.x + rx, y: c.y), inH: CGPoint(x: 0, y: ky), outH: CGPoint(x: 0, y: -ky)),
        ]
        if rx == 0 || ry == 0 { anchors = anchors.map { Anchor($0.p) } }
        var sp = Subpath(anchors: anchors, closed: true)
        sp.normalizeWinding()
        return Shape2D(subpaths: [sp])
    }
}

// MARK: - Freehand fitting

enum Fit {
    /// Ramer–Douglas–Peucker. Drops the samples that a straight run through
    /// their neighbours already accounts for.
    static func simplify(_ pts: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]

        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            let a = pts[lo], b = pts[hi]
            let ab = b - a
            let len = ab.length
            var worst: CGFloat = -1, worstIndex = lo

            for i in (lo + 1)..<hi {
                let p = pts[i]
                let d: CGFloat
                if len < 1e-9 {
                    d = p.dist(a)
                } else {
                    // Perpendicular distance to the segment ab.
                    d = abs(ab.x * (a.y - p.y) - ab.y * (a.x - p.x)) / len
                }
                if d > worst { worst = d; worstIndex = i }
            }

            if worst > tolerance {
                keep[worstIndex] = true
                stack.append((lo, worstIndex))
                stack.append((worstIndex, hi))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    /// Catmull-Rom tangents converted to cubic Bézier handles: each anchor's
    /// handles point along the chord between its neighbours, at a sixth of that
    /// chord. Gives a smooth curve through every sample without solving a fit.
    static func handles(for pts: [CGPoint], closed: Bool) -> [Anchor] {
        let n = pts.count
        guard n >= 2 else { return pts.map { Anchor($0) } }
        return pts.indices.map { i in
            let prev = i == 0 ? (closed ? pts[n - 1] : pts[0]) : pts[i - 1]
            let next = i == n - 1 ? (closed ? pts[0] : pts[n - 1]) : pts[i + 1]
            let t = (next - prev) * (1.0 / 6.0)
            return Anchor(pts[i], inH: -t, outH: t)
        }
    }

    /// How far the fitted curve may stray from the samples, **in points on
    /// screen**, and how far apart two samples must be to both be kept.
    ///
    /// On screen, not in the document, and that distinction is the whole bug.
    /// The samples arrive already converted to document space, so a fixed
    /// document-space tolerance means something different at every zoom: at 3×
    /// it throws away detail six screen points wide — a third of a letter —
    /// while at 0.5× it barely touches anything. Drawing zoomed in, which is
    /// exactly when you are drawing the fine stuff, was where it bit hardest.
    /// Dividing by the zoom makes the allowance mean the same thing to the hand
    /// holding the pen wherever it is drawn.
    ///
    /// The number itself came down from 2.0 as well. At sub-pixel it keeps
    /// roughly three times the anchors it used to, which is the price of a line
    /// that still looks like the one that was drawn.
    static let strokeTolerance: CGFloat = 0.7
    static let minSampleSpacing: CGFloat = 0.75

    /// Raw pointer samples to a finished subpath. Closes the path when the
    /// stroke ends near where it began, which is what makes a drawn loop fill.
    ///
    /// `zoom` is what the samples were drawn at. It is a parameter rather than
    /// something the caller pre-divides into a tolerance because forgetting it
    /// is silent — the line just comes out flatter than it went in.
    static func stroke(_ raw: [CGPoint], closeWithin: CGFloat, zoom: CGFloat = 1) -> Subpath? {
        let scale = max(zoom, 0.01)
        let spacing = minSampleSpacing / scale
        var pts: [CGPoint] = []
        for p in raw where pts.isEmpty || p.dist(pts[pts.count - 1]) > spacing { pts.append(p) }
        guard pts.count >= 2 else { return nil }

        var closed = false
        if pts.count >= 4, pts[0].dist(pts[pts.count - 1]) < closeWithin {
            closed = true
            pts.removeLast()
        }
        pts = simplify(pts, tolerance: strokeTolerance / scale)
        guard pts.count >= 2 else { return nil }

        var sp = Subpath(anchors: handles(for: pts, closed: closed), closed: closed)
        sp.normalizeWinding()
        return sp
    }
}

// MARK: - Cubic segments

/// One segment of a subpath, and the two things the pen needs to do with it:
/// find the nearest place on it, and split it there without changing its shape.
enum Curve {
    typealias Cubic = (CGPoint, CGPoint, CGPoint, CGPoint)

    static func point(_ c: Cubic, at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x,
                       y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
    }

    /// de Casteljau. The two halves reproduce the original curve exactly between
    /// them, which is the whole point: adding a point to a segment must leave
    /// the drawing looking identical. Placing an anchor at the right position
    /// with fresh handles is a different curve through the same three points,
    /// and it dents whatever you were tracing.
    static func split(_ c: Cubic, at t: CGFloat) -> (left: Cubic, right: Cubic) {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let ab = mix(c.0, c.1), bc = mix(c.1, c.2), cd = mix(c.2, c.3)
        let abc = mix(ab, bc), bcd = mix(bc, cd)
        let mid = mix(abc, bcd)
        return ((c.0, ab, abc, mid), (mid, bcd, cd, c.3))
    }

    /// The control points' own box, which contains the curve. Cheap, and the
    /// reason hovering a drawing with a thousand points does not cost a
    /// thousand curve samples per mouse move.
    static func bounds(_ c: Cubic) -> CGRect {
        let xs = [c.0.x, c.1.x, c.2.x, c.3.x], ys = [c.0.y, c.1.y, c.2.y, c.3.y]
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Where on this curve sits closest to `p`. Sampled, then bisected around
    /// the best sample — exact enough for a click, and far cheaper than solving
    /// the quintic the true answer needs.
    static func nearest(_ c: Cubic, to p: CGPoint, samples: Int = 20) -> (t: CGFloat, distance: CGFloat) {
        var bestT: CGFloat = 0, bestD = CGFloat.greatestFiniteMagnitude
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let d = point(c, at: t).dist(p)
            if d < bestD { bestD = d; bestT = t }
        }
        var step = 1 / CGFloat(samples) / 2
        for _ in 0..<8 {
            for t in [bestT - step, bestT + step] where t >= 0 && t <= 1 {
                let d = point(c, at: t).dist(p)
                if d < bestD { bestD = d; bestT = t }
            }
            step /= 2
        }
        return (bestT, bestD)
    }
}

extension Subpath {
    /// How many curves this subpath is made of. A closed one has a segment from
    /// its last anchor back to its first; an open one does not.
    var segmentCount: Int {
        guard anchors.count >= 2 else { return 0 }
        return closed ? anchors.count : anchors.count - 1
    }

    /// The anchor a segment ends at, wrapping for a closed subpath.
    func segmentEnd(_ i: Int) -> Int { (i + 1) % anchors.count }

    /// One segment's four control points.
    func segment(_ i: Int) -> Curve.Cubic? {
        guard i >= 0, i < segmentCount else { return nil }
        let a = anchors[i], b = anchors[segmentEnd(i)]
        return (a.p, a.p + a.outH, b.p + b.inH, b.p)
    }

    /// The nearest place on this subpath to `p`, within `limit`.
    func nearestPlace(to p: CGPoint, within limit: CGFloat) -> (segment: Int, t: CGFloat)? {
        var best: (Int, CGFloat, CGFloat)?
        for i in 0..<segmentCount {
            guard let c = segment(i) else { continue }
            // The box first — most segments in a drawing are nowhere near the
            // pointer, and rejecting them is a rectangle test rather than
            // twenty curve evaluations.
            guard Curve.bounds(c).insetBy(dx: -limit, dy: -limit).contains(p) else { continue }
            let hit = Curve.nearest(c, to: p)
            guard hit.distance <= limit else { continue }
            if best == nil || hit.distance < best!.2 { best = (i, hit.t, hit.distance) }
        }
        guard let best else { return nil }
        return (best.0, best.1)
    }
}

extension CGPath {
    /// The `d` attribute for a path built rather than stored — the pencil's
    /// mark, which is geometry the document never holds.
    var svgPathData: String {
        var out: [String] = []
        func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
        applyWithBlock { e in
            let p = e.pointee
            switch p.type {
            case .moveToPoint:         out.append("M \(f(p.points[0].x)) \(f(p.points[0].y))")
            case .addLineToPoint:      out.append("L \(f(p.points[0].x)) \(f(p.points[0].y))")
            case .addQuadCurveToPoint: out.append("Q \(f(p.points[0].x)) \(f(p.points[0].y)) \(f(p.points[1].x)) \(f(p.points[1].y))")
            case .addCurveToPoint:     out.append("C \(f(p.points[0].x)) \(f(p.points[0].y)) \(f(p.points[1].x)) \(f(p.points[1].y)) \(f(p.points[2].x)) \(f(p.points[2].y))")
            case .closeSubpath:        out.append("Z")
            @unknown default:          break
            }
        }
        return out.joined(separator: " ")
    }
}
