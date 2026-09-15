import CoreGraphics
import Foundation

/// How much a line wanders off the path it was drawn on, and how much that
/// wander changes from one frame to the next.
///
/// Stored on the layer but never baked into it: the anchors on disk stay the
/// clean line that was drawn, and the wander is added when the frame is
/// painted. Same arrangement as the rig, for the same three reasons — the
/// dials stay live long after the stroke is finished, undo takes back a
/// setting rather than a redrawn line, and the artwork cannot drift out of
/// step with the thing driving it.
struct Wiggle: Codable, Equatable {
    /// How far the line strays from where it was drawn, 0…1 of `maxAmplitude`.
    /// The size of the bumps.
    var amount: Double = 0
    /// How tightly it strays: 0 is a long lazy drift, 1 is a fine chatter.
    /// The number of bumps.
    var frequency: Double = 0.5
    /// How jagged the bumps are: 0 is broken ground, 1 is a smooth undulation.
    ///
    /// Its own dial rather than something read off the amount, which is how it
    /// was first built and was wrong. The two are independent questions — a
    /// wide gentle swell and a tight jagged scratch are both things you might
    /// want — and tying them together made half the combinations unreachable.
    var smoothen: Double = 0
    /// How much the wander differs from one frame to the next. At 0 every frame
    /// wanders identically and a held drawing is perfectly still — surface
    /// texture and nothing more. At 1 each frame is wholly its own, which is the
    /// boil of a line redrawn by hand. In between, the two are mixed, so a rigged
    /// character can breathe without shimmering apart.
    var boil: Double = 0.5

    /// In document points, at `amount` 1. Past about this the line stops being
    /// the line that was drawn and starts being a different one.
    static let maxAmplitude: CGFloat = 14

    /// How much of the fitted curve's smoothness survives, which is half of
    /// what the Smoothen dial does.
    ///
    /// A wander re-fitted with full tangents comes off as gentle swells: every
    /// crest rounded. Shorten the handles and the same points read as broken
    /// ground instead.
    var smoothness: CGFloat { CGFloat(min(max(smoothen, 0), 1)) }

    /// How much of the finer waves is heard, which is the other half.
    ///
    /// Rounding corners alone files down the jaggedness after the fact and
    /// leaves the line busy; quietening the fine waves means they were never
    /// there. Both move together on one dial because they are one question —
    /// how jagged are the bumps — asked of two different parts of the pipe.
    var detail: CGFloat { 1 - CGFloat(min(max(smoothen, 0), 1)) }

    /// Document points from one crest of the **coarsest** wave to the next. The
    /// finer waves laid over it run at two and four times this.
    var wavelength: CGFloat {
        let t = CGFloat(min(max(frequency, 0), 1))
        return 120 - t * 96
    }

    var amplitude: CGFloat { CGFloat(min(max(amount, 0), 1)) * Self.maxAmplitude }

    /// Nothing to do, which is worth asking before flattening a path.
    var isIdle: Bool { amplitude < 0.05 }

    static let off = Wiggle(amount: 0)

    /// Hand-written so a `.flip` saved before Smoothen existed still opens — it
    /// has a wiggle but no such key, and the synthesised decoder would refuse
    /// the whole document over it. Absent means 0, which is how those drawings
    /// were painted.
    init(amount: Double = 0, frequency: Double = 0.5, smoothen: Double = 0, boil: Double = 0.5) {
        self.amount = amount
        self.frequency = frequency
        self.smoothen = smoothen
        self.boil = boil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        frequency = try c.decodeIfPresent(Double.self, forKey: .frequency) ?? 0.5
        smoothen = try c.decodeIfPresent(Double.self, forKey: .smoothen) ?? 0
        boil = try c.decodeIfPresent(Double.self, forKey: .boil) ?? 0.5
    }
}

// MARK: - The noise

/// Smooth one-dimensional value noise on an integer lattice.
///
/// Deliberately not random: the same layer on the same frame has to wander the
/// same way every time it is painted, or the line would crawl under a still
/// cursor and every redraw — a scroll, a panel opening — would be a new
/// drawing. Everything here is a pure function of position and seed.
enum Wobble {
    /// One lattice point's value in -1…1.
    ///
    /// `period` wraps the lattice so a closed path can come back to where it
    /// started. Without it a loop meets its own beginning at an unrelated value
    /// and every circle drawn wears a nick at three o'clock.
    private static func lattice(_ i: Int, seed: UInt64, period: Int) -> CGFloat {
        var n = UInt64(bitPattern: Int64(period > 0 ? ((i % period) + period) % period : i))
        n &+= seed &* 0x9E37_79B9_7F4A_7C15
        n ^= n >> 30; n = n &* 0xBF58_476D_1CE4_E5B9
        n ^= n >> 27; n = n &* 0x94D0_49BB_1331_11EB
        n ^= n >> 31
        // 53 bits, so the divisor is 2^53 and not 2^52 — halving it here
        // stretched the field to -1…3 and every line strayed two and a half
        // times as far as the dial asked for, lopsidedly.
        return CGFloat(n >> 11) / CGFloat(UInt64(1) << 53) * 2 - 1
    }

