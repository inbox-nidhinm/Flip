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

    static let size = CGSize(width: 168, height: 24)

    /// `tint` is the menu's own text colour, so the sample reads as part of the
    /// list rather than as a picture pasted into it.
    @MainActor static func image(_ nib: Nib, tint: RGBA) -> CGImage? {
        let key = "\(nib.rawValue)-\(tint.hex6)"
        if let hit = cache[key] { return hit }
        guard let made = render(nib, tint: tint) else { return nil }
        cache[key] = made
        return made
    }

    private static func render(_ nib: Nib, tint: RGBA) -> CGImage? {
        let scale: CGFloat = 2
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
        let amp = size.height * 0.26
        path.move(to: CGPoint(x: 6, y: mid))
        for i in 1...48 {
            let t = CGFloat(i) / 48
            path.addLine(to: CGPoint(x: 6 + t * (size.width - 12),
                                     y: mid + sin(t * .pi * 2.1) * amp))
        }

        let width: CGFloat = 6
        ctx.setFillColor(tint.cg)
        if nib.isPencil, let mark = Pencil.mark(path, nib: nib, width: width,
                                                seed: Render.paperSeed) {
            ctx.addPath(mark)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.setStrokeColor(tint.cg)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
