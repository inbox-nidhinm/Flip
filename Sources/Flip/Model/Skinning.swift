import CoreGraphics
import Foundation

struct Weight {
    var bone: Int
    var value: CGFloat
}

/// The blended local transform one point ends up under.
///
/// Kept as a value rather than a `CGAffineTransform` because an anchor and its
/// handles need *different* parts of it: the anchor takes the whole thing,
/// while a handle is an offset from its anchor and so takes the linear part
/// with none of the translation. Flip stores handles as offsets precisely so
/// that moving an anchor carries its curvature along, and skinning has to
/// respect that or every deformed joint kinks.
struct SkinFrame {
    var rotation: CGFloat = 0
    var stretch: CGFloat = 1
    /// The rest axis that `stretch` acts along, so lengthening a bone lengthens
    /// the drawing instead of inflating it.
    var axis: CGFloat = 0
    var restPivot: CGPoint = .zero
    var posePivot: CGPoint = .zero

    /// Stretch in the rest-axis frame, then rotate. No translation.
    private func linear(_ v: CGPoint) -> CGPoint {
        let ca = cos(axis), sa = sin(axis)
        let along = (v.x * ca + v.y * sa) * stretch
        let perp  = -v.x * sa + v.y * ca
        let sx = along * ca - perp * sa
        let sy = along * sa + perp * ca
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: c * sx - s * sy, y: s * sx + c * sy)
    }

    func point(_ p: CGPoint) -> CGPoint {
        let v = linear(CGPoint(x: p.x - restPivot.x, y: p.y - restPivot.y))
        return CGPoint(x: posePivot.x + v.x, y: posePivot.y + v.y)
    }

    /// A handle keeps its anchor as its origin, so it takes only the linear part.
    func handle(_ v: CGPoint) -> CGPoint { linear(v) }
}

enum Skin {
    /// How many bones may influence one anchor. Three crosses a joint smoothly
    /// without letting a distant limb tug on the whole silhouette.
    static let influences = 3
    /// Inverse-distance exponent. Higher is more local. Chosen over a tuned
    /// falloff radius so there is one fewer number to guess.
    static let falloff: CGFloat = 3

    /// Weights for one anchor, against *rest* geometry — which makes binding
    /// idempotent and safe to recompute whenever anything changes, so nothing
    /// has to be cached or invalidated.
    ///
    /// Ownership has already decided *whether* a layer may move at all. This
    /// only divides an owned layer's anchors between the bones of its own rig.
    static func weights(for p: CGPoint, in skeleton: Skeleton) -> [Weight] {
        guard !skeleton.isEmpty else { return [] }

        var candidates: [(Int, CGFloat)] = []
        candidates.reserveCapacity(skeleton.bones.count)
        for i in skeleton.bones.indices {
            candidates.append((i, Skeleton.distanceToRest(p, skeleton.bones[i])))
        }
        candidates.sort { $0.1 < $1.1 }
        let nearest = candidates.prefix(influences)

        var raw: [(Int, CGFloat)] = []
        var total: CGFloat = 0
        for (i, d) in nearest {
            // A bone reaches a few multiples of its own length and no further, so
            // one long bone cannot drag the far end of a large layer it owns.
            guard d <= max(skeleton.bones[i].restLength * 3, 80) else { continue }
            let w = 1 / pow(d + 0.5, falloff)
            raw.append((i, w))
            total += w
        }
        // An owned layer always follows its rig. If every bone is out of reach,
        // the nearest one carries it rigidly rather than stranding it mid-pose.
        guard total > 0 else {
            return nearest.first.map { [Weight(bone: $0.0, value: 1)] } ?? []
        }
        return raw.map { Weight(bone: $0.0, value: $0.1 / total) }
    }

    /// Blend each influencing bone's *frame*, rather than blending the positions
    /// each bone would put the point at, as linear blend skinning does. Every
    /// point then lands under a rotate-translate-stretch with no shear, which is
    /// what removes the pinching at bends.
    static func frame(for p: CGPoint, weights: [Weight], skeleton: Skeleton) -> SkinFrame {
        guard !weights.isEmpty else { return SkinFrame(restPivot: p, posePivot: p) }

        var cosSum: CGFloat = 0, sinSum: CGFloat = 0
        var axisCos: CGFloat = 0, axisSin: CGFloat = 0
        var restPivot = CGPoint.zero, posePivot = CGPoint.zero
        var stretch: CGFloat = 0

        for w in weights {
            guard skeleton.bones.indices.contains(w.bone) else { continue }
            let b = skeleton.bones[w.bone]
            let delta = b.worldAngle - b.restWorldAngle
            cosSum  += w.value * cos(delta)
            sinSum  += w.value * sin(delta)
            axisCos += w.value * cos(b.restWorldAngle)
            axisSin += w.value * sin(b.restWorldAngle)
            restPivot.x += w.value * b.restOrigin.x
            restPivot.y += w.value * b.restOrigin.y
            posePivot.x += w.value * b.origin.x
            posePivot.y += w.value * b.origin.y
            stretch += w.value * (b.restLength > 0.001 ? b.length / b.restLength : 1)
        }

        return SkinFrame(rotation: atan2(sinSum, cosSum),
                         stretch: stretch,
                         axis: atan2(axisSin, axisCos),
                         restPivot: restPivot,
                         posePivot: posePivot)
    }

    /// The shape as the pose leaves it. The stored geometry is always the rest
    /// pose — posing never writes to the artwork — so this runs at draw time and
    /// the document keeps only one copy of the drawing.
    static func deform(_ shape: Shape2D, with skeleton: Skeleton) -> Shape2D {
        guard !skeleton.isEmpty, skeleton.isPosed else { return shape }
        var out = shape
        for si in out.subpaths.indices {
            for ai in out.subpaths[si].anchors.indices {
                let a = out.subpaths[si].anchors[ai]
                let f = frame(for: a.p, weights: weights(for: a.p, in: skeleton), skeleton: skeleton)
                out.subpaths[si].anchors[ai].p    = f.point(a.p)
                out.subpaths[si].anchors[ai].inH  = f.handle(a.inH)
                out.subpaths[si].anchors[ai].outH = f.handle(a.outH)
            }
        }
        return out
    }
}