    /// One wave of the field at `x`, in lattice units.
    static func at(_ x: CGFloat, seed: UInt64, period: Int = 0) -> CGFloat {
        let i = Int(floor(x))
        let t = x - CGFloat(i)
        // Smoothstep, so the slope is zero at every lattice point and the joins
        // between cells cannot be seen.
        let s = t * t * (3 - 2 * t)
        return lattice(i, seed: seed, period: period) * (1 - s)
             + lattice(i + 1, seed: seed, period: period) * s
    }

    /// How many waves are laid over each other, each twice as fine and half as
    /// tall as the one under it.
    static let octaves = 3

    /// The field with all its waves, which is what makes it read as ground
    /// rather than as a ripple.
    ///
    /// One wave is a swell — smooth, regular, and unmistakably a sine however
    /// it is dressed. Terrain is a big shape with smaller shapes on it, all the
    /// way down; three is enough to stop the eye finding the period.
    ///
    /// `period` doubles with each wave, which is what keeps a closed path
    /// closing: at four times the frequency the lattice has to wrap four times
    /// as often or the finest wave meets itself at a stranger.
    ///
    /// `detail` is how much of the finer waves is heard, 0…1. Jaggedness *is*
    /// the fine waves — rounding the corners off afterwards only files down
    /// what they made — so smoothing has to reach in here and quieten them.
    /// At nothing it leaves the coarsest wave alone and the line becomes a
    /// single clean swell.
    static func rough(_ x: CGFloat, seed: UInt64, period: Int = 0,
                      detail: CGFloat = 1) -> CGFloat {
        var sum: CGFloat = 0, amp: CGFloat = 1, power: CGFloat = 0
        var f: CGFloat = 1, p = period
        let d = min(max(detail, 0), 1)
        for o in 0..<octaves {
            sum += at(x * f, seed: seed &+ UInt64(o) &* 0x9E37_79B9, period: p) * amp
            power += amp * amp
            amp *= 0.55 * d
            f *= 2
            p *= 2
        }
        // Normalised by the root of the summed power, not by the summed
        // amplitude. The waves are independent and mostly cancel, so dividing
        // by the sum of their heights gave a peak that was almost never reached
        // — three waves came out at around half the reach of one, and Wiggle
        // quietly meant something different at each end of the Smoothen dial.
        // Clamped, because independent waves can still occasionally agree, and
        // the amplitude is a promise.
        let n = sum / sqrt(max(power, 0.0001))
        return min(max(n, -1), 1)
    }

    /// A stable 64-bit seed from a UUID, and from a pair of them.
    static func seed(_ id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { raw in
            var h: UInt64 = 0xCBF2_9CE4_8422_2325
            for byte in raw { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
            return h
        }
    }

    static func seed(_ a: UUID, _ b: UUID) -> UInt64 {
        let x = seed(a), y = seed(b)
        var h = x ^ (y &+ 0x9E37_79B9_7F4A_7C15 &+ (x << 6) &+ (x >> 2))
        h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 33
        return h
    }
}

// MARK: - Applying it

extension Wiggle {
    /// The shape as the wander leaves it.
    ///
    /// The path is walked at a spacing fine enough to carry the wave, each point
    /// pushed **sideways** — along the normal, never along the tangent — and the
    /// curve re-fitted through where they land. Sideways only because a line
    /// that also stretched and bunched along its own length would read as the
    /// drawing melting rather than as the hand shaking.
    ///
    /// Re-walking rather than nudging the anchors: a fitted stroke keeps only
    /// the anchors it needs, so a long straight run may have two, and no amount
    /// of moving two points puts a wobble between them.
    func applied(to shape: Shape2D, still: UInt64, moving: UInt64) -> Shape2D {
        guard !isIdle else { return shape }
        let mix = CGFloat(min(max(boil, 0), 1))
        return Shape2D(subpaths: shape.subpaths.map { sp in
            wander(sp, mix: mix, still: still, moving: moving)
        })
    }

    /// No path may cost more than this many anchors, however long it is. A wave
    /// that fine over a line that long is not a texture anyone can see; it is
    /// only a bill the rasteriser pays on every repaint.
    private static let sampleCeiling = 900

