import AppKit
import CoreGraphics

/// The measurements of the selection's transform box. In **view** points, not
/// document ones, so a grip is the same size to see and to grab at any zoom —
/// the same reasoning as the point tool's anchors and handles.
enum TransformBox {
    /// The side of a corner grip's square.
    static let grip: CGFloat = 8

    /// How far outside the artwork the box is drawn. Matches the outset the
    /// selection outline already used, so turning the box on did not move the
    /// line that was there before it.
    static let outset: CGFloat = 1.5

    /// How far clear of the box a turn begins — and, because the two meet exactly
    /// rather than overlapping, how far a corner's own grab region reaches out.
    /// One number for both, so there is no seam between them where the pointer
    /// would mean neither thing.
    static let gap: CGFloat = 6

    /// How far out the turn zone runs before the pointer is over plain canvas
    /// again. Without a limit, a click anywhere in an empty artboard near a
    /// selection would turn it instead of starting a marquee.
    static let reach: CGFloat = 22

    /// Slack either side of a bar. A 1px line is not a target, and a bar has no
    /// width of its own — the box's edge *is* the bar.
    static let slop: CGFloat = 3

    /// A bar needs some clear edge left between the two corner regions to be
    /// worth offering. Below this the corners already cover the whole side.
    static let shortestBar: CGFloat = gap * 2 + 4
}

