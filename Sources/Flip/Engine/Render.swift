import CoreGraphics
import AppKit

/// A closed area, plus the winding rule that decides what is inside it.
struct Region {
    var path: CGPath
    var rule: CGPathFillRule
}

/// Draws a frame with CoreGraphics.
///
/// CoreGraphics has no boolean path operator, and this app never needs one.
/// Every operation is expressed as *clipping* instead of geometry, which is
/// exact — no flattening curves to polylines — and maps one-to-one onto SVG's
/// `clipPath`/`mask`, so the canvas and the export agree by construction.
///
///   unite      combined path, non-zero fill
///   exclude    combined path, even-odd fill
///   intersect  clip to every child in turn
///   subtract   clip to the first child, then to the *outside* of each other
///              (a huge rect plus that child, filled even-odd)
enum Render {
    /// One sheet of paper under the whole document. Fixed rather than per-layer
    /// so strokes that cross land on the same tooth — a seed per layer would
    /// give every mark its own private paper, which reads as collage.
    static let paperSeed: UInt64 = 0x50415045_52000001
    /// Large enough to stand in for "everywhere" when inverting a clip.
    static let huge = CGRect(x: -1e5, y: -1e5, width: 2e5, height: 2e5)

    // MARK: Regions

    /// The single path a layer reduces to, or `nil` when it needs clipping.
    static func region(_ layer: Layer) -> Region? {
        switch layer.content {
        case .shape(let s):
            return s.isEmpty ? nil : Region(path: s.cgPath, rule: .winding)

        case .boolean(let op, let kids):
            let live = kids.filter { $0.visible }
            guard !live.isEmpty else { return nil }
            guard op == .unite || op == .exclude else { return nil }
            let regions = live.compactMap { region($0) }
            guard regions.count == live.count else { return nil }
            let combined = CGMutablePath()
            regions.forEach { combined.addPath($0.path) }
            return Region(path: combined, rule: op == .unite ? .winding : .evenOdd)

        case .group:
            // A group's children each keep their own paint, so there is no one
            // region that stands for the group — unlike a union, whose children
            // are all painted in the union's colour and so can be one path.
            return nil
        }
    }

    // MARK: Painting

    /// Every layer, as the frame's armatures leave it.
    ///
    /// `posed` is applied here rather than at each call site so the canvas, the
    /// onion skins, the frame thumbnails and the raster exports all agree — the
    /// stored geometry is the rest pose, and this is the only place that turns it
    /// into what you see.
    static func draw(_ frame: Frame, in ctx: CGContext, tint: RGBA? = nil, alpha: Double = 1) {
        for layer in frame.layers { draw(frame.painted(layer), in: ctx, tint: tint, alpha: alpha) }
    }

    /// `override` forces a flat opaque fill and drops the stroke. Boolean groups
    /// use it to paint their children in the group's own colour, and the
    /// compositing fallback uses it to stamp a silhouette.
    static func draw(_ layer: Layer, in ctx: CGContext,
                     tint: RGBA? = nil, alpha: Double = 1, override: RGBA? = nil) {
        guard layer.visible else { return }

        // A layer's own opacity and blend mode are both *composited*, not
        // folded into its paint: they act on the layer as a unit, so a
        // half-opacity shape does not show its own stroke through its own fill,
        // and a multiplied group multiplies once as a whole rather than once per
        // child — its children do not multiply with each other on the way. Same
        // rule as SVG's `opacity` and `mix-blend-mode`, which is what the export
        // writes.
        //
        // Which is what the transparency layer is for. Core Graphics applies the
        // alpha and the blend mode set *before* `beginTransparencyLayer` when
        // the layer is composited back down, and resets both to their defaults
        // inside it — so everything in the layer paints normally against nothing
        // and the result meets the backdrop once.
        //
        // Skipped under an `override`, where the layer is being stamped as a
        // silhouette for a mask and has to come out solid.
        let blend = layer.blending
        if override == nil, layer.alpha < 0.999 || blend != .normal {
            ctx.saveGState()
            ctx.setAlpha(layer.alpha)
            ctx.setBlendMode(blend.cg)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            paint(layer, in: ctx, tint: tint, alpha: alpha, override: nil)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        }
        paint(layer, in: ctx, tint: tint, alpha: alpha, override: override)
    }