    private func wander(_ sp: Subpath, mix: CGFloat, still: UInt64, moving: UInt64) -> Subpath {
        // A third of a wave between samples: enough for the curve to be fitted
        // back through the crests, few enough that a long stroke does not come
        // out with an order of magnitude more geometry than it went in with.
        // Fine enough for the *finest* wave, not the coarsest: sampling the
        // base wavelength only would step straight over the detail that makes
        // the line rough and leave the swell behind.
        let span = Self.roughLength(sp)
        let finest = wavelength / CGFloat(1 << (Wobble.octaves - 1))
        let step = max(finest / 3, span / CGFloat(Self.sampleCeiling), 0.6)
        var pts = Self.walk(sp, step: step)
        guard pts.count >= 3 else { return sp }

        // Distance along the line, so the wave keeps its wavelength whether the
        // samples fell close together or far apart.
        var run: [CGFloat] = [0]
        run.reserveCapacity(pts.count)
        for i in 1..<pts.count { run.append(run[i - 1] + pts[i].dist(pts[i - 1])) }
        let total = run[pts.count - 1]
        guard total > step else { return sp }

        // A whole number of waves around a closed path, so its end meets its
        // own beginning. Open paths have no such obligation.
        let cycles = max(2, Int((total / wavelength).rounded()))
        let lattice = sp.closed ? total / CGFloat(cycles) : wavelength
        let period = sp.closed ? cycles : 0

        var out = pts
        for i in pts.indices {
            let x = run[i] / lattice
            let a = Wobble.rough(x, seed: still, period: period, detail: detail)
            let b = Wobble.rough(x, seed: moving, period: period, detail: detail)
            let n = a * (1 - mix) + b * mix

            // The normal to the line here, from the neighbours rather than one
            // side, so a sharp corner leans on both of its edges.
            let prev = pts[i == 0 ? (sp.closed ? pts.count - 1 : 0) : i - 1]
            let next = pts[i == pts.count - 1 ? (sp.closed ? 0 : pts.count - 1) : i + 1]
            let t = next - prev
            let len = t.length
            guard len > 1e-9 else { continue }
            out[i] = CGPoint(x: pts[i].x - t.y / len * amplitude * n,
                             y: pts[i].y + t.x / len * amplitude * n)
        }
        pts = out
        // Handles shortened rather than dropped outright: at nothing they are
        // corners and the line is broken ground, at full length it is the
        // smooth curve the points describe, and the dial runs between.
        let k = smoothness
        var anchors = Fit.handles(for: pts, closed: sp.closed)
        if k < 0.999 {
            for i in anchors.indices {
                anchors[i].inH = Self.shorten(anchors[i].inH, by: k)
                anchors[i].outH = Self.shorten(anchors[i].outH, by: k)
            }
        }
        return Subpath(anchors: anchors, closed: sp.closed)
    }

    /// A handle scaled down, and dropped outright once it is too short to bend
    /// anything the eye can find.
    ///
    /// Not a micro-optimisation: the samples here are a couple of points apart,
    /// so a handle a quarter of a point long is a curve with nowhere to curve.
    /// Saying `line` instead of `curve` for those is the difference between a
    /// frame that paints in twenty milliseconds and one that takes forty.
    private static func shorten(_ h: CGPoint, by k: CGFloat) -> CGPoint {
        let scaled = h * k
        return scaled.length < 0.25 ? .zero : scaled
    }

    /// The control polygon's length, which is an upper bound on the curve's and
    /// costs nothing to find. Enough to choose a sampling step by.
    private static func roughLength(_ sp: Subpath) -> CGFloat {
        let a = sp.anchors
        guard a.count >= 2 else { return 0 }
        var total: CGFloat = 0
        let last = sp.closed ? a.count : a.count - 1
        for i in 0..<last {
            let p = a[i], q = a[(i + 1) % a.count]
            let c0 = p.p + p.outH, c1 = q.p + q.inH
            total += p.p.dist(c0) + c0.dist(c1) + c1.dist(q.p)
        }
        return total
    }

    /// The subpath as a polyline, roughly `step` apart.
    private static func walk(_ sp: Subpath, step: CGFloat) -> [CGPoint] {
        let anchors = sp.anchors
        guard anchors.count >= 2 else { return anchors.map { $0.p } }
        var pts: [CGPoint] = [anchors[0].p]
        let last = sp.closed ? anchors.count : anchors.count - 1
        for i in 0..<last {
            let a = anchors[i], b = anchors[(i + 1) % anchors.count]
            let c0 = a.p + a.outH, c1 = b.p + b.inH
            // The control polygon's length is an upper bound on the curve's, and
            // over-sampling a little is cheaper than solving for arc length.
            let rough = a.p.dist(c0) + c0.dist(c1) + c1.dist(b.p)
            let n = max(1, Int((rough / step).rounded(.up)))
            for k in 1...n {
                pts.append(Curve.point((a.p, c0, c1, b.p), at: CGFloat(k) / CGFloat(n)))
            }
        }
        if sp.closed { pts.removeLast() }
        return pts
    }
}