/// One of the eight grips on a selection's bounding box.
///
/// All eight **stretch**: the four bars along the axis they run across, the four
/// corners along both at once. The visible edge of the box *is* the bar, so the
/// only things drawn are the four corner squares.
///
/// Turning lives in the clear space just outside each corner — see `turns`.
/// Nothing is drawn out there on purpose: the grip you can see is the one that
/// resizes, and a second control 6pt off the corner would crowd the very corner
/// it is meant to be distinct from. The pointer is what announces it.
enum TransformGrip: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Corners first: the two ends of every bar overlap a corner region, and the
    /// corner is the one that should win there — it is the grip you can actually
    /// see, so it is the one you meant to grab.
    static let hitOrder: [TransformGrip] = [
        .topLeft, .topRight, .bottomRight, .bottomLeft,
        .top, .bottom, .left, .right,
    ]

    /// In order round the box, so a path drawn through them closes correctly.
    static let corners: [TransformGrip] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

    /// Where the grip sits in the box, 0…1 in each axis. Y runs down, matching
    /// the canvas and the document.
    var unit: CGPoint {
        switch self {
        case .topLeft:      return CGPoint(x: 0, y: 0)
        case .top:          return CGPoint(x: 0.5, y: 0)
        case .topRight:     return CGPoint(x: 1, y: 0)
        case .right:        return CGPoint(x: 1, y: 0.5)
        case .bottomRight:  return CGPoint(x: 1, y: 1)
        case .bottom:       return CGPoint(x: 0.5, y: 1)
        case .bottomLeft:   return CGPoint(x: 0, y: 1)
        case .left:         return CGPoint(x: 0, y: 0.5)
        }
    }

    var isCorner: Bool { unit.x != 0.5 && unit.y != 0.5 }

    /// Whether this grip drives that axis. A bar sits at the midpoint of the axis
    /// it does not drive, which is exactly what makes it a one-axis control.
    var scalesX: Bool { unit.x != 0.5 }
    var scalesY: Bool { unit.y != 0.5 }

    /// The point that holds still: the opposite corner, or the opposite edge.
    ///
    /// An axis the grip does not drive anchors at the **centre**, which is what a
    /// locked drag on a bar needs — the box then grows symmetrically across that
    /// axis instead of dragging one of its sides along for the ride.
    var anchorUnit: CGPoint {
        CGPoint(x: scalesX ? 1 - unit.x : 0.5,
                y: scalesY ? 1 - unit.y : 0.5)
    }

    /// Which way is *out of* the box at this grip: one axis for a bar, the
    /// diagonal for a corner. The pointer uses it to work out which way the grip
    /// faces on screen once the box itself has been turned.
    var outward: CGPoint {
        CGPoint(x: unit.x == 0.5 ? 0 : (unit.x == 0 ? -1 : 1),
                y: unit.y == 0.5 ? 0 : (unit.y == 0 ? -1 : 1))
    }

    func point(in r: CGRect) -> CGPoint { Self.at(unit, in: r) }
    func anchor(in r: CGRect) -> CGPoint { Self.at(anchorUnit, in: r) }

    private static func at(_ u: CGPoint, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + u.x * r.width, y: r.minY + u.y * r.height)
    }

    /// Whether a point, in the same space as the rect it is given, takes hold of
    /// this grip to stretch by.
    ///
    /// A corner reaches **strictly less than** `gap` in each direction, so it
    /// stops exactly where the turn zone begins: the two tile the ground around
    /// the corner with no overlap and no seam between them. A `CGRect` could not
    /// say that — `contains` is half-open, so a rect takes a point on its leading
    /// edge and refuses the matching one on its trailing edge, which would leave
    /// the corner a point wider on one side than the other and hand the turn zone
    /// its first row away.
    func grabs(_ p: CGPoint, in r: CGRect) -> Bool {
        guard !isCorner else {
            let c = point(in: r)
            return abs(p.x - c.x) < TransformBox.gap && abs(p.y - c.y) < TransformBox.gap
        }
        return barRect(in: r)?.contains(p) == true
    }

    /// The stretch of edge a bar answers for: whatever is left between the two
    /// corner regions, given thickness by the slop alone, since the box's own
    /// edge is the bar and has no width. `nil` when there is no room left, in
    /// which case the bar is simply not offered.
    func barRect(in r: CGRect) -> CGRect? {
        guard !isCorner else { return nil }
        let c = point(in: r)
        let inset = TransformBox.gap
        if scalesY {   // a horizontal bar, running the width of the box
            guard r.width >= TransformBox.shortestBar else { return nil }
            return CGRect(x: r.minX + inset, y: c.y - TransformBox.slop,
                          width: r.width - inset * 2, height: TransformBox.slop * 2)
        }
        guard r.height >= TransformBox.shortestBar else { return nil }
        return CGRect(x: c.x - TransformBox.slop, y: r.minY + inset,
                      width: TransformBox.slop * 2, height: r.height - inset * 2)
    }

    /// Whether a point turns the selection rather than stretching it: out past
    /// both of this corner's edges, at least `gap` clear of the box in one axis
    /// so the corner's own grip keeps its target, and no further out than
    /// `reach`, past which the pointer is over canvas again.
    func turns(_ p: CGPoint, in r: CGRect) -> Bool {
        guard isCorner else { return false }
        let c = point(in: r), out = outward
        // Measured outward, so both numbers grow as the pointer leaves the box.
        let u = (p.x - c.x) * out.x
        let v = (p.y - c.y) * out.y
        guard u >= 0, v >= 0, u <= TransformBox.reach, v <= TransformBox.reach else { return false }
        return max(u, v) >= TransformBox.gap
    }

    /// The square drawn at a corner.
    func gripRect(in r: CGRect) -> CGRect {
        let c = point(in: r), half = TransformBox.grip / 2
        return CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2)
    }
}

/// What the pointer would do where it is.
enum TransformTarget {
    case scale(TransformGrip)
    /// The turn zone outside a corner. Every corner turns the selection about the
    /// same centre, so which one it is matters only to the pointer.
    case rotate(TransformGrip)
}

// MARK: - The box

/// The selection's box: its extent in the selection's **own** frame, the angle
/// that frame is turned by, and the point it turns about.
///
/// An upright selection is the ordinary case and comes out with `angle == 0`,
/// where this is a plain bounding box and every rotation below is the identity.
struct OrientedBox {
    /// Axis-aligned — in the selection's own frame, not the document's.
    let local: CGRect
    /// The point that frame turns about, in the enclosing space.
    let pivot: CGPoint
    let angle: CGFloat