    /// One layer's own painting, with its opacity already accounted for.
    private static func paint(_ layer: Layer, in ctx: CGContext,
                              tint: RGBA?, alpha: Double, override: RGBA?) {
        // A plain group does nothing to its children but hold them: they keep
        // their own paint and their own order, bottom of the stack first. Its own
        // fill and stroke are not used — a group is a name and a place in the
        // stack, not a shape. Under an `override` the children are stamped in
        // that colour, which is what lets a group sit inside a boolean.
        if case .group(let kids) = layer.content {
            for kid in kids { draw(kid, in: ctx, tint: tint, alpha: alpha, override: override) }
            return
        }

        // A tint *recolours* what the layer already paints; it must never add paint
        // the layer does not have. Substituting it in directly gave every
        // unfilled path a fill, so an onion-skinned outline came out as a solid
        // tinted blob that buried whatever was behind it.
        let fill: RGBA?
        let stroke: RGBA?
        if let override {
            fill = override
            stroke = nil
        } else {
            fill = layer.fill.map { tint ?? $0 }
            stroke = layer.stroke.map { tint ?? $0 }
        }

        if let r = region(layer) {
            // A union's combined path still contains the seams where its children
            // overlap, and those are not edges of the result. Fill from the
            // combined path, but take the outline from the children with the
            // union's interior punched out, which erases the seams entirely.
            // (Exclude needs no such care — there the overlap *is* a boundary.)
            if case .boolean(.unite, let kids) = layer.content, let stroke {
                if let fill {
                    ctx.addPath(r.path)
                    ctx.setFillColor(fill.cg(alpha: alpha))
                    ctx.fillPath(using: r.rule)
                }
                outline(kids.filter { $0.visible }, hollowing: r, in: ctx,
                        stroke: stroke, width: layer.strokeWidth, alpha: alpha)
                return
            }
            // The paper is fixed to the sheet, not to the layer: the seed is the
            // same for every stroke so two that cross meet the same tooth.
            paint(r, in: ctx, fill: fill, stroke: stroke, width: layer.strokeWidth,
                  alpha: alpha, nib: layer.nib ?? .pen, seed: paperSeed)
            return
        }

        guard case .boolean(let op, let kids) = layer.content else { return }
        let live = kids.filter { $0.visible }
        guard let first = live.first else { return }
        let rest = Array(live.dropFirst())

        let regions = live.map { region($0) }
        if regions.allSatisfy({ $0 != nil }) {
            clipped(op, regions.map { $0! }, in: ctx,
                    fill: fill, stroke: stroke, width: layer.strokeWidth, alpha: alpha)
        } else {
            // A child is itself a subtract or intersect, so there is no single
            // path to clip with. Composite instead: stamp the first child, then
            // punch the others out of it inside a transparency layer.
            composited(op, first: first, rest: rest, in: ctx,
                       fill: fill, alpha: alpha)
        }
    }

