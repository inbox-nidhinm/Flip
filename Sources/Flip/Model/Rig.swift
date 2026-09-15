import CoreGraphics
import Foundation

/// One bone of a posing armature.
///
/// The pose is stored as a *local* angle relative to the parent, which is what
/// makes a chain follow its root for free. Rest and pose are carried side by
/// side because binding is computed against rest and deformation against the
/// difference between the two.
///
/// Document space here is y-down like the rest of Flip, so angles read
/// clockwise. Nothing in the maths cares which way it is.
struct Bone: Codable, Equatable {
    var parent: Int?
    var length: CGFloat
    /// The length the shape was bound at. `length` may differ once a bone has
    /// been stretched, and the ratio is what drives squash along the bone.
    var restLength: CGFloat

    var restLocalAngle: CGFloat
    var localAngle: CGFloat

    /// Only meaningful when `parent` is nil; a child hangs off its parent's tip.
    var restRootOrigin: CGPoint
    var rootOrigin: CGPoint

    // Resolved by `Skeleton.solve()`, not stored in the document.
    var restOrigin: CGPoint = .zero
    var restWorldAngle: CGFloat = 0
    var origin: CGPoint = .zero
    var worldAngle: CGFloat = 0

    enum CodingKeys: String, CodingKey {
        case parent, length, restLength, restLocalAngle, localAngle, restRootOrigin, rootOrigin
    }

    var restTip: CGPoint {
        CGPoint(x: restOrigin.x + cos(restWorldAngle) * restLength,
                y: restOrigin.y + sin(restWorldAngle) * restLength)
    }
    var tip: CGPoint {
        CGPoint(x: origin.x + cos(worldAngle) * length,
                y: origin.y + sin(worldAngle) * length)
    }
    var isRoot: Bool { parent == nil }
}

/// One armature. A frame may hold several, each driving its own layers.
struct Skeleton: Codable, Equatable {
    /// Invariant: a bone's parent always sits at a lower index, so one forward
    /// pass resolves the whole hierarchy. Creation order guarantees it.
    var bones: [Bone] = []

    var isEmpty: Bool { bones.isEmpty }

    enum CodingKeys: String, CodingKey { case bones }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bones = try c.decode([Bone].self, forKey: .bones)
        solve()
    }

    mutating func solve() {
        for i in bones.indices {
            if let p = bones[i].parent, p < i {
                bones[i].restOrigin     = bones[p].restTip
                bones[i].restWorldAngle = bones[p].restWorldAngle + bones[i].restLocalAngle
                bones[i].origin         = bones[p].tip
                bones[i].worldAngle     = bones[p].worldAngle + bones[i].localAngle
            } else {
                bones[i].restOrigin     = bones[i].restRootOrigin
                bones[i].restWorldAngle = bones[i].restLocalAngle
                bones[i].origin         = bones[i].rootOrigin
                bones[i].worldAngle     = bones[i].localAngle
            }
        }
    }

    // MARK: Building

    @discardableResult
    mutating func addBone(from a: CGPoint, to b: CGPoint, parent: Int?) -> Int {
        let length = a.dist(b)
        let world  = atan2(b.y - a.y, b.x - a.x)

        var bone = Bone(parent: parent, length: length, restLength: length,
                        restLocalAngle: world, localAngle: world,
                        restRootOrigin: a, rootOrigin: a)
        if let p = parent {
            bone.restLocalAngle = world - bones[p].restWorldAngle
            bone.localAngle     = world - bones[p].worldAngle
        }
        bones.append(bone)
        solve()
        return bones.count - 1
    }

    // MARK: Posing

    mutating func resetPose() {
        for i in bones.indices {
            bones[i].localAngle = bones[i].restLocalAngle
            bones[i].rootOrigin = bones[i].restRootOrigin
            bones[i].length     = bones[i].restLength
        }
        solve()
    }

    /// Forward kinematics: point one bone at the cursor. Children keep their
    /// local angles, so the rest of the chain swings along rigidly.
    mutating func aim(_ i: Int, at target: CGPoint, stretch: Bool) {
        let o = bones[i].origin
        let want = atan2(target.y - o.y, target.x - o.x)
        let parentWorld = bones[i].parent.map { bones[$0].worldAngle } ?? 0
        bones[i].localAngle = want - parentWorld
        if stretch { bones[i].length = max(o.dist(target), 4) }
        solve()
    }

    /// Cyclic-coordinate-descent IK: drag one tip and let a few ancestors
    /// rearrange to reach it. Cheap, unconditionally stable, no joint limits.
    mutating func reach(_ effector: Int, to target: CGPoint, depth: Int, iterations: Int = 10) {
        var chain: [Int] = []
        var cursor: Int? = effector
        while let c = cursor, chain.count < depth {
            chain.append(c)
            cursor = bones[c].parent
        }
        for _ in 0..<iterations {
            for j in chain {
                let pivot = bones[j].origin
                let tip   = bones[effector].tip
                let have  = atan2(tip.y - pivot.y, tip.x - pivot.x)
                let want  = atan2(target.y - pivot.y, target.x - pivot.x)
                bones[j].localAngle += want - have
                solve()
            }
        }
    }

    mutating func translateRoot(_ i: Int, to p: CGPoint) {
        guard bones.indices.contains(i), bones[i].isRoot else { return }
        bones[i].rootOrigin = p
        solve()
    }

    var isPosed: Bool {
        bones.contains {
            abs($0.localAngle - $0.restLocalAngle) > 1e-4
                || $0.rootOrigin.dist($0.restRootOrigin) > 1e-4
                || abs($0.length - $0.restLength) > 1e-4
        }
    }

    /// Perpendicular distance from `p` to a bone's rest segment. Binding works in
    /// rest space, so this is the only distance the weights ever need.
    static func distanceToRest(_ p: CGPoint, _ b: Bone) -> CGFloat {
        let a = b.restOrigin, e = b.restTip
        let vx = e.x - a.x, vy = e.y - a.y
        let len2 = vx * vx + vy * vy
        if len2 < 1e-9 { return p.dist(a) }
        var t = ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2
        t = min(max(t, 0), 1)
        return p.dist(CGPoint(x: a.x + t * vx, y: a.y + t * vy))
    }
}