    var isUpright: Bool { angle == 0 }

    /// Into the box's own frame, where the box is an ordinary rectangle and all
    /// the grip arithmetic above applies unchanged.
    func toLocal(_ p: CGPoint) -> CGPoint {
        isUpright ? p : p.applying(.about(pivot, .rotation(-angle)))
    }

    /// Back out of it.
    func toWorld(_ p: CGPoint) -> CGPoint {
        isUpright ? p : p.applying(.about(pivot, .rotation(angle)))
    }

    /// A grip's position in the enclosing space.
    func world(_ grip: TransformGrip) -> CGPoint { toWorld(grip.point(in: local)) }

    /// The centre, in the enclosing space — what a turn goes about.
    var centre: CGPoint { toWorld(CGPoint(x: local.midX, y: local.midY)) }

    /// Which way a grip faces in the enclosing space, once the box's own turn is
    /// taken into account. This is what lets the pointer stay right on a box that
    /// is no longer square to the artboard.
    func direction(_ grip: TransformGrip) -> CGPoint {
        grip.outward.applying(.rotation(angle))
    }

    /// The same box in another space reached by a uniform scale and a
    /// translation — which is exactly what the canvas's document-to-view
    /// transform is, so the angle carries over untouched.
    func mapped(rect: (CGRect) -> CGRect, point: (CGPoint) -> CGPoint) -> OrientedBox {
        OrientedBox(local: rect(local), pivot: point(pivot), angle: angle)
    }

    /// Grown on every side, in the box's own frame.
    func outset(by d: CGFloat) -> OrientedBox {
        OrientedBox(local: local.insetBy(dx: -d, dy: -d), pivot: pivot, angle: angle)
    }

    /// What the pointer would do at `p`, given in the enclosing space. Corners
    /// win the ends of a bar; the turn zones sit entirely outside the box, so
    /// they cannot be reached until every stretching grip has been ruled out.
    func target(at p: CGPoint) -> TransformTarget? {
        let q = toLocal(p)
        if let grip = TransformGrip.hitOrder.first(where: { $0.grabs(q, in: local) }) {
            return .scale(grip)
        }
        if let grip = TransformGrip.corners.first(where: { $0.turns(q, in: local) }) {
            return .rotate(grip)
        }
        return nil
    }
}

// MARK: - Drags

/// A stretch in progress.
///
/// All the arithmetic happens in the box's **own** frame and the result is
/// carried back into the document's. That is what makes a bar on a turned
/// selection stretch it along its own axis rather than the artboard's — which is
/// the whole point of the box turning with the shape.
struct TransformDrag {
    let grip: TransformGrip
    let box: OrientedBox
    /// The point that holds still, in the box's frame.
    let anchor: CGPoint
    /// Where the grip was when the drag began, in the box's frame.
    let start: CGPoint
    /// Where the pointer sat within the grip. Carried so the box follows the
    /// pointer from wherever it was taken hold of, rather than snapping the grip
    /// under the pointer on the first move.
    let offset: CGPoint

    init(grip: TransformGrip, box: OrientedBox, pointer: CGPoint) {
        self.grip = grip
        self.box = box
        anchor = grip.anchor(in: box.local)
        start = grip.point(in: box.local)
        let local = box.toLocal(pointer)
        offset = CGPoint(x: local.x - start.x, y: local.y - start.y)
    }

    /// A selection with no extent on an axis cannot be scaled along it — there is
    /// no starting distance for a factor to be a multiple of. A straight
    /// horizontal line is the ordinary case of this, not a pathological one.
    private static let flat: CGFloat = 0.001

