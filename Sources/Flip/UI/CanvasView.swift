import SwiftUI
import AppKit

/// The drawing surface.
///
/// An `NSView` rather than SwiftUI's `Canvas` because this needs modifier keys,
/// hover, scroll-wheel panning and point-accurate hit testing, none of which a
/// gesture recogniser gives cleanly. The view is flipped, so document space is
/// y-down and matches SVG's — the export needs no coordinate flip.
struct CanvasView: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeNSView(context: Context) -> Surface {
        let view = Surface()
        view.model = model
        // `clipsToBounds` is false by default on current macOS, and an artboard
        // larger than the viewport is drawn past the view's edges — over
        // whatever SwiftUI laid out *before* the canvas, which is the left panel
        // and the title bar. Later siblings paint over it and look fine, which
        // is why only two of the four edges appeared broken.
        view.clipsToBounds = true
        return view
    }

    func updateNSView(_ view: Surface, context: Context) {
        view.model = model
        view.toolCursor = FlipCursor.forTool(model.tool, boneMode: model.boneMode)
        // Putting the pen down finishes whatever it was drawing. So does stepping
        // to another frame, where the path being drawn does not exist.
        //
        // Hopped to the next runloop turn because finishing can delete a layer,
        // and mutating the model from inside `updateNSView` is a write during a
        // SwiftUI update — undefined, and in practice it corrupted the tool
        // selection and the path being drawn. Guarded on there actually being a
        // run, so the common case schedules nothing.
        if view.hasPen, model.tool != .bezier || view.penFrame != model.frameIndex {
            DispatchQueue.main.async { view.finishPen() }
        }
        view.needsDisplay = true
    }
}

// MARK: - Surface

final class Surface: NSView {
    var model: AppModel!

    /// The pointer while over the canvas. The floating panels lay their own
    /// cursor rects on top of this one, so it does not have to know where they
    /// are — see `CursorArea`. Cached by `FlipCursor`, so the identity check is
    /// enough to avoid rebuilding rects on every model change.
    var toolCursor: NSCursor? {
        didSet {
            guard toolCursor !== oldValue else { return }
            window?.invalidateCursorRects(for: self)
            // And immediately, for the same reason `panHeld` does it: switching
            // Place to Pose in the rig bar is a click nowhere near the canvas,
            // and waiting for the next mouse move to answer it reads as the
            // button not having worked.
            if !panHeld, isMouseInside { toolCursor?.set() }
        }
    }

    /// The identity the stroke in hand will be committed under.
    ///
    /// Held here rather than left to `newLayer` so the preview and the finished
    /// layer wander identically — they are the same line, and it should not
    /// change shape at the moment of letting go.
    private var strokeIdentity = UUID()

    /// Whether the pointer is over the canvas right now, kept by the tracking
    /// area below. Asking AppKit costs a window-coordinate conversion and can
    /// be wrong mid-drag; this is only ever read to decide whether setting a
    /// cursor now would be visible at all.
    private var isMouseInside = false

