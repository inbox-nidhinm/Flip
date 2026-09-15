import AppKit
import SwiftUI

/// The pointer over the canvas, drawn from the artwork in `CursorArt`.
///
/// Built once per cursor and kept: `NSCursor` is handed to AppKit on every
/// cursor-rect rebuild, and rasterising a handful of paths each time would be
/// wasted work. Holding one instance also means `===` can answer "did the cursor
/// actually change", which is what keeps the canvas from invalidating its rects
/// on every model update.
enum FlipCursor {
    /// The grid the artwork is drawn on.
    static let grid: CGFloat = 32

    /// Drawn a fifth larger than the grid. A pointer has to hold its own against
    /// the drawing beneath it, and at 1:1 these read small next to the system
    /// arrow. The artwork is vector and the hot spot is scaled with it, so this
    /// is the only number that has to change.
    static let scale: CGFloat = 1.2

    /// The size the cursor is actually drawn at.
    static var size: CGFloat { grid * scale }

    private static var cache: [CursorArt: NSCursor] = [:]

    /// The closed hand, for while the artboard is actually being dragged. The
    /// open hand says *you could*; this one says *you are*, and without it a pan
    /// gives no feedback at all — the artwork moves under a pointer that has not
    /// changed.
    static var grabbing: NSCursor { cursor(.handGrabbed) }

    /// The bone tool is the one tool whose pointer depends on more than which
    /// tool it is: placing and posing are two jobs done with one tool, and the
    /// pointer is the only thing on screen that says which one a click will do.
    static func forTool(_ tool: Tool, boneMode: BoneMode = .place) -> NSCursor {
        switch tool {
        case .select:           return cursor(.cursor)
        case .hand:             return cursor(.hand)
        case .brush:            return cursor(.brush)
        case .bezier:           return cursor(.penTool)
        case .rect, .ellipse:   return cursor(.shape)
        case .bone:             return cursor(boneMode == .place ? .bonePointer : .jointMover)
        }
    }

    /// The pointer over the selection's transform box.
    ///
    /// Chosen by the direction the grip actually faces **on screen**, not by
    /// which corner of the box it is — so once the box has been turned, the top
    /// bar of a shape lying on its side gets the sideways arrows, and the turn
    /// zone off its top-left corner gets the pointer for whichever corner of the
    /// screen that has become. There are four stretch drawings covering eight
    /// directions at 45° apart, and four turn drawings covering the quadrants, so
    /// this is a question of finding the nearest one.
    static func forTarget(_ target: TransformTarget, in box: OrientedBox) -> NSCursor {
        switch target {
        case .scale(let grip):
            return cursor(stretch(box.direction(grip)))
        case .rotate(let grip):
            return cursor(turn(box.direction(grip)))
        }
    }

    /// The stretch drawing for a direction. Only the *axis* matters — an arrow
    /// pointing along it points both ways — so opposite directions land on the
    /// same one, and the four cover the circle in 45° steps.
    private static func stretch(_ d: CGPoint) -> CursorArt {
        switch axis(of: d) {
        case 0:  return .transformHorizontal
        case 1:  return .transformNWSE      // down and to the right
        case 2:  return .transformVertical
        default: return .transformNESW      // up and to the right
        }
    }

    /// Which of the four axes a direction is closest to, counting 45° at a time
    /// from horizontal. Y runs down, so the second step is towards the
    /// bottom-right — the axis a top-left and a bottom-right corner share.
    private static func axis(of d: CGPoint) -> Int {
        let step = CGFloat.pi / 4
        let turns = (atan2(d.y, d.x) / step).rounded()
        // Four axes, not eight directions: an arrow is symmetric about its line.
        return ((Int(turns) % 4) + 4) % 4
    }

    /// The turn drawing for a corner, by the quadrant it now points into.
    private static func turn(_ d: CGPoint) -> CursorArt {
        switch (d.x >= 0, d.y >= 0) {
        case (false, false): return .rotateTopLeft
        case (true, false):  return .rotateTopRight
        case (false, true):  return .rotateBottomLeft
        case (true, true):   return .rotateBottomRight
        }
    }

    static func cursor(_ art: CursorArt) -> NSCursor {
        if let hit = cache[art] { return hit }
        let hotSpot = CGPoint(x: art.hotSpot.x * scale, y: art.hotSpot.y * scale)
        let made = NSCursor(image: image(art), hotSpot: hotSpot)
        cache[art] = made
        return made
    }

    /// `flipped: true` gives the drawing handler a y-down context, which is the
    /// space the SVG path data is already in — so the artwork needs no transform
    /// and the hot spot's coordinates carry over as written.
    private static func image(_ art: CursorArt) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Scale the context rather than the paths, so stroke widths grow with
            // the artwork and the outline stays in proportion to the body.
            ctx.scaleBy(x: scale, y: scale)
            for stroke in art.strokes { draw(stroke, in: ctx) }
            return true
        }
    }

    private static func draw(_ s: CursorStroke, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setLineJoin(join(s.join))
        ctx.setLineCap(cap(s.cap))
        ctx.addPath(IconPath.parse(s.d).cgPath)

        let fill = colour(s.fill)
        let line = colour(s.stroke)
        if let fill { ctx.setFillColor(fill) }
        if let line { ctx.setStrokeColor(line); ctx.setLineWidth(s.width) }

        switch (fill != nil, line != nil) {
        case (true, true):   ctx.drawPath(using: .fillStroke)
        case (true, false):  ctx.fillPath()
        case (false, true):  ctx.strokePath()
        case (false, false): ctx.beginPath()      // nothing to paint; drop the path
        }
    }

    private static func colour(_ name: String?) -> CGColor? {
        guard let name, name != "none" else { return nil }
        switch name.lowercased() {
        case "white": return CGColor(gray: 1, alpha: 1)
        case "black": return CGColor(gray: 0, alpha: 1)
        default:
            // #RGB or #RRGGBB, in case the artwork ever stops being monochrome.
            var hex = name
            if hex.hasPrefix("#") { hex.removeFirst() }
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
            return CGColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }

    private static func join(_ name: String?) -> CGLineJoin {
        switch name {
        case "bevel": return .bevel
        case "miter": return .miter
        default:      return .round
        }
    }

    private static func cap(_ name: String?) -> CGLineCap {
        switch name {
        case "butt":   return .butt
        case "square": return .square
        default:       return .round
        }
    }
}

// MARK: - Claiming a region for a cursor

/// Gives whatever it is laid over its own cursor.
///
/// The canvas covers the whole window and the panels float on top of it, so the
/// canvas cannot know where they are — and its cursor rect would otherwise apply
/// underneath them too, leaving a paintbrush hovering over the layer list. AppKit
/// resolves cursor rects per view and the topmost view under the pointer wins, so
/// each floating card takes the arrow back simply by being on top. It never takes
/// a click: `hitTest` returns nil, so the controls it sits behind are untouched.
struct CursorArea: NSViewRepresentable {
    var cursor: NSCursor = .arrow

    func makeNSView(context: Context) -> Area {
        let view = Area()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: Area, context: Context) {
        guard view.cursor !== cursor else { return }
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }

    final class Area: NSView {
        var cursor: NSCursor = .arrow

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: cursor)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