    /// The scale factors for a pointer at `local`, given in the box's own frame.
    ///
    /// **Free by default.** Each axis is the ratio of how far the pointer is from
    /// the anchor now to how far the grip was from it to begin with — so a corner
    /// stretches both axes independently, and a bar stretches only its own.
    ///
    /// **Shift locks them together.** A corner takes the single factor from
    /// whichever axis the pointer pushed furthest; a bar drives both axes from the
    /// one it runs across, about the box's centre in the other — so a locked pull
    /// on the top bar grows the box symmetrically sideways rather than dragging
    /// its left edge along with it.
    func factors(atLocal local: CGPoint, locked: Bool) -> (x: CGFloat, y: CGFloat) {
        let q = CGPoint(x: local.x - offset.x, y: local.y - offset.y)
        let dx = start.x - anchor.x
        let dy = start.y - anchor.y
        let liveX = grip.scalesX && abs(dx) > Self.flat
        let liveY = grip.scalesY && abs(dy) > Self.flat
        let sx = liveX ? (q.x - anchor.x) / dx : 1
        let sy = liveY ? (q.y - anchor.y) / dy : 1
        guard locked else { return (sx, sy) }

        let one: CGFloat
        switch (liveX, liveY) {
        // Distance from 1, not magnitude: dragging a corner mostly sideways to
        // *shrink* gives a small sx and an sy near 1, and the axis that actually
        // moved is the smaller of the two numbers.
        case (true, true):   one = abs(sx - 1) >= abs(sy - 1) ? sx : sy
        case (true, false):  one = sx
        case (false, true):  one = sy
        case (false, false): one = 1
        }
        return (one, one)
    }

    /// The whole thing as one transform in the enclosing space: into the box's
    /// frame, stretch, back out again.
    func transform(at p: CGPoint, locked: Bool) -> CGAffineTransform {
        let f = factors(atLocal: box.toLocal(p), locked: locked)
        let stretch = CGAffineTransform.about(anchor, CGAffineTransform(scaleX: f.x, y: f.y))
        guard !box.isUpright else { return stretch }
        return CGAffineTransform.about(box.pivot, .rotation(-box.angle))
            .concatenating(stretch)
            .concatenating(.about(box.pivot, .rotation(box.angle)))
    }
}

/// A turn in progress.
///
/// Tracks the *change* in the angle from the centre to the pointer, not the angle
/// itself, so the selection turns with the drag from wherever it was taken hold
/// of rather than snapping that spot under the pointer.
struct RotateDrag {
    /// The centre of the selection's box, which is what it turns about.
    let pivot: CGPoint
    /// The angle from the pivot to the pointer when the drag began.
    let start: CGFloat

    /// A locked turn lands on one of these. 15° divides the right angle five ways
    /// and the circle twenty-four, so the cardinals and the diagonals are all on
    /// it.
    static let step: CGFloat = .pi / 12

    init(box: OrientedBox, pointer: CGPoint) {
        pivot = box.centre
        start = RotateDrag.angle(of: pointer, about: pivot)
    }

    private static func angle(of p: CGPoint, about c: CGPoint) -> CGFloat {
        atan2(p.y - c.y, p.x - c.x)
    }

    /// How far to turn for a pointer at `p`.
    ///
    /// **Free by default.** Holding shift locks the turn to 15° steps — of the
    /// *change*, because stepping from wherever the shape already was keeps the
    /// steps even whatever angle that is.
    func angle(at p: CGPoint, locked: Bool) -> CGFloat {
        var delta = RotateDrag.angle(of: p, about: pivot) - start
        // Shortest way round, so a drag across the -pi/pi seam does not spin the
        // shape the long way about.
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        guard locked else { return delta }
        return (delta / RotateDrag.step).rounded() * RotateDrag.step
    }

    /// The turn as one transform.
    func transform(at p: CGPoint, locked: Bool) -> CGAffineTransform {
        .about(pivot, .rotation(angle(at: p, locked: locked)))
    }
}