    /// Whether a modifier that pans is being held right now.
    ///
    /// Held as state rather than read where it is needed, because the *cursor
    /// rect* is what actually decides the pointer — calling `set()` alone was
    /// not enough, since AppKit re-asserts the rect's cursor at the next cursor
    /// update and puts the tool's pointer straight back.
    private var panHeld = false {
        didSet {
            guard panHeld != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            // And immediately, rather than waiting for the rebuild: a key press
            // should not take a mouse move to answer.
            (panHeld ? FlipCursor.forTool(.hand) : toolCursor)?.set()
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        // The modifier wins over the tool: while it is held the whole canvas
        // pans, so the whole canvas says so.
        if let cursor = panHeld ? FlipCursor.forTool(.hand) : toolCursor {
            addCursorRect(bounds, cursor: cursor)
        }
    }

    /// The pointer over the canvas, set on every move.
    ///
    /// Not a cursor rect, because the transform box's regions stop being
    /// rectangles the moment the box is turned — the bounding rectangle of a 45°
    /// bar covers the middle of the selection, so a rect would claim the cursor
    /// everywhere the bar is not, and `addCursorRect` takes nothing else. Setting
    /// it per move is what allows the exact region, turn zones included.
    ///
    /// The tool's own rect stays: it covers the pointer arriving in the view
    /// without moving, and it is what each floating panel takes back with a rect
    /// of its own.
    private func updatePointer(with event: NSEvent) {
        updatePointer(at: event.locationInWindow, event.modifierFlags)
    }

    /// The pointer recomputed from where the mouse actually is and which
    /// modifiers are actually down, rather than from an event carrying neither.
    ///
    /// `flagsChanged` is a keyboard event and its `locationInWindow` means
    /// nothing — which is exactly the moment the pointer most needs to change,
    /// since pressing ⌥ over a shape has to answer before the hand moves.
    private func refreshPointer() {
        guard let window else { return }
        updatePointer(at: window.mouseLocationOutsideOfEventStream, NSEvent.modifierFlags)
    }

    private func updatePointer(at inWindow: NSPoint, _ flags: NSEvent.ModifierFlags) {
        // Only while the canvas is genuinely the view under the pointer.
        // `mouseMoved` goes to the first responder, which is this view even when
        // the pointer is over a panel — and a resize cursor showing through the
        // layer list is the very thing the panels' own rects exist to prevent.
        guard window?.contentView?.hitTest(inWindow) === self else { return }
        // Re-read rather than trusted: a modifier let go while another app had
        // the keyboard never sends us its `flagsChanged`, and the pointer would
        // stay a hand until one was pressed again.
        panHeld = panModifier(flags)
        // Before the transform grips, because the modifier beats them at the
        // press too — holding ⌃ over a corner pans, it does not resize, and the
        // pointer has to say the same thing the click will do.
        if pans(flags) {
            FlipCursor.forTool(.hand).set()
            return
        }
        // The pen's own pointer, chosen by the same function the press reads —
        // which is the only way a cursor can promise something a click keeps.
        if model.tool == .bezier {
            switch penIntent(at: toDoc(convert(inWindow, from: nil)), flags) {
            case .insert:
                FlipCursor.cursor(.penToolAddPoints).set()
            case .close, .extend, .join:
                FlipCursor.cursor(.penToolConnectPoints).set()
            case .grabPoint, .grabHandle, .convert:
                FlipCursor.cursor(.penToolMovePoint).set()
            case .clear, .place:
                toolCursor?.set()
            }
            return
        }
        let p = convert(inWindow, from: nil)
        if let box = viewBox(), let target = box.target(at: p) {
            FlipCursor.forTarget(target, in: box).set()
        } else if wouldDuplicate(at: p, flags) {
            FlipCursor.cursor(.cursorDuplicate).set()
        } else {
            toolCursor?.set()
        }
    }

    /// Whether ⌥ here would leave a copy behind rather than do nothing in
    /// particular.
    ///
    /// After the transform grips on purpose: ⌥ over a corner is still a resize,
    /// and the pointer has to say what the press will actually do. Over bare
    /// paper it says nothing — an ⌥-drag there is a marquee, and an arrow with a
    /// copy on it would be promising a duplicate of nothing.
    ///
    /// The modifier is tested before anything is hit-tested, so the cost of
    /// this on every mouse move is one flag check until ⌥ is actually down.
    private func wouldDuplicate(at viewPoint: CGPoint, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard model.tool == .select, flags.contains(.option) else { return false }
        let p = toDoc(viewPoint)
        // The same three tests `mouseDown` makes on its way to a move, which is
        // the only thing ⌥ turns into a duplicate.
        if flags.contains(.command) { return deepLayer(at: p) != nil }
        return selectionHit(at: p) || topLayer(at: p) != nil
    }

    /// The path the pen is part way through drawing.
    ///
    /// Held on the canvas rather than the model because it is a state of the
    /// *gesture*, not of the document: the layer and its anchors are already
    /// committed after every click, so quitting mid-path leaves a real path
    /// behind and undo steps back through the points one at a time.
    private var pen: Pen?

    private struct Pen {
        let layer: UUID
        let subpath: Int
        /// The frame it belongs to. Stepping away abandons the run, since the
        /// path it is building is not in the frame you moved to.
        let frame: Int
    }

    /// Whether a path is part way through being drawn.
    var hasPen: Bool { pen != nil }

    /// Which frame the pen is drawing into, or the current one when it is idle.
    var penFrame: Int { pen?.frame ?? model?.frameIndex ?? 0 }

    /// Finish an open path from outside the gesture — a tool change, a frame step.
    func finishPen() { endPen() }

    private enum Drag {
        case none
        case stroke([CGPoint])
        case shape(CGPoint, CGPoint)
        case move(last: CGPoint)
        case node(NodeRef, CGPoint)
        case handle(NodeRef, out: Bool)
        /// Pulling the handles out of the point just placed with the pen. A click
        /// that never becomes a drag simply leaves them at zero — which is the
        /// difference between a corner and a curve.
        case penHandle(NodeRef)
        case marquee(CGPoint, CGPoint)
        case pan(CGPoint)
        case reference(last: CGPoint)
        /// Stretching the selection by one of the grips on its box.
        case scale(Scaling)
        /// Turning it, from the clear space just outside a corner.
        case rotate(Rotating)
        /// Pulling out a bone. `rig` and `parent` are set when the drag began on
        /// an existing tip, which is how a chain is built.
        case newBone(start: CGPoint, rig: Int?, parent: Int?, current: CGPoint)
        /// Moving a handle of an armature already built.
        case poseBone(rig: Int, bone: Int, root: Bool)

        /// Drags that write to the document, and so want the interface to hold
        /// still until they finish.
        var mutatesDocument: Bool {
            switch self {
            case .move, .node, .handle, .penHandle, .reference, .scale, .rotate: return true
            case .newBone, .poseBone: return true
            default: return false
            }
        }
    }

    /// A resize in progress: the grip's own arithmetic, plus the geometry it is
    /// working from.
    private struct Scaling {
        let transform: TransformDrag
        /// The selection's geometry as it stood when the drag began, keyed by
        /// layer id. Every update scales *this* rather than the previous
        /// update's result, so the factors are absolute instead of compounding:
        /// dragging a grip back through its anchor mirrors the shape, and out the
        /// far side restores it — where a running multiplication would have lost
        /// it for good the moment it passed through zero.
        let originals: [UUID: Layer]
    }

    /// A rotation in progress. Same shape as `Scaling`, and absolute from the
    /// same snapshot for the same reason: turning the previous result would
    /// accumulate rounding right round the circle, and coming back to the angle
    /// you started at would not come back to the shape you started with.
    private struct Rotating {
        let transform: RotateDrag
        let originals: [UUID: Layer]
    }

    private var drag: Drag = .none
    private var snapTarget: (NodeRef, CGPoint)?
    private var hoverPoint: CGPoint?
    /// The layer a click with the bone tool would bind or release. Canvas-side,
    /// unlike `model.hoveredLayer`, which the layers panel owns and which marks a
    /// row rather than an action.
    private var boneHover: UUID?
    private var hasFitted = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Frame the artboard the first time the view has a real size, so a document
    /// bigger than the window does not open scaled past its edges.
    override func layout() {
        super.layout()
        guard !hasFitted, bounds.width > 120, bounds.height > 120 else { return }
        hasFitted = true
        // Out of the layout pass — fitting publishes zoom and pan to the model.
        DispatchQueue.main.async { [weak self] in self?.fitToWindow() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    // MARK: Transform

    private var zoom: CGFloat { model.zoom }

    private var origin: CGPoint {
        CGPoint(x: (bounds.width - model.doc.size.width * zoom) / 2 + model.pan.x,
                y: (bounds.height - model.doc.size.height * zoom) / 2 + model.pan.y)
    }

    private func toDoc(_ p: CGPoint) -> CGPoint {
        let o = origin
        return CGPoint(x: (p.x - o.x) / zoom, y: (p.y - o.y) / zoom)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let o = origin
        return CGPoint(x: o.x + p.x * zoom, y: o.y + p.y * zoom)
    }

    private func point(_ event: NSEvent) -> CGPoint { toDoc(convert(event.locationInWindow, from: nil)) }

    /// A layer as the frame's armatures leave it. Anything that measures or hits
    /// a layer has to go through this, or on a posed layer it works against
    /// geometry the screen is not showing.
    private func posed(_ layer: Layer) -> Layer { model.frame.posed(layer) }

    /// Bone handles are larger targets than a path node: they are the whole of
    /// how a rig is posed, and there is nothing else near them to hit by mistake.
    private var boneGrab: CGFloat { 15 / zoom }

    /// Hit tolerances are in document points but should feel constant on screen.
    private var grab: CGFloat { 6 / zoom }
    private var pick: CGFloat { 4 / zoom }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, model != nil else { return }
        let doc = model.doc

        ctx.setFillColor(FlipTheme.canvas.rgba.cg)
        ctx.fill(bounds)
        drawGrain(ctx)

        let board = CGRect(origin: origin, size: CGSize(width: doc.size.width * zoom,
                                                        height: doc.size.height * zoom))
        ctx.setShadow(offset: .zero, blur: 18, color: CGColor(gray: 0, alpha: 0.45))
        ctx.setFillColor(doc.background.cg)
        ctx.fill(board)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        ctx.saveGState()
        ctx.clip(to: board)
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: zoom, y: zoom)

        drawReference(ctx)

        for ghost in model.onionLayers {
            Render.draw(ghost.frame, in: ctx, tint: ghost.tint, alpha: ghost.alpha)
        }
        Render.draw(model.frame, in: ctx)
        drawInProgress(ctx)
        ctx.restoreGState()

        ctx.setStrokeColor(FlipTheme.border.rgba.cg)
        ctx.setLineWidth(1)
        ctx.stroke(board.insetBy(dx: -0.5, dy: -0.5))

        // Nothing but the reference is live while it is being placed, so the
        // selection's box and grips would only be furniture to click by mistake.
        guard !model.isPlaying, !model.repositioning else { return }
        drawRigGhost(ctx)
        drawRig(ctx)
        drawHover(ctx)
        drawSelection(ctx)
        if model.tool == .bezier { drawSpines(ctx); drawNodes(ctx); drawPenPreview(ctx) }
        drawMarquee(ctx)
    }

    /// Under the ghosts and under the artwork. Called inside the artboard clip and
    /// the document transform, so `Render` can position it in document points.
    /// The panels' grain, laid on the canvas behind the artboard so the two
    /// surfaces read as the same material. Drawn before the board, so the
    /// artwork itself stays clean — this is the ground the board sits on, not a
    /// filter over the drawing.
    private func drawGrain(_ ctx: CGContext) {
        guard let pattern = Grain.pattern else { return }
        ctx.saveGState()
        ctx.setAlpha(FlipTheme.grain)
        pattern.setFill()
        bounds.fill()
        ctx.restoreGState()
    }

    private func drawReference(_ ctx: CGContext) {
        guard let ref = model.doc.reference, let image = model.referenceImage else { return }
        Render.drawReference(ref, image: image, in: ctx, docSize: model.doc.size)
    }

    private func drawInProgress(_ ctx: CGContext) {
        let accent = FlipTheme.accent.rgba
        switch drag {
        case .stroke(let pts):
            guard pts.count > 1 else { return }
            ctx.setStrokeColor((model.strokeEnabled ? model.strokeColor : accent).cg)
            ctx.setLineWidth(max(model.strokeWidth, 1 / zoom))
            ctx.setLineJoin(.round); ctx.setLineCap(.round)
            // Wandering as it is drawn, not once the hand comes up. The texture
            // is half of what the line *is*, and a stroke that went down smooth
            // and roughened a moment later is a stroke you cannot aim.
            //
            // Stable as the stroke grows: the wander is a function of distance
            // from the start, so what is already down does not move when more
            // is added to the end.
            let w = model.wiggle
            let live: CGPath
            if !w.isIdle {
                let raw = Subpath(anchors: pts.map { Anchor($0) }, closed: false)
                live = w.applied(to: Shape2D(subpaths: [raw]),
                                 still: Wobble.seed(strokeIdentity),
                                 moving: Wobble.seed(strokeIdentity, model.frame.id)).cgPath
            } else {
                let p = CGMutablePath()
                p.addLines(between: pts)
                live = p
            }
            // The nib too, for the same reason the wander is here: a line that
            // goes down as a pen and turns to graphite when you let go is a line
            // you cannot judge while drawing it.
            let colour = model.strokeEnabled ? model.strokeColor : accent
            if model.nib.isPencil,
               let mark = Pencil.mark(live, nib: model.nib,
                                      width: max(model.strokeWidth, 1 / zoom),
                                      seed: Render.paperSeed) {
                ctx.addPath(mark)
                ctx.setFillColor(colour.cg)
                ctx.fillPath(using: .evenOdd)
                return
            }
            ctx.addPath(live)
            ctx.strokePath()

        case .shape(let a, let b):
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            let shape = model.tool == .ellipse ? Shape2D.ellipse(r) : Shape2D.rect(r)
            if model.fillEnabled {
                ctx.addPath(shape.cgPath)
                ctx.setFillColor(model.fillColor.cg(alpha: 0.7))
                ctx.fillPath()
            }
            ctx.addPath(shape.cgPath)
            ctx.setStrokeColor((model.strokeEnabled ? model.strokeColor : accent).cg)
            ctx.setLineWidth(max(model.strokeWidth, 1 / zoom))
            ctx.strokePath()

        default: break
        }
    }

    /// The shape under the pointer in the layers panel.
    ///
    /// Drawn at exactly the geometry `drawSelection` uses for a single shape —
    /// same bounds, same outset, one line width — so clicking the row you are
    /// hovering promotes the box in place instead of nudging it. Only the alpha
    /// differs, which is what makes it read as *would be* rather than *is*.
    ///
    /// Skipped for a layer already selected: its outline is on screen, and a
    /// second line drawn over the first at half strength only muddies it.
    // MARK: The armature

    /// The pose left behind, as an outline.
    ///
    /// Not gated on `showRig`: hiding the bones is how you look at the pose as a
    /// drawing, and the outline you are comparing it against is the whole reason
    /// you would. Drawn over the artwork rather than under it, because Flip's
    /// fills are opaque and underneath it would only show where the two poses
    /// already differ — which is the half you can see anyway.
    private func drawRigGhost(_ ctx: CGContext) {
        guard !model.rigGhost.isEmpty else { return }
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
        ctx.setLineWidth(1 / zoom)
        ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
        for shape in model.rigGhost {
            ctx.addPath(shape.cgPath)
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
    }

    /// Bones over the artwork, in document space so they track the artboard.
    /// Lengths are divided by the zoom wherever they should feel constant on
    /// screen, the way every other overlay in here works.
    private func drawRig(_ ctx: CGContext) {
        guard model.tool == .bone else { return }

        // The bone being dragged right now, which is drawn whether or not there
        // is already an armature to hang it on.
        //
        // This used to sit behind the guard below, and the very first bone of a
        // rig is placed when `hasRig` is still false — so the first drag in a
        // frame showed nothing at all until the mouse came up, and every drag
        // after it was live. A tool that answers the second use and not the
        // first reads as broken rather than as empty.
        var placing: (start: CGPoint, current: CGPoint)?
        if case .newBone(let start, _, _, let current) = drag { placing = (start, current) }

        let onScreen = model.rigsOnScreen
        let armatures = model.showRig && model.hasRig && !onScreen.isEmpty
        guard armatures || placing != nil else { return }

        let accent = FlipTheme.accent.rgba.cg
        let hot = CGColor(srgbRed: 0.98, green: 0.78, blue: 0.28, alpha: 1)

        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: zoom, y: zoom)

        if armatures {
            // Which layers the active armature drives, shown structurally rather
            // than written down — so what a pose will move is visible before it
            // moves.
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5 / zoom)
            for shape in rigOwnedShapes() {
                ctx.addPath(shape.cgPath)
                ctx.strokePath()
            }

            // What a click would do to the layer under the pointer. Solid amber to
            // take it into the rig, dashed in the rig's own colour to let it go —
            // releasing is otherwise silent, and doing it by accident leaves a layer
            // that simply stops following its bones.
            if let id = boneHover,
               let layer = LayerTree.find(id, in: model.frame.layers) {
                let releasing = model.isOwnedByRigOnScreen(layer)
                ctx.setStrokeColor(releasing ? accent : hot)
                ctx.setLineWidth(2 / zoom)
                if releasing { ctx.setLineDash(phase: 0, lengths: [5 / zoom, 4 / zoom]) }
                // Every shape it draws — a group is highlighted whole, because a
                // click takes it whole.
                for shape in model.posedShapes(of: layer) {
                    ctx.addPath(shape.cgPath)
                    ctx.strokePath()
                }
                ctx.setLineDash(phase: 0, lengths: [])
            }

            for (ri, rig) in model.frame.armatures.enumerated() where onScreen.contains(ri) {
                // Dim the armatures a click would not affect.
                let dim = onScreen.count > 1 && model.activeRig != nil && model.activeRig != ri
                let body = accent.copy(alpha: dim ? 0.20 : 0.55) ?? accent
                let edge = accent.copy(alpha: dim ? 0.35 : 1) ?? accent

                // The rest pose behind the current one, so a pose reads as a
                // departure from somewhere rather than as an arbitrary arrangement.
                if rig.isPosed {
                    ctx.setStrokeColor(accent.copy(alpha: 0.40) ?? accent)
                    ctx.setLineWidth(1 / zoom)
                    ctx.setLineDash(phase: 0, lengths: [3 / zoom, 3 / zoom])
                    for b in rig.bones {
                        ctx.addPath(boneSpindle(from: b.restOrigin, to: b.restTip))
                        ctx.strokePath()
                    }
                    ctx.setLineDash(phase: 0, lengths: [])
                }

                ctx.setFillColor(body)
                for b in rig.bones { ctx.addPath(boneSpindle(from: b.origin, to: b.tip)); ctx.fillPath() }
                ctx.setStrokeColor(edge)
                ctx.setLineWidth(1 / zoom)
                for b in rig.bones { ctx.addPath(boneSpindle(from: b.origin, to: b.tip)); ctx.strokePath() }

                // Tips turn a bone; a root's origin moves its whole chain. Drawn
                // differently because they do different things.
                for i in rig.bones.indices {
                    let live = isPosing(rig: ri, bone: i, root: false)
                    boneDot(ctx, rig.bones[i].tip, r: (live ? 8 : 5.5) / zoom, color: live ? hot : edge)
                }
                for i in rig.bones.indices where rig.bones[i].isRoot {
                    let live = isPosing(rig: ri, bone: i, root: true)
                    boneSquare(ctx, rig.bones[i].origin, half: (live ? 7.5 : 5.5) / zoom,
                               color: live ? hot : edge)
                }
            }
        }

        if let placing {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5 / zoom)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
            ctx.move(to: placing.start)
            ctx.addLine(to: placing.current)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            boneDot(ctx, placing.start, r: 3.5 / zoom, color: accent)
            // The tip too, so the bone being drawn has the same pair of handles
            // the finished ones do and the drag reads as a bone rather than a
            // line. Amber because it is live, exactly as a tip being posed is.
            boneDot(ctx, placing.current, r: 5.5 / zoom, color: hot)
        }