    private static func paint(_ r: Region, in ctx: CGContext,
                              fill: RGBA?, stroke: RGBA?, width: CGFloat, alpha: Double,
                              nib: Nib = .pen, seed: UInt64 = 0) {
        if let fill {
            ctx.addPath(r.path)
            ctx.setFillColor(fill.cg(alpha: alpha))
            ctx.fillPath(using: r.rule)
        }
        guard let stroke, width > 0 else { return }
        // The nib takes the outline and nothing else — the fill above is the
        // layer's own either way, which is what makes this an addition to the
        // stroke rather than a replacement for it.
        //
        // A shape, so it is filled rather than stroked, and with the even-odd
        // rule so the holes the paper punched through it stay holes.
        if nib.isPencil,
           let mark = Pencil.mark(r.path, nib: nib, width: width, seed: seed) {
            ctx.addPath(mark)
            ctx.setFillColor(stroke.cg(alpha: alpha))
            ctx.fillPath(using: .evenOdd)
            return
        }
        ctx.addPath(r.path)
        ctx.setStrokeColor(stroke.cg(alpha: alpha))
        ctx.setLineWidth(width)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    /// Strokes the children at double width, then removes everything that falls
    /// inside `region` — leaving one continuous outline on the result's boundary
    /// and nothing along its interior seams.
    private static func outline(_ kids: [Layer], hollowing r: Region, in ctx: CGContext,
                                stroke: RGBA, width: CGFloat, alpha: Double) {
        guard width > 0 else { return }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setStrokeColor(stroke.cg(alpha: alpha))
        ctx.setLineWidth(width * 2)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        for kid in kids { if let kr = self.region(kid) { ctx.addPath(kr.path) } }
        ctx.strokePath()
        ctx.setBlendMode(.destinationOut)
        ctx.addPath(r.path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath(using: r.rule)
        ctx.setBlendMode(.normal)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func clipped(_ op: BoolOp, _ regions: [Region], in ctx: CGContext,
                                fill: RGBA?, stroke: RGBA?, width: CGFloat, alpha: Double) {
        guard let first = regions.first else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch op {
        case .intersect:
            for r in regions { ctx.addPath(r.path); ctx.clip(using: r.rule) }
        case .subtract:
            ctx.addPath(first.path)
            ctx.clip(using: first.rule)
            for r in regions.dropFirst() {
                let inverse = CGMutablePath()
                inverse.addRect(huge)
                inverse.addPath(r.path)
                ctx.addPath(inverse)
                ctx.clip(using: .evenOdd)
            }
        case .unite, .exclude:
            return  // handled by `region`
        }

        if let fill {
            ctx.setFillColor(fill.cg(alpha: alpha))
            ctx.fill(huge)
        }
        if let stroke, width > 0 {
            // The result outline has no path of its own, so stroke every child
            // at double width and let the clip keep the correct half. Standard
            // trick, and it lands on the true edge of the result.
            ctx.setStrokeColor(stroke.cg(alpha: alpha))
            ctx.setLineWidth(width * 2)
            ctx.setLineJoin(.round)
            for r in regions { ctx.addPath(r.path) }
            ctx.strokePath()
        }
    }

    private static func composited(_ op: BoolOp, first: Layer, rest: [Layer], in ctx: CGContext,
                                   fill: RGBA?, alpha: Double) {
        guard let fill else { return }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(first, in: ctx, alpha: alpha, override: fill)
        ctx.setBlendMode(op == .intersect ? .destinationIn : .destinationOut)
        for kid in rest { draw(kid, in: ctx, alpha: 1, override: RGBA(0, 0, 0, 1)) }
        ctx.setBlendMode(.normal)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Paints the tracing reference. Expects a y-down context already in document
    /// coordinates — which is both the flipped canvas view and the bitmap contexts
    /// here, so one implementation serves both.
    ///
    /// A `CGImage` is drawn bottom-up, so in a y-down context it would land
    /// upside down; reflecting about the destination rect's own centre line puts
    /// it right without disturbing anything else in the transform.
    static func drawReference(_ ref: Reference, image: CGImage,
                              in ctx: CGContext, docSize: CGSize) {
        guard ref.visible, ref.opacity > 0.001 else { return }
        let r = ref.rect(in: docSize)
        ctx.saveGState()
        ctx.setAlpha(ref.opacity)
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: r.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: r)
        ctx.restoreGState()
    }

    // MARK: Hit testing

    static func hit(_ layer: Layer, _ p: CGPoint, tolerance: CGFloat) -> Bool {
        guard layer.visible else { return false }
        switch layer.content {
        case .shape(let s):
            guard !s.isEmpty else { return false }
            let path = s.cgPath
            // Reject on the bounding box first. Building the stroked outline below
            // is by far the most expensive thing in a click, and for every layer
            // the pointer is nowhere near it is wasted work.
            let slack = max(layer.strokeWidth, tolerance * 2)
            guard path.boundingBoxOfPath.insetBy(dx: -slack, dy: -slack).contains(p) else { return false }
            if layer.fill != nil, s.hasFillableArea, path.contains(p, using: .winding) { return true }
            let outline = path.copy(strokingWithWidth: slack,
                                    lineCap: .round, lineJoin: .round, miterLimit: 10)
            return outline.contains(p)

        case .group(let kids):
            return kids.contains { hit($0, p, tolerance: tolerance) }

        case .boolean(let op, let kids):
            let live = kids.filter { $0.visible }
            guard let first = live.first else { return false }
            switch op {
            case .unite, .exclude:  return live.contains { hit($0, p, tolerance: tolerance) }
            case .intersect:        return live.allSatisfy { hit($0, p, tolerance: tolerance) }
            case .subtract:
                return hit(first, p, tolerance: tolerance)
                    && !live.dropFirst().contains { hit($0, p, tolerance: tolerance) }
            }
        }
    }

    static func bounds(_ layer: Layer) -> CGRect {
        switch layer.content {
        case .shape(let s):
            return s.isEmpty ? .null : s.cgPath.boundingBoxOfPath
        case .boolean(_, let kids), .group(let kids):
            return kids.reduce(CGRect.null) { $0.union(bounds($1)) }
        }
    }

    // MARK: Thumbnails

    static func image(of frame: Frame, doc: Document, height: CGFloat) -> CGImage? {
        let scale = height / doc.size.height
        return raster(frame, doc: doc,
                      pixelSize: CGSize(width: doc.size.width * scale, height: height),
                      background: doc.background)
    }

    /// Rasterises one frame at an arbitrary size. A `nil` background leaves the
    /// bitmap transparent, which is what the GIF encoder wants.
    static func raster(_ frame: Frame, doc: Document,
                       pixelSize: CGSize, background: RGBA?) -> CGImage? {
        let w = max(1, Int(pixelSize.width.rounded()))
        let h = max(1, Int(pixelSize.height.rounded()))
        guard doc.size.width > 0, doc.size.height > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        if let background {
            ctx.setFillColor(background.cg)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Document space is y-down; a bitmap context is y-up.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / doc.size.width, y: -CGFloat(h) / doc.size.height)
        ctx.interpolationQuality = .high
        draw(frame, in: ctx)
        return ctx.makeImage()
    }
}
