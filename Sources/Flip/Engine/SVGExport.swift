import CoreGraphics
import Foundation

/// Writes the document as one animated SVG.
///
/// Frames are hard cuts, not tweens, so each frame is a group that is invisible
/// by default and switched on for its slice of the cycle by a CSS animation with
/// a per-frame delay. No interpolation is involved, which is what makes the file
/// play identically everywhere.
///
/// Booleans become **masks**, mirroring the clipping the canvas does:
///   subtract   one mask — the first child in white, the others in black
///   intersect  nested masks, one per child
///   unite      a single path, `fill-rule="nonzero"`
///   exclude    a single path, `fill-rule="evenodd"`
/// Mask content is arbitrary SVG, so a boolean nested inside another boolean
/// works at any depth.
struct SVGExport {
    let doc: Document

    private final class Defs {
        var body: [String] = []
        var n = 0
        func nextID() -> String { n += 1; return "m\(n)" }
    }

    /// Stands in for "everywhere", the same way the renderer's `huge` rect does.
    private static let huge = #"x="-100000" y="-100000" width="200000" height="200000""#

    func svg() -> String {
        let defs = Defs()
        let w = f(doc.size.width), h = f(doc.size.height)

        // Stepped in play order, so a bounce comes out as a bounce. Each frame
        // is *rendered* once however many times it is played: rendering it again
        // would emit a second copy of every mask it needs, and a mask can be
        // referenced from as many groups as like.
        let order = doc.playOrder
        var inners: [Int: String] = [:]
        var groups: [String] = []
        for (step, i) in order.enumerated() {
            let inner: String
            if let done = inners[i] {
                inner = done
            } else {
                var parts = doc.frames[i].layers
                    .map { render($0, defs: defs, indent: "      ") }
                    .filter { !$0.isEmpty }
                // The artboard again, inside the frame this time — but only for
                // a frame that has something blending in it.
                //
                // `mix-blend-mode` reaches only as far as its own stacking
                // context, and every frame group is one: they carry an animated
                // `opacity`, which is what makes them one. So the ground the
                // layers blend onto has to be *inside* the group; the rect at
                // the top of the file is outside it and a multiplied layer would
                // find nothing under it but transparency. Written only where it
                // changes something, so a document that blends nothing exports
                // byte for byte what it did before.
                if blends(doc.frames[i].layers) {
                    parts.insert("      <rect width=\"\(f(doc.size.width))\" "
                                 + "height=\"\(f(doc.size.height))\" "
                                 + "fill=\"\(doc.background.hex)\"/>", at: 0)
                }
                inner = parts.joined(separator: "\n")
                inners[i] = inner
            }
            let delay = Double(step) / max(doc.fps, 1)
            let attrs = order.count > 1
                ? #" class="\#(isHold(step) ? "hold" : "fr")" style="animation-delay:\#(f(delay))s""#
                : ""
            groups.append("    <g\(attrs)>\n\(inner)\n    </g>")
        }

        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(w) \(h)" width="\(w)" height="\(h)" shape-rendering="geometricPrecision">
          <title>Flip animation — \(doc.frames.count) frame\(doc.frames.count == 1 ? "" : "s") at \(f(doc.fps)) fps</title>
        \(style())  <rect width="\(w)" height="\(h)" fill="\(doc.background.hex)"/>
          <defs>
        \(defs.body.joined(separator: "\n"))
          </defs>
        \(groups.joined(separator: "\n"))
        </svg>
        """
    }

    // MARK: Timing

    /// The last *step*, not the last frame — under a bounce those are different
    /// frames, and only `once` holds anything at all.
    private func isHold(_ step: Int) -> Bool {
        doc.mode == .once && step == doc.playOrder.count - 1
    }

    private func style() -> String {
        guard doc.playOrder.count > 1 else { return "" }
        // The cycle is the played sequence, so a bounce's slice is one step of
        // the way out and back rather than one frame of the document.
        let n = Double(doc.playOrder.count)
        let slice = 100.0 / n
        // Two stops at the same value then an immediate drop, so the browser has
        // nothing to interpolate between and the cut stays hard.
        let cut = min(slice + 0.001, 99.999)
        let iteration = doc.mode == .once ? "1" : "infinite"
        let fill = doc.mode == .once ? "animation-fill-mode:forwards;" : ""
        return """
          <style>
            .fr,.hold{opacity:0;animation-duration:\(f(doc.duration))s;animation-iteration-count:\(iteration);\(fill)}
            .fr{animation-name:flip}
            .hold{animation-name:flipHold}
            @keyframes flip{0%{opacity:1}\(f(slice))%{opacity:1}\(f(cut))%{opacity:0}100%{opacity:0}}
            @keyframes flipHold{0%{opacity:1}100%{opacity:1}}
          </style>

        """
    }

    /// Whether anything in this stack blends, at any depth.
    private func blends(_ layers: [Layer]) -> Bool {
        layers.contains { $0.visible && ($0.blending != .normal || blends($0.children)) }
    }

    // MARK: Layers

    private func render(_ layer: Layer, defs: Defs, indent: String, override: RGBA? = nil) -> String {
        guard layer.visible else { return "" }
        let body = element(layer, defs: defs, indent: indent, override: override)

        // A layer's own opacity and blend mode composite the whole layer as a
        // unit, which is exactly what `opacity` and `mix-blend-mode` on a group
        // do — and what the canvas does with a transparency layer. Not
        // `fill-opacity`, which would let a half-opacity shape show its own
        // stroke through its own fill.
        //
        // Dropped under an `override`, where the layer is being stamped into a
        // mask and has to come out solid.
        guard override == nil, !body.isEmpty else { return body }
        var attrs = ""
        if layer.alpha < 0.999 { attrs += " opacity=\"\(f(layer.alpha))\"" }
        if layer.blending != .normal {
            attrs += " style=\"mix-blend-mode:\(layer.blending.css)\""
        }
        guard !attrs.isEmpty else { return body }
        return "\(indent)<g\(attrs)>\n\(body)\n\(indent)</g>"
    }

    private func element(_ layer: Layer, defs: Defs, indent: String, override: RGBA?) -> String {
        let fill   = override ?? layer.fill
        let stroke = override != nil ? nil : layer.stroke
        let width  = layer.strokeWidth

        switch layer.content {
        case .shape(let s):
            guard !s.isEmpty else { return "" }
            // A pencil is a shape, not a stroke, and that is the whole reason it
            // was built from geometry: the mark exports as a filled path like
            // anything else here, rather than needing a picture of itself.
            if let nib = layer.nib, nib.isPencil, let stroke, width > 0,
               let mark = Pencil.mark(s.cgPath, nib: nib, width: width,
                                      seed: Render.paperSeed) {
                var out = ""
                if let fill {
                    out += indent + path(s.svgPathData, fill: fill, rule: "nonzero",
                                         stroke: nil, width: 0) + "\n"
                }
                return out + indent + path(mark.svgPathData, fill: stroke, rule: "evenodd",
                                           stroke: nil, width: 0)
            }
            return indent + path(s.svgPathData, fill: fill, rule: "nonzero",
                                 stroke: stroke, width: width)

        case .group(let kids):
            // Nothing but a container: the children keep their own paint and
            // their own order. A `<g>` even when it needs no attributes, so the
            // exported file has the same shape as the document.
            let inner = kids
                .map { render($0, defs: defs, indent: indent + "  ", override: override) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !inner.isEmpty else { return "" }
            return "\(indent)<g>\n\(inner)\n\(indent)</g>"

        case .boolean(let op, let kids):
            let live = kids.filter { $0.visible }
            guard let first = live.first else { return "" }
            let rest = Array(live.dropFirst())

            switch op {
            case .unite, .exclude:
                let d = live.compactMap { flatPath($0) }
                guard d.count == live.count else {
                    return render(.init(name: layer.name, content: .boolean(.intersect, live)),
                                  defs: defs, indent: indent, override: override)
                }
                let combined = d.joined(separator: " ")

                // A union's combined path still holds the seams where its children
                // overlap, which are not edges of the result. Fill from it, then
                // stroke it through a mask that removes the interior, leaving one
                // outline on the boundary. Exclude needs none of this — there the
                // overlap genuinely is a boundary.
                if op == .unite, let stroke, width > 0 {
                    let id = defs.nextID()
                    defs.body.append("""
                        <mask id="\(id)" maskUnits="userSpaceOnUse">
                          <rect \(Self.huge) fill="#FFFFFF"/>
                          <path d="\(combined)" fill="#000000"/>
                        </mask>
                    """)
                    var out = [indent + path(combined, fill: fill, rule: "nonzero", stroke: nil, width: 0)]
                    out.append("\(indent)<g mask=\"url(#\(id))\">")
                    out.append(indent + "  " + path(combined, fill: nil, rule: "nonzero",
                                                    stroke: stroke, width: width * 2))
                    out.append("\(indent)</g>")
                    return out.joined(separator: "\n")
                }

                return indent + path(combined, fill: fill,
                                     rule: op == .unite ? "nonzero" : "evenodd",
                                     stroke: stroke, width: width)

            case .subtract:
                let id = defs.nextID()
                var mask = ["    <mask id=\"\(id)\" maskUnits=\"userSpaceOnUse\">"]
                mask.append(render(first, defs: defs, indent: "      ", override: RGBA(1, 1, 1, 1)))
                for kid in rest {
                    mask.append(render(kid, defs: defs, indent: "      ", override: RGBA(0, 0, 0, 1)))
                }
                mask.append("    </mask>")
                defs.body.append(mask.filter { !$0.isEmpty }.joined(separator: "\n"))
                return group(mask: id, over: live, fill: fill, stroke: stroke,
                             width: width, defs: defs, indent: indent)

            case .intersect:
                // One mask per child, nested, because luminance masks do not
                // combine on a single element.
                var ids: [String] = []
                for kid in live {
                    let id = defs.nextID()
                    defs.body.append("""
                        <mask id="\(id)" maskUnits="userSpaceOnUse">
                    \(render(kid, defs: defs, indent: "      ", override: RGBA(1, 1, 1, 1)))
                        </mask>
                    """)
                    ids.append(id)
                }
                var body = paint(over: live, fill: fill, stroke: stroke, width: width,
                                 indent: indent + String(repeating: "  ", count: ids.count))
                for id in ids.reversed() {
                    body = "\(indent)<g mask=\"url(#\(id))\">\n\(body)\n\(indent)</g>"
                }
                return body
            }
        }
    }

    /// A `<g mask=…>` holding the fill and the double-width child strokes.
    private func group(mask id: String, over live: [Layer], fill: RGBA?, stroke: RGBA?,
                       width: CGFloat, defs: Defs, indent: String) -> String {
        let inner = paint(over: live, fill: fill, stroke: stroke, width: width, indent: indent + "  ")
        return "\(indent)<g mask=\"url(#\(id))\">\n\(inner)\n\(indent)</g>"
    }

    /// Fill covers everything and the mask trims it. Child outlines are stroked
    /// at double width so the mask keeps exactly the half that lies on the
    /// result's edge — the same trick the canvas renderer uses.
    private func paint(over live: [Layer], fill: RGBA?, stroke: RGBA?,
                       width: CGFloat, indent: String) -> String {
        var out: [String] = []
        if let fill {
            out.append("\(indent)<rect \(Self.huge) fill=\"\(fill.hex)\"\(opacity(fill))/>")
        }
        if let stroke, width > 0 {
            for kid in live {
                guard let d = flatPath(kid) else { continue }
                out.append(indent + path(d, fill: nil, rule: "nonzero",
                                         stroke: stroke, width: width * 2))
            }
        }
        return out.joined(separator: "\n")
    }

    /// The one path a layer reduces to, when it has one.
    private func flatPath(_ layer: Layer) -> String? {
        switch layer.content {
        case .shape(let s):
            return s.isEmpty ? nil : s.svgPathData
        case .boolean(let op, let kids):
            guard op == .unite || op == .exclude else { return nil }
            let live = kids.filter { $0.visible }
            let parts = live.compactMap { flatPath($0) }
            guard parts.count == live.count, !parts.isEmpty else { return nil }
            return parts.joined(separator: " ")

        case .group:
            // Its children each carry their own paint, so it has no single path —
            // the same reason the renderer's `region` gives up on a group.
            return nil
        }
    }

    // MARK: Primitives

    private func path(_ d: String, fill: RGBA?, rule: String,
                      stroke: RGBA?, width: CGFloat) -> String {
        var a = ["<path d=\"\(d)\""]
        if let fill {
            a.append("fill=\"\(fill.hex)\"\(opacity(fill).trimmingCharacters(in: .whitespaces))")
            if rule != "nonzero" { a.append("fill-rule=\"\(rule)\"") }
        } else {
            a.append("fill=\"none\"")
        }
        if let stroke, width > 0 {
            a.append("stroke=\"\(stroke.hex)\"")
            a.append("stroke-width=\"\(f(width))\"")
            a.append("stroke-linejoin=\"round\"")
            a.append("stroke-linecap=\"round\"")
            if stroke.a < 1 { a.append("stroke-opacity=\"\(f(stroke.a))\"") }
        }
        return a.joined(separator: " ") + "/>"
    }

    private func opacity(_ c: RGBA) -> String { c.a < 1 ? " fill-opacity=\"\(f(c.a))\"" : "" }

    private func f(_ v: CGFloat) -> String { f(Double(v)) }
    private func f(_ v: Double) -> String {
        let s = String(format: "%.3f", v)
        var t = s
        while t.contains("."), t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t.isEmpty ? "0" : t
    }
}