        ctx.restoreGState()
    }

    /// Starts dragging the selection, leaving a copy of it behind first if ⌥ is
    /// held — which is what makes ⌥-drag a duplicate.
    ///
    /// One `commit` either way, so the copy and the move it was made for undo
    /// together: an ⌥-drag is one action to the hand that did it, and taking two
    /// presses of ⌘Z to get back would be counting the implementation out loud.
    /// `duplicateSelectionInPlace` takes that checkpoint itself, before it
    /// changes anything — hence the either/or rather than both.
    private func beginMove(from p: CGPoint, leavingACopy copy: Bool) {
        if !copy || !model.duplicateSelectionInPlace() { model.commit() }
        drag = .move(last: p)
    }

    /// The posed outlines of everything an armature on screen drives.
    ///
    /// Stops at the layer that carries the rig rather than walking past it: a
    /// bound group is outlined by the shapes inside it, and those shapes do not
    /// carry the rig themselves — they inherit it.
    private func rigOwnedShapes() -> [Shape2D] {
        var out: [Shape2D] = []
        func walk(_ layers: [Layer]) {
            for l in layers where l.visible {
                if model.isOwnedByRigOnScreen(l) { out += model.posedShapes(of: l) }
                else if !l.children.isEmpty { walk(l.children) }
            }
        }
        walk(model.frame.layers)
        return out
    }

    private func isPosing(rig: Int, bone: Int, root: Bool) -> Bool {
        if case .poseBone(let r, let b, let ro) = drag { return r == rig && b == bone && ro == root }
        return false
    }

    /// A tapered spindle rather than a plain line: it costs eight lines and makes
    /// the direction of every bone readable at a glance, which matters when a
    /// chain doubles back on itself.
    private func boneSpindle(from a: CGPoint, to b: CGPoint) -> CGPath {
        let length = max(a.dist(b), 0.001)
        let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
        let px = -dy, py = dx
        let w = min(max(length * 0.11, 2.5 / zoom), 7 / zoom)
        let shoulder = CGPoint(x: a.x + dx * length * 0.24, y: a.y + dy * length * 0.24)

        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: CGPoint(x: shoulder.x + px * w, y: shoulder.y + py * w))
        path.addLine(to: b)
        path.addLine(to: CGPoint(x: shoulder.x - px * w, y: shoulder.y - py * w))
        path.closeSubpath()
        return path
    }

    private func boneDot(_ ctx: CGContext, _ p: CGPoint, r: CGFloat, color: CGColor) {
        let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: box)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
        ctx.setLineWidth(1 / zoom)
        ctx.strokeEllipse(in: box)
    }

    private func boneSquare(_ ctx: CGContext, _ p: CGPoint, half: CGFloat, color: CGColor) {
        let box = CGRect(x: p.x - half, y: p.y - half, width: half * 2, height: half * 2)
        ctx.setFillColor(model.doc.background.cg)
        ctx.fill(box)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(2 / zoom)
        ctx.stroke(box)
    }

    private func drawHover(_ ctx: CGContext) {
        guard let id = model.hoveredLayer, !model.selection.contains(id),
              let layer = model.layerHere(id) else { return }
        let b = Render.bounds(posed(layer))
        guard !b.isNull else { return }
        ctx.setStrokeColor(FlipTheme.accent.rgba.cg(alpha: 0.55))
        ctx.setLineWidth(1)
        ctx.stroke(viewRect(b).insetBy(dx: -TransformBox.outset, dy: -TransformBox.outset))
    }

    /// The selection's outline, and in the cursor tool the box it is transformed
    /// by.
    ///
    /// Drawn in view space, so the grips are the same size to see and to grab at
    /// any zoom — the same reasoning as the point tool's anchors and handles.
    private func drawSelection(_ ctx: CGContext) {
        guard !model.selection.isEmpty else { return }
        let here = model.selectedLayersHere
        guard !here.isEmpty else { return }
        let accent = FlipTheme.accent.rgba.cg
        let box = viewBox()

        ctx.setStrokeColor(accent)
        ctx.setLineWidth(1)

        // Each shape's own outline, when the box around them all is not already
        // it. Skipped for a turned box: those outlines are upright, and an
        // upright rectangle inside a diagonal one reads as a mistake rather than
        // as two facts. The box is the informative one there anyway.
        if box == nil || (here.count > 1 && box?.isUpright == true) {
            for layer in here {
                let b = Render.bounds(posed(layer))
                guard !b.isNull else { continue }
                ctx.stroke(viewRect(b).insetBy(dx: -TransformBox.outset, dy: -TransformBox.outset))
            }
        }

        guard let box else { return }
        let corners = TransformGrip.corners.map { box.world($0) }
        ctx.move(to: corners[0])
        for p in corners.dropFirst() { ctx.addLine(to: p) }
        ctx.addLine(to: corners[0])
        ctx.strokePath()

        // Four corner squares and nothing else. The bars are the box's own
        // edges, which are already on screen — a control drawn along each one
        // would be four more things to look at saying what the line beneath them
        // already says. And nothing marks the turn zones just outside the
        // corners: a grip drawn 6pt off the corner would crowd the corner it is
        // meant to be distinct from, so the pointer announces those instead.
        //
        // White with an accent edge, matching the point tool's anchors, because a
        // solid accent grip disappears into a drawing in the same green.
        let half = TransformBox.grip / 2
        let square = CGRect(x: -half, y: -half, width: half * 2, height: half * 2)
        for grip in TransformGrip.corners {
            let c = box.world(grip)
            // Drawn about the corner and turned with the box, so the squares stay
            // square to the box rather than to the artboard.
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: box.angle)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(square)
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5)
            ctx.stroke(square)
            ctx.restoreGState()
        }
    }

    private func viewRect(_ b: CGRect) -> CGRect {
        CGRect(origin: toView(b.origin),
               size: CGSize(width: b.width * zoom, height: b.height * zoom))
    }

    /// The selection's box in **view** space, where the grips are measured, or
    /// `nil` when there is nothing to transform in the frame on screen.
    ///
    /// The document-to-view transform is a uniform scale and a translation, so it
    /// carries the box's angle over untouched — which is why the grips can be
    /// sized in view points while the box itself is a document-space idea.
    private func viewBox() -> OrientedBox? {
        guard model.tool == .select, !model.selection.isEmpty, !model.isPlaying,
              let box = model.selectionBox else { return nil }
        return box.mapped(rect: viewRect, point: toView).outset(by: TransformBox.outset)
    }

    /// The line through the points, for every shape the pen is working on.
    ///
    /// Without it the anchors are a constellation. The artwork's own stroke can
    /// be any width, or none at all, and a filled shape with no stroke gives no
    /// clue which point joins which — least of all on a curve, where the order
    /// along the path is not the order across the screen.
    private func drawSpines(_ ctx: CGContext) {
        var t = CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: zoom, y: zoom)
        ctx.setStrokeColor(FlipTheme.accent.rgba.cg(alpha: 0.55))
        ctx.setLineWidth(1)
        for layer in model.penShapes {
            guard let shape = layer.shape, !shape.isEmpty,
                  let path = shape.cgPath.copy(using: &t) else { continue }
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// Anchors and handles, drawn in view space so they stay the same size at any
    /// zoom. Open endpoints get a hollow ring — those are the ones you can join.
    private func drawNodes(_ ctx: CGContext) {
        let accent = FlipTheme.accent.rgba.cg
        let white = CGColor(gray: 1, alpha: 1)

        for layer in model.penShapes {
            guard let shape = layer.shape else { continue }

            // Handles for the *points* that are picked, not for every point on a
            // picked layer. A path of forty anchors drew eighty handle dots and
            // eighty lines over the artwork — the points themselves were the one
            // thing you could not find in it. Accent rather than white: the
            // artboard is near-white paper, and a white handle over it was
            // invisible exactly where it was needed.
            let picked = model.selectedNodes.filter { $0.layer == layer.id }
            if !picked.isEmpty {
                func anchor(_ ref: NodeRef) -> Anchor? {
                    guard shape.subpaths.indices.contains(ref.subpath),
                          shape.subpaths[ref.subpath].anchors.indices.contains(ref.anchor)
                    else { return nil }
                    return shape.subpaths[ref.subpath].anchors[ref.anchor]
                }

                ctx.setStrokeColor(FlipTheme.accent.rgba.cg(alpha: 0.65))
                ctx.setLineWidth(1)
                for ref in picked {
                    guard let a = anchor(ref) else { continue }
                    for h in [a.inH, a.outH] where h.length > 0.5 {
                        ctx.move(to: toView(a.p)); ctx.addLine(to: toView(a.p + h))
                    }
                }
                ctx.strokePath()

                for ref in picked {
                    guard let a = anchor(ref) else { continue }
                    for h in [a.inH, a.outH] where h.length > 0.5 {
                        let c = toView(a.p + h)
                        let dot = CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)
                        ctx.setFillColor(accent)
                        ctx.fillEllipse(in: dot)
                        // A white ring keeps it legible over a dark drawing as
                        // well as over the paper.
                        ctx.setStrokeColor(white)
                        ctx.setLineWidth(1)
                        ctx.strokeEllipse(in: dot)
                    }
                }
            }

            for (si, sp) in shape.subpaths.enumerated() {
                for (ai, a) in sp.anchors.enumerated() {
                    let c = toView(a.p)
                    let ref = NodeRef(layer: layer.id, subpath: si, anchor: ai)
                    let picked = model.selectedNodes.contains(ref)
                    let isEnd = !sp.closed && (ai == 0 || ai == sp.anchors.count - 1)
                    let r: CGFloat = isEnd ? 4.5 : 3.5
                    let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)

                    ctx.setLineWidth(1.5)
                    if isEnd {
                        ctx.setFillColor(picked ? accent : CGColor(gray: 0.1, alpha: 1))
                        ctx.fillEllipse(in: box)
                        ctx.setStrokeColor(accent)
                        ctx.strokeEllipse(in: box)
                    } else {
                        ctx.setFillColor(picked ? accent : white)
                        ctx.fill(box)
                        ctx.setStrokeColor(accent)
                        ctx.stroke(box)
                    }
                }
            }
        }

        if let (_, p) = snapTarget {
            let c = toView(p)
            ctx.setStrokeColor(CGColor(srgbRed: 0.30, green: 0.85, blue: 0.45, alpha: 1))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
        }
    }

    private func drawMarquee(_ ctx: CGContext) {
        guard case .marquee(let a, let b) = drag else { return }
        let p = toView(a), q = toView(b)
        let r = CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(q.x - p.x), height: abs(q.y - p.y))
        ctx.setFillColor(FlipTheme.accent.rgba.cg(alpha: 0.12))
        ctx.fill(r)
        ctx.setStrokeColor(FlipTheme.accent.rgba.cg)
        ctx.setLineWidth(1)
        ctx.stroke(r)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        defer {
            model.suspendsPublishing = drag.mutatesDocument
            needsDisplay = true
        }
        window?.makeFirstResponder(self)

        // A press on the canvas shuts whatever is raised over it — a strip
        // popup, the colour card, the shortcuts legend — and then, for all but
        // the legend, carries on into the tool. Picking a colour and putting the
        // brush down is one intention; making it two clicks, with the first
        // stroke going nowhere, reads as the app having stopped responding.
        //
        // This has to live here rather than as a transparent SwiftUI layer over
        // the canvas: the canvas is an `NSView`, and AppKit hit-tests it before
        // any SwiftUI gesture drawn on top of it ever sees the event.
        if model.dismissTransients() { return }

        model.stop()
        let p = point(event)
        let shift = event.modifierFlags.contains(.shift)

        // Moving the reference takes precedence over every tool, but only while it
        // is unlocked — the lock is what stops a stray drag shifting the thing you
        // are tracing.
        let command = event.modifierFlags.contains(.command)
        let option = event.modifierFlags.contains(.option)

        // In reposition mode the reference is the only thing on the canvas that
        // moves, so every press that is not a pan drags it — no aiming, and no
        // modifier to hold down through a long adjustment.
        if model.repositioning {
            if pans(event.modifierFlags) {
                drag = .pan(convert(event.locationInWindow, from: nil))
                FlipCursor.grabbing.set()
            } else {
                drag = .reference(last: p)
            }
            return
        }

        // ⌃ with any tool, or the hand tool with none — and ⌥ with the tools
        // that have no use for it. A pan is the one thing you want without
        // putting the tool in your hand down, so it has more than one way in on
        // purpose.
        if pans(event.modifierFlags) {
            drag = .pan(convert(event.locationInWindow, from: nil))
            FlipCursor.grabbing.set()
            return
        }

        switch model.tool {
        // Never reached: the hand starts its pan above, before the tool is even
        // consulted. Listed so that adding a tool later cannot quietly fall
        // through this switch.
        case .hand:
            break

        case .bone:
            switch model.boneMode {
            case .place:
                // Starting on an existing tip chains a child within that tip's
                // own armature; anywhere else begins a new one, which claims
                // whatever it is drawn inside.
                if let h = model.boneTip(near: p, within: boneGrab) {
                    model.activeRig = h.rig
                    drag = .newBone(start: model.frame.armatures[h.rig].bones[h.bone].tip,
                                    rig: h.rig, parent: h.bone, current: p)
                } else {
                    drag = .newBone(start: p, rig: nil, parent: nil, current: p)
                }
            case .pose:
                // A root's origin moves the whole chain, so it is offered first;
                // on a root bone the two handles sit at opposite ends anyway.
                if let h = model.boneRoot(near: p, within: boneGrab) {
                    model.commit()
                    model.activeRig = h.rig
                    drag = .poseBone(rig: h.rig, bone: h.bone, root: true)
                } else if let h = model.boneTip(near: p, within: boneGrab) {
                    model.commit()
                    model.activeRig = h.rig
                    drag = .poseBone(rig: h.rig, bone: h.bone, root: false)
                }
            }

        case .brush:
            // Rolled now rather than at the commit: the wander is a function of
            // the layer's identity, and a preview drawn under a different one
            // would jump to a new shape the moment the hand came up.
            strokeIdentity = UUID()
            drag = .stroke([p])

        case .rect, .ellipse:
            drag = .shape(p, p)

        case .select:
            // Before the shape under the pointer: a grip sits on the selection's
            // own edge, so the shape is always under it and would otherwise win
            // every grab and start a move instead of a resize. The turn zones are
            // outside the shape entirely, and take precedence over the marquee
            // they would otherwise start.
            if let box = viewBox(),
               let target = box.target(at: convert(event.locationInWindow, from: nil)) {
                beginTransform(target, from: p)
                return
            }
            // ⌘ goes deep, ⇧ adds — so ⌘⇧ picks leaves out of a group one at a
            // time, which is the same pair of meanings the two modifiers carry
            // on their own and composes the way you would guess.
            if command, let deep = deepLayer(at: p) {
                if shift {
                    if model.selection.contains(deep.id) { model.selection.remove(deep.id) }
                    else { model.selection.insert(deep.id) }
                } else {
                    model.selection = [deep.id]
                }
                model.selectedNodes = []
                // No move behind a click that has just *deselected* something:
                // the drag would take the rest of the selection with it, from a
                // press the hand meant as "not that one".
                guard model.selection.contains(deep.id) else { drag = .none; return }
                beginMove(from: p, leavingACopy: option)
                return
            }

            // Before `topLayer`, or a grouped shape can never be dragged.
            if !shift, selectionHit(at: p) {
                beginMove(from: p, leavingACopy: option)
                return
            }

            if let hit = topLayer(at: p) {
                if shift {
                    if model.selection.contains(hit.id) { model.selection.remove(hit.id) }
                    else { model.selection.insert(hit.id) }
                } else if !model.selection.contains(hit.id) {
                    model.selection = [hit.id]
                }
                model.selectedNodes = []
                beginMove(from: p, leavingACopy: option)
            } else {
                if !shift { model.selection = []; model.selectedNodes = [] }
                drag = .marquee(p, p)
            }

        case .bezier:
            switch penIntent(at: p, event.modifierFlags) {
            case .close(let ref):
                model.closeDrawnPath(ref)
                pen = nil
                return

            case .extend(let ref):
                guard model.turnForDrawing(ref) else { return }
                model.selection = [ref.layer]
                model.selectedNodes = []
                if let l = LayerTree.find(ref.layer, in: model.frame.layers), let sh = l.shape,
                   sh.subpaths.indices.contains(ref.subpath) {
                    pen = Pen(layer: ref.layer, subpath: ref.subpath, frame: model.frameIndex)
                }
                return

            case .join(let ref):
                guard let session = pen, let sp = penSubpath(), let last = sp.anchors.indices.last
                else { return }
                model.join(NodeRef(layer: session.layer, subpath: session.subpath, anchor: last), ref)
                pen = nil
                return

            case .insert(let layer, let subpath, let segment, let t):
                if let ref = model.insertAnchor(layer: layer, subpath: subpath,
                                                segment: segment, at: t) {
                    model.selection = [layer]
                    model.selectedNodes = [ref]
                    drag = .node(ref, p)
                }
                return

            case .grabHandle(let ref, let out):
                model.commit()
                drag = .handle(ref, out: out)
                model.selection = [ref.layer]
                return

            case .grabPoint(let ref):
                model.commit()
                model.selection = [ref.layer]
                if shift { model.selectedNodes.insert(ref) } else { model.selectedNodes = [ref] }
                drag = .node(ref, p)
                endPen()
                return

            case .convert(let ref):
                model.toggleSmooth(ref)
                model.selection = [ref.layer]
                model.selectedNodes = [ref]
                return

            case .clear:
                model.selectedNodes = []
                return

            case .place:
                break
            }

            // Nothing under the pointer, so this is a new point — either the
            // first of a path or the next one along.
            placePenPoint(at: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .stroke(var pts):
            pts.append(p)
            drag = .stroke(pts)

        case .shape(let a, _):
            var b = p
            if event.modifierFlags.contains(.shift) {
                let side = max(abs(b.x - a.x), abs(b.y - a.y))
                b = CGPoint(x: a.x + side * (b.x < a.x ? -1 : 1), y: a.y + side * (b.y < a.y ? -1 : 1))
            }
            drag = .shape(a, b)

        case .move(let last):
            // Every frame the selection reaches, not just this one — ⌥-clicking a
            // layer in the panel selects it in all of them, and a move that only
            // took effect here would undo that link on the first drag.
            model.translateSelection(by: p - last)
            drag = .move(last: p)

        case .newBone(let start, let rig, let parent, _):
            drag = .newBone(start: start, rig: rig, parent: parent, current: p)

        case .poseBone(let rig, let bone, let root):
            if root {
                model.poseRoot(rig: rig, bone: bone, to: p)
            } else {
                model.poseTip(rig: rig, bone: bone, to: p,
                              stretch: event.modifierFlags.contains(.option))
            }

        case .penHandle(let ref):
            // Symmetric by default, which is what makes a dragged point smooth.
            // ⌥ moves only the outgoing handle, leaving a corner behind you and a
            // curve ahead — the standard way to turn a corner mid-path.
            let breakPair = event.modifierFlags.contains(.option)
            model.editShape(ref.layer) { shape in
                guard shape.subpaths.indices.contains(ref.subpath),
                      shape.subpaths[ref.subpath].anchors.indices.contains(ref.anchor) else { return }
                var a = shape.subpaths[ref.subpath].anchors[ref.anchor]
                a.outH = p - a.p
                if !breakPair { a.inH = -a.outH }
                shape.subpaths[ref.subpath].anchors[ref.anchor] = a
            }

        case .node(let ref, _):
            model.editShape(ref.layer) { s in
                guard s.subpaths.indices.contains(ref.subpath),
                      s.subpaths[ref.subpath].anchors.indices.contains(ref.anchor) else { return }
                s.subpaths[ref.subpath].anchors[ref.anchor].p = p
            }
            findSnap(from: ref, at: p)

        case .handle(let ref, let out):
            let mirror = !event.modifierFlags.contains(.option)
            model.editShape(ref.layer) { s in
                guard s.subpaths.indices.contains(ref.subpath),
                      s.subpaths[ref.subpath].anchors.indices.contains(ref.anchor) else { return }
                var a = s.subpaths[ref.subpath].anchors[ref.anchor]
                let offset = p - a.p
                if out { a.outH = offset; if mirror { a.inH = -offset } }
                else    { a.inH = offset;  if mirror { a.outH = -offset } }
                s.subpaths[ref.subpath].anchors[ref.anchor] = a
            }

        case .scale(let s):
            let locked = event.modifierFlags.contains(.shift)
            model.transformSelection(s.originals, by: s.transform.transform(at: p, locked: locked))

        case .rotate(let r):
            let locked = event.modifierFlags.contains(.shift)
            let turn = r.transform.angle(at: p, locked: locked)
            model.transformSelection(r.originals,
                                     by: .about(r.transform.pivot, .rotation(turn)),
                                     turningBy: turn)

        case .marquee(let a, _):
            drag = .marquee(a, p)

        case .reference(let last):
            model.moveReference(by: p - last)
            drag = .reference(last: p)

        case .pan(let last):
            let now = convert(event.locationInWindow, from: nil)
            model.pan = CGPoint(x: model.pan.x + (now.x - last.x), y: model.pan.y + (now.y - last.y))
            drag = .pan(now)

        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if drag.mutatesDocument { model.invalidateThumbnail() }
        model.resumePublishing()
        // The grabbing hand is set by hand, so it has to be put down by hand:
        // nothing else runs between a press and a release to restore it.
        if case .pan = drag { toolCursor?.set() }
        switch drag {
        case .stroke(let pts):
            if let sp = Fit.stroke(pts, closeWithin: model.snapDistance, zoom: zoom) {
                let shape = Shape2D(subpaths: [sp])
                var layer = model.newLayer(shape, name: sp.closed ? "Shape" : "Line")
                layer.id = strokeIdentity
                model.add(layer)
            }

        case .shape(let a, let b):
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            if r.width > 2, r.height > 2 {
                let isEllipse = model.tool == .ellipse
                model.add(model.newLayer(isEllipse ? .ellipse(r) : .rect(r),
                                         name: isEllipse ? "Circle" : "Rectangle"))
            }

        // `mouseUp` keeps no point of its own, and the drag already carries the
        // last one — which on a press that never moved is the press itself, so
        // the click case reads from the same field.
        case .newBone(let start, let rig, let parent, let end):
            if start.dist(end) >= 10 / zoom {
                model.addBone(from: start, to: end, rig: rig, parent: parent)
            } else if let id = model.layersEnclosing(end).first {
                // A click rather than a drag: the explicit override, for
                // everything enclosure gets wrong.
                model.toggleRigMembership(layerAt: id)
            }

        case .poseBone:
            break

        case .node(let ref, _):
            if let (target, _) = snapTarget { model.join(ref, target) }

        case .marquee(let a, let b):
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            if r.width > 1 || r.height > 1 {
                let inside = model.frame.layers
                    .filter { $0.visible && r.intersects(Render.bounds(posed($0))) }
                    .map { $0.id }
                model.selection.formUnion(inside)
            }

        default:
            break
        }
        drag = .none
        snapTarget = nil
        // Recomputed on release, not just on the next move: binding a layer flips
        // what the highlight means, and the first bone of a new armature is what
        // makes there be anything to bind to at all.
        refreshBoneHover(at: point(event))
        needsDisplay = true
    }

    /// Just a modifier, no tool. What the *tool* does is already carried by
    /// `toolCursor`, and folding the two together would leave `panHeld`
    /// permanently true whenever the hand tool was in use.
    ///
    /// ⌃ always pans. ⌥ pans only where the tool has no use of its own for it —
    /// the pen converts an anchor with it, and the pointer leaves a copy behind.
    /// It is decided by the tool alone and never by what the press lands on: the
    /// pointer is a promise about the next click, and a modifier that means one
    /// thing over a shape and another over bare paper is a promise that cannot
    /// be drawn.
    private func panModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        if flags.contains(.control) { return true }
        guard flags.contains(.option) else { return false }
        switch model.tool {
        case .bezier, .select: return false
        default:               return true
        }
    }

    /// Whether a press with these modifiers would pan rather than use the tool.
    ///
    /// Shared by `mouseDown` and `updatePointer` deliberately. The cursor is a
    /// promise about what the next click does, and the only way it cannot go
    /// stale is for the promise and the click to read the same function.
    private func pans(_ flags: NSEvent.ModifierFlags) -> Bool {
        panModifier(flags) || model.tool == .hand
    }

    /// Pressing or releasing a modifier changes what the next click will do, so
    /// it has to change the pointer too — and at the moment the key moves, not
    /// the next time the mouse does.
    override func flagsChanged(with event: NSEvent) {
        panHeld = panModifier(event.modifierFlags)
        // The pen's pointer depends on ⌘ and ⌥ as much as on what is under it,
        // and so does the cursor's now that ⌥ duplicates — so for both, a
        // modifier alone has to be enough to change it, without waiting for the
        // hand to move.
        if model?.tool == .bezier || model?.tool == .select { refreshPointer() }
        super.flagsChanged(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // Also here, not only in `mouseEntered`: the tracking area is rebuilt on
        // every resize, and a rebuild under a stationary pointer sends no enter.
        isMouseInside = true
        updatePointer(with: event)
        hoverPoint = point(event)
        if refreshBoneHover(at: point(event)) { needsDisplay = true }
        // The rubber band follows the pointer, so the canvas has to redraw on a
        // bare move — which it otherwise never needs to do.
        if pen != nil { needsDisplay = true }
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        guard boneHover != nil else { return }
        boneHover = nil
        needsDisplay = true
    }

    /// The same query the click uses, so the highlight can never promise
    /// something the click will not do. Returns whether it changed.
    @discardableResult
    private func refreshBoneHover(at p: CGPoint) -> Bool {
        let next: UUID?
        if model.tool == .bone, model.boneMode == .place, model.hasRig {
            next = model.layersEnclosing(p).first
        } else {
            next = nil
        }
        guard next != boneHover else { return false }
        boneHover = next
        return true
    }

    // MARK: Transform

    /// Take hold of the box: a grip stretches the selection, the space just
    /// outside a corner turns it.
    ///
    /// The drag works in **document** space from here on, so it takes the
    /// document's box rather than the view's — the grips were only measured in
    /// view points to keep them a constant size to grab.
    private func beginTransform(_ target: TransformTarget, from p: CGPoint) {
        guard let box = model.selectionBox else { return }
        model.commit()
        model.selectedNodes = []
        let originals = model.selectionSnapshot()
        switch target {
        case .scale(let grip):
            drag = .scale(Scaling(transform: TransformDrag(grip: grip, box: box, pointer: p),
                                  originals: originals))
        case .rotate:
            drag = .rotate(Rotating(transform: RotateDrag(box: box, pointer: p),
                                    originals: originals))
        }
    }

    // MARK: The pen

    /// Place the next point, starting a path if there is not one under way.
    ///
    /// Every point is committed as it lands, so ⌘Z steps back through them one at
    /// a time and abandoning the run leaves a real layer rather than losing work.
    private func placePenPoint(at p: CGPoint) {
        if let session = pen {
            model.commit()
            var placed = 0
            model.editShape(session.layer) { shape in
                guard shape.subpaths.indices.contains(session.subpath) else { return }
                shape.subpaths[session.subpath].anchors.append(Anchor(p))
                placed = shape.subpaths[session.subpath].anchors.count - 1
            }
            drag = .penHandle(NodeRef(layer: session.layer, subpath: session.subpath, anchor: placed))
        } else {
            let shape = Shape2D(subpaths: [Subpath(anchors: [Anchor(p)])])
            let layer = model.newLayer(shape, name: "Path")
            model.add(layer)
            pen = Pen(layer: layer.id, subpath: 0, frame: model.frameIndex)
            drag = .penHandle(NodeRef(layer: layer.id, subpath: 0, anchor: 0))
        }
    }

    /// Whether clicking this anchor would close the path being drawn. Needs three
    /// points, because two anchors joined end to end enclose nothing.
    /// What a press with the pen would do, here, with these modifiers held.
    ///
    /// One function, read by the press *and* by the pointer. The pen now has
    /// five different things a click can mean and three cursors promising which
    /// — two copies of that reasoning would drift apart within a week, and the
    /// symptom would be a cursor that lies.
    enum PenIntent {
        /// Shut the path being drawn.
        case close(NodeRef)
        /// Draw onward from an existing loose end.
        case extend(NodeRef)
        /// Tie the path being drawn to another path's loose end.
        case join(NodeRef)
        /// Add a point part way along a segment.
        case insert(layer: UUID, subpath: Int, segment: Int, t: CGFloat)
        /// ⌘: take hold of a point, or of one of its handles.
        case grabPoint(NodeRef)
        case grabHandle(NodeRef, out: Bool)
        /// ⌥ on a point: corner ↔ smooth.
        case convert(NodeRef)
        /// ⌘ on nothing: let go of the points that were picked.
        case clear
        /// Put a new point down.
        case place
    }

    /// ⌘ is the pen's edit key: with it held the pen selects and moves what is
    /// already there, without it the pen draws. That split is what makes
    /// clicking a loose end unambiguous — without it, a click on an endpoint
    /// cannot tell "carry on from here" apart from "pick this up".
    func penIntent(at p: CGPoint, _ flags: NSEvent.ModifierFlags) -> PenIntent {
        if flags.contains(.command) {
            if let (ref, out) = handle(at: p) { return .grabHandle(ref, out: out) }
            if let ref = anchor(at: p) { return .grabPoint(ref) }
            return .clear
        }
        // Before the rest: ⌥ on a point is a conversion whatever else that
        // point happens to be — including the first point of the path being
        // drawn, where the alternative reading is "close", and closing is what
        // a plain click there already does.
        if flags.contains(.option), let ref = anchor(at: p) { return .convert(ref) }
        if let ref = penClose(at: p) { return .close(ref) }
        if let ref = looseEnd(at: p) { return pen == nil ? .extend(ref) : .join(ref) }
        if let spot = segmentPlace(at: p) { return .insert(layer: spot.0, subpath: spot.1,
                                                          segment: spot.2, t: spot.3) }
        return .place
    }

    /// An open subpath's first or last point, other than the one the pen is
    /// already drawing from — clicking the end you are standing on is not a
    /// thing you can mean.
    private func looseEnd(at p: CGPoint) -> NodeRef? {
        var best: (NodeRef, CGFloat)?
        for layer in model.penShapes {
            guard let shape = layer.shape else { continue }
            for (si, sp) in shape.subpaths.enumerated() where !sp.closed && sp.anchors.count >= 1 {
                for ai in [0, sp.anchors.count - 1] {
                    if let s = pen, s.layer == layer.id, s.subpath == si { continue }
                    let d = sp.anchors[ai].p.dist(p)
                    guard d < grab else { continue }
                    let ref = NodeRef(layer: layer.id, subpath: si, anchor: ai)
                    if best == nil || d < best!.1 { best = (ref, d) }
                }
            }
        }
        return best?.0
    }

    /// Where on a path the pointer is, when it is on one and not on a point.
    private func segmentPlace(at p: CGPoint) -> (UUID, Int, Int, CGFloat)? {
        guard anchor(at: p) == nil else { return nil }
        for layer in model.penShapes {
            guard let shape = layer.shape else { continue }
            for (si, sp) in shape.subpaths.enumerated() {
                if let hit = sp.nearestPlace(to: p, within: grab) {
                    return (layer.id, si, hit.segment, hit.t)
                }
            }
        }
        return nil
    }

    /// The first point of the path being drawn, when a press here would close it.
    ///
    /// Measured against that point directly rather than through `anchor(at:)`,
    /// and at twice the radius. Two reasons, both of which were stopping this
    /// from working at all: an ordinary anchor's 6pt target is a small thing to
    /// hit for the one click in the pen that has no second chance — miss and you
    /// get a stray point — and the first anchor's own *handle* sits within that
    /// same 6pt when the handle is short, so `handle(at:)`, which is tested
    /// first, was swallowing the click before the close was ever considered.
    private func penClose(at p: CGPoint) -> NodeRef? {
        guard let session = pen,
              let sp = penSubpath(), sp.anchors.count >= 3, !sp.closed,
              let first = sp.anchors.first,
              first.p.dist(p) < 12 / zoom else { return nil }
        return NodeRef(layer: session.layer, subpath: session.subpath, anchor: 0)
    }

    private func penSubpath() -> Subpath? {
        guard let session = pen,
              let layer = LayerTree.find(session.layer, in: model.frame.layers),
              let shape = layer.shape,
              shape.subpaths.indices.contains(session.subpath) else { return nil }
        return shape.subpaths[session.subpath]
    }

    /// Finish an open path. A single click that never became a second point is
    /// not a path at all, so the layer it made goes with it.
    private func endPen() {
        guard let session = pen else { return }
        pen = nil
        if let sp = penSubpath(), sp.anchors.count < 2 {
            model.deleteLayer(session.layer)
        }
        needsDisplay = true
    }

    /// The segment that has not been committed yet: from the last point placed to
    /// wherever the pointer is, curving out of that point's handle so what you see
    /// is the segment you are about to get.
    private func drawPenPreview(_ ctx: CGContext) {
        guard pen != nil, let hover = hoverPoint,
              let sp = penSubpath(), let last = sp.anchors.last else { return }

        ctx.setStrokeColor(FlipTheme.accent.rgba.cg(alpha: 0.9))
        ctx.setLineWidth(1)
        ctx.move(to: toView(last.p))
        ctx.addCurve(to: toView(hover),
                     control1: toView(last.p + last.outH),
                     control2: toView(hover))
        ctx.strokePath()

        // Over the first point with enough points to enclose something: this
        // click closes the path, so say so before it happens.
        if penClose(at: hover) != nil, let first = sp.anchors.first {
            let c = toView(first.p)
            ctx.setStrokeColor(FlipTheme.accent.rgba.cg)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        drag = .pan(convert(event.locationInWindow, from: nil))
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { drag = .none }

    // MARK: Zoom and pan

    override func scrollWheel(with event: NSEvent) {
        // Not while a card is over the canvas. See `AppModel.isCovered`.
        guard !model.isCovered else { return }
        if event.modifierFlags.contains(.command) {
            zoomBy(1 + event.scrollingDeltaY * 0.01, around: convert(event.locationInWindow, from: nil))
        } else {
            model.pan = CGPoint(x: model.pan.x + event.scrollingDeltaX,
                                y: model.pan.y + event.scrollingDeltaY)
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard !model.isCovered else { return }
        zoomBy(1 + event.magnification, around: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    /// Keeps the point under the cursor pinned while the scale changes.
    private func zoomBy(_ factor: CGFloat, around anchor: CGPoint) {
        let before = toDoc(anchor)
        model.zoom = min(max(model.zoom * factor, 0.05), 40)
        let after = toDoc(anchor)
        model.pan = CGPoint(x: model.pan.x + (after.x - before.x) * model.zoom,
                            y: model.pan.y + (after.y - before.y) * model.zoom)
    }

    /// Every panel floats over the canvas, so the usable area is not the whole
    /// view — leave it room on all four sides or a fitted artboard opens with its
    /// edges hidden behind the panels and the frame strip.
    func fitToWindow() {
        let margin: CGFloat = 32
        let top: CGFloat = margin
        let bottom: CGFloat = 96
        let left = model.showLayers
            ? FlipTheme.floatInset + FlipTheme.panelWidth + margin / 2
            : margin
        let right = model.showTools
            ? FlipTheme.floatInset + FlipTheme.panelWidth + margin / 2
            : margin

        let usableW = max(bounds.width - left - right, 80)
        let usableH = max(bounds.height - top - bottom, 80)
        model.zoom = max(min(usableW / model.doc.size.width,
                             usableH / model.doc.size.height), 0.05)
        // Centring happens against the full bounds, so offset by half the
        // difference between the insets to land in the usable area instead.
        model.pan = CGPoint(x: (left - right) / 2, y: (top - bottom) / 2)
        needsDisplay = true
    }

    // MARK: Keys

    /// Arrow-key nudge: a document point at a time, eight with shift held.
    ///
    /// Document points rather than screen ones, so a nudge means the same amount
    /// of artwork at every zoom — which is the opposite of the choice the stroke
    /// fitter needs, and right for the same reason: that one is about what the
    /// hand drew, this one is about where the shape sits.
    ///
    /// Undo is pushed only on the first key of a run. Holding an arrow down
    /// repeats about thirty times a second, and a step per repeat would flush
    /// the whole eighty-deep history in under three seconds; this way a held
    /// arrow is one undo and a tapped one is its own.
    private func nudge(_ event: NSEvent) {
        guard !model.selection.isEmpty else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 8 : 1
        let d: CGPoint
        switch event.keyCode {
        case 123: d = CGPoint(x: -step, y: 0)
        case 124: d = CGPoint(x: step, y: 0)
        // The view is flipped, so down the screen is up the number line.
        case 125: d = CGPoint(x: 0, y: step)
        default:  d = CGPoint(x: 0, y: -step)
        }
        if !event.isARepeat { model.commit() }
        model.translateSelection(by: d)
        model.invalidateThumbnail()
        needsDisplay = true
    }

    /// Bare-letter shortcuts live here rather than in the menu so they cannot
    /// fire while a rename field has the keyboard.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // ⇧⌘< and ⇧⌘> are handled here rather than declared on the menu
            // items, because SwiftUI drops a comma key equivalent: the menu came
            // out with the modifier set and *no key*, so `Move Frame Left` could
            // never fire. Reading the character ourselves is exact, and it keeps
            // the pair together — declaring one on the menu and one here would be
            // two mechanisms for one control.
            //
            // `<` and `>`, not `,` and `.`: `charactersIgnoringModifiers` ignores
            // every modifier *except shift*, so with shift held these keys report
            // the shifted character. Both spellings are accepted anyway, since
            // which one arrives is a property of the keyboard layout.
            if event.modifierFlags.contains(.shift),
               let c = event.charactersIgnoringModifiers {
                if c == "<" || c == "," { model.moveFrame(by: -1); needsDisplay = true; return }
                if c == ">" || c == "." { model.moveFrame(by: 1);  needsDisplay = true; return }
            }
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 51, 117:   // delete, forward delete
            if model.tool == .bezier, !model.selectedNodes.isEmpty { model.deleteSelectedNodes() }
            else { model.deleteSelection() }
            needsDisplay = true
            return
        case 53:        // escape
            // Repositioning first, and return accepts it below: it is the most
            // recently entered thing, and the one with the most to lose from a
            // key going somewhere else.
            if model.repositioning { model.endReposition(keep: false); needsDisplay = true; return }
            // The card first: it is the thing most recently opened, so it is the
            // thing escape is for.
            if model.showShortcuts { model.showShortcuts = false; return }
            // While drawing, escape ends the path rather than clearing the
            // selection — the path you just made is what you want selected.
            if pen != nil { endPen(); return }
            model.selection = []; model.selectedNodes = []
            needsDisplay = true
            return
        case 36, 76:    // return, enter
            if model.repositioning { model.endReposition(keep: true); needsDisplay = true; return }
            if pen != nil { endPen(); return }
        case 49:        // space
            model.togglePlay()
            return
        case 123, 124, 125, 126:    // ← → ↓ ↑
            nudge(event)
            return
        default:
            break
        }

        let shift = event.modifierFlags.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": model.tool = .select;  model.selectedNodes = []
        case "h": model.tool = .hand;    model.selectedNodes = []
        case "b": model.tool = .brush;   model.selectedNodes = []
        case "p": model.tool = .bezier
        case "r": model.tool = .rect;    model.selectedNodes = []
        // A for armature. The obvious letters were all taken by tools that came
        // first, and K reads as nothing at all.
        case "a": model.tool = .bone;    model.selectedNodes = []
        // O is the circle tool now, so onion skin moves onto its shifted twin.
        case "o":
            if shift { model.onionEnabled.toggle() }
            else { model.tool = .ellipse; model.selectedNodes = [] }
        // The keys `<` and `>` are printed on. Both spellings, so it works
        // whether or not shift is held to reach the character on the keycap —
        // `charactersIgnoringModifiers` keeps shift applied, so the two arrive as
        // different characters from the same key.
        case ",", "<": model.stop(); model.step(-1)
        case ".", ">": model.stop(); model.step(1)
        // The brackets moved off frame stepping and onto layer order, where the
        // rest of this platform keeps them.
        case "]": model.moveSelectionToEnd(front: true)
        case "[": model.moveSelectionToEnd(front: false)
        case "n": model.addFrame(duplicate: false)
        default:
            super.keyDown(with: event)
            return
        }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NotificationCenter.default.addObserver(
            forName: .flipFitToWindow, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToWindow() }
        }
    }

    // MARK: Hit testing

    private func topLayer(at p: CGPoint) -> Layer? {
        model.frame.layers.last { Render.hit(posed($0), p, tolerance: pick) }
    }

    /// The shape under the pointer, however deep it is grouped.
    ///
    /// `topLayer` stops at the top of the stack on purpose: a plain click on a
    /// grouped drawing should take the whole group, because that is what a
    /// group is for. This is the other half, and what ⌘ asks for — the leaf you
    /// are actually pointing at.
    ///
    /// Descends into groups only. A boolean's children are its *inputs*, not
    /// things that stand on their own — reaching in and moving one would change
    /// the result rather than move a shape, which is what Release is for.
    private func deepLayer(at p: CGPoint) -> Layer? {
        func search(_ layers: [Layer]) -> Layer? {
            for l in layers.reversed() where l.visible {
                if l.isGroup, let deeper = search(l.children) { return deeper }
                if !l.isGroup, Render.hit(posed(l), p, tolerance: pick) { return l }
            }
            return nil
        }
        return search(model.frame.layers)
    }

    /// Whether the pointer is on something already selected, at any depth.
    ///
    /// This is what makes a grouped shape draggable. Without it the press fell
    /// through to `topLayer`, which can only ever see the group — so selecting
    /// a child in the panel and dragging it on the canvas threw the selection
    /// away, took the whole group instead, and moved all of it.
    private func selectionHit(at p: CGPoint) -> Bool {
        model.selection.contains { id in
            guard let l = LayerTree.find(id, in: model.frame.layers) else { return false }
            return Render.hit(posed(l), p, tolerance: pick)
        }
    }

    private func anchor(at p: CGPoint) -> NodeRef? {
        var best: (NodeRef, CGFloat)?
        for layer in model.penShapes {
            guard let shape = layer.shape else { continue }
            for (si, sp) in shape.subpaths.enumerated() {
                for (ai, a) in sp.anchors.enumerated() {
                    let d = a.p.dist(p)
                    guard d < grab else { continue }
                    if best == nil || d < best!.1 {
                        best = (NodeRef(layer: layer.id, subpath: si, anchor: ai), d)
                    }
                }
            }
        }
        return best?.0
    }

    /// Only the handles that are on screen, which is only the picked points'.
    ///
    /// It used to sweep every anchor of every selected layer, so a click could
    /// catch a handle that was not drawn — and now that handles appear only for
    /// picked points, that would be a grab on nothing visible at all.
    private func handle(at p: CGPoint) -> (NodeRef, Bool)? {
        for ref in model.selectedNodes {
            guard let layer = LayerTree.find(ref.layer, in: model.frame.layers),
                  let shape = layer.shape,
                  shape.subpaths.indices.contains(ref.subpath),
                  shape.subpaths[ref.subpath].anchors.indices.contains(ref.anchor)
            else { continue }
            let a = shape.subpaths[ref.subpath].anchors[ref.anchor]
            if a.outH.length > 0.5, (a.p + a.outH).dist(p) < grab { return (ref, true) }
            if a.inH.length > 0.5, (a.p + a.inH).dist(p) < grab  { return (ref, false) }
        }
        return nil
    }

    /// The nearest other open endpoint, so the ring shows before you let go.
    private func findSnap(from ref: NodeRef, at p: CGPoint) {
        var best: (NodeRef, CGPoint, CGFloat)?
        for (candidate, position) in model.openEndpoints(excluding: ref) {
            let d = position.dist(p)
            guard d < model.snapDistance else { continue }
            if best == nil || d < best!.2 { best = (candidate, position, d) }
        }
        // Only an endpoint can be welded to another endpoint.
        if isEndpoint(ref), let best { snapTarget = (best.0, best.1) } else { snapTarget = nil }
    }

    private func isEndpoint(_ ref: NodeRef) -> Bool {
        guard let l = LayerTree.find(ref.layer, in: model.frame.layers), let s = l.shape,
              s.subpaths.indices.contains(ref.subpath) else { return false }
        let sp = s.subpaths[ref.subpath]
        return !sp.closed && (ref.anchor == 0 || ref.anchor == sp.anchors.count - 1)
    }
}
