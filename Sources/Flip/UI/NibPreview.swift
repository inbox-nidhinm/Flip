import AppKit
import CoreGraphics

/// A sample stroke of each nib, for the picker.
///
/// Drawn with the same `Pencil` the canvas uses rather than with artwork of its
/// own: a picker that shows a drawing of a brush instead of the brush's own
/// mark is a picker that can be wrong, and this one cannot — change the nib and
/// the sample changes with it.
enum NibPreview {
    private static var cache: [String: CGImage] = [:]

    static let height: CGFloat = 22

    /// `tint` is the menu's own text colour, so the sample reads as part of the
    /// list rather than as a picture pasted into it.
    ///
    /// Drawn to the width it will be shown at rather than scaled into it: the
    /// sample is a *stroke*, and a stroke stretched to fit is a lie about the
    /// brush — the grain smears out with it. Cached per width, of which there
    /// are only ever one or two.
    @MainActor static func image(_ nib: Nib, tint: RGBA, width: CGFloat = 168) -> CGImage? {
        let w = max(40, width.rounded())
        let key = "\(nib.rawValue)-\(tint.hex6)-\(Int(w))"
        if let hit = cache[key] { return hit }
        guard let made = render(nib, tint: tint, width: w) else { return nil }
        cache[key] = made
        return made
    }

    private static func render(_ nib: Nib, tint: RGBA, width: CGFloat) -> CGImage? {
        let scale: CGFloat = 2
        let size = CGSize(width: width, height: height)
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        // A wave rather than a straight line: a brush's character is in how it
        // turns, and a horizontal rule shows none of it.
        let path = CGMutablePath()
        let mid = size.height / 2
        let amp = size.height * 0.28
        // The inset is half the stroke's width, so a round cap finishes flush
        // with the end of the box rather than being clipped by it.
        let inset: CGFloat = 4
        path.move(to: CGPoint(x: inset, y: mid))
        let steps = max(24, Int(size.width / 4))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: inset + t * (size.width - inset * 2),
                                     y: mid + sin(t * .pi * 2.1) * amp))
        }

        let stroke: CGFloat = 6
        ctx.setFillColor(tint.cg)
        if nib.isPencil, let mark = Pencil.mark(path, nib: nib, width: stroke,
                                                seed: Render.paperSeed) {
            ctx.addPath(mark)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.setStrokeColor(tint.cg)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
