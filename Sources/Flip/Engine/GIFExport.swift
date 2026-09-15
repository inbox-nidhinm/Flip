import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Writes the document as an animated GIF.
///
/// GIF is a poor fit for this kind of artwork and the two places it shows are
/// worth knowing about:
///
/// **Timing is quantised to hundredths of a second.** 12 fps wants 8.333 cs a
/// frame, which has to land on 8 or 9. Rounding every frame the same way drifts
/// — thirty frames at 8 cs runs 7% fast — so the remainder is carried from one
/// frame to the next and the total duration comes out right even though
/// individual frames differ by a hundredth.
///
/// **Alpha is one bit.** A pixel is either fully there or fully absent; there is
/// no partial coverage. Antialiased edges therefore have to be thresholded, and
/// the pixels that survive are un-premultiplied so they keep their own colour
/// rather than fading toward black — dark fringing is the usual giveaway of a
/// carelessly made transparent GIF.
struct GIFExport {
    let doc: Document
    /// Transparent background instead of the artboard's paper colour.
    var transparent: Bool
    /// Fraction of the artboard's size. GIF has no compression to speak of, so
    /// full-size frames get very large very quickly.
    var scale: CGFloat
    /// Coverage a pixel needs before it is kept at all, when transparent.
    var alphaThreshold: Double

    enum Failure: LocalizedError {
        case destination
        case frame(Int)
        case finalize

        var errorDescription: String? {
            switch self {
            case .destination:   return "Could not start writing the GIF."
            case .frame(let i):  return "Frame \(i + 1) could not be rendered."
            case .finalize:      return "The GIF could not be completed."
            }
        }
    }

    var pixelSize: CGSize {
        CGSize(width: max(1, (doc.size.width * scale).rounded()),
               height: max(1, (doc.size.height * scale).rounded()))
    }

    /// Per-frame delays in hundredths of a second, with the rounding error
    /// carried forward so the animation does not drift off its frame rate.
    var delays: [Int] {
        let ideal = 100.0 / max(doc.fps, 1)
        var out: [Int] = []
        var carry = 0.0
        for _ in doc.playOrder {
            let want = ideal + carry
            // Anything under two hundredths is widely re-interpreted as ten, so
            // that is the floor rather than one.
            let take = max(2, Int(want.rounded()))
            carry = want - Double(take)
            out.append(take)
        }
        return out
    }

    var estimatedDuration: Double { Double(delays.reduce(0, +)) / 100.0 }

    func write(to url: URL) throws {
        // The frames as played, not as stored — a bounce writes its interior
        // frames a second time on the way back, which is the only way GIF can
        // carry one. GIF has no notion of playing a range in reverse.
        let order = doc.playOrder
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, order.count, nil
        ) else { throw Failure.destination }

        // 0 means loop forever; 1 plays once and holds the last frame.
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: doc.mode == .once ? 1 : 0
            ]
        ] as CFDictionary)

        let size = pixelSize
        let times = delays
        // Rendering is the expensive half of an export, and a bounce asks for
        // every interior frame twice. Held by frame index, so the second ask is
        // free.
        var rendered: [Int: CGImage] = [:]

        for (step, index) in order.enumerated() {
            let image: CGImage
            if let done = rendered[index] {
                image = done
            } else {
                guard var made = Render.raster(doc.frames[index], doc: doc, pixelSize: size,
                                               background: transparent ? nil : doc.background)
                else { throw Failure.frame(index) }

                if transparent, let hardened = Self.hardenAlpha(made, threshold: alphaThreshold) {
                    made = hardened
                }
                rendered[index] = made
                image = made
            }

            let seconds = Double(times[step]) / 100.0
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: seconds,
                    kCGImagePropertyGIFUnclampedDelayTime: seconds,
                ]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { throw Failure.finalize }
    }

    /// Collapses partial coverage to all-or-nothing, which is all GIF can carry.
    ///
    /// Kept pixels are un-premultiplied. Without that, a half-covered edge pixel
    /// arrives already darkened toward the transparent black it was composited
    /// against, and promoting it to fully opaque bakes that darkening in — the
    /// grubby outline you see around badly made transparent GIFs.
    static func hardenAlpha(_ image: CGImage, threshold: Double) -> CGImage? {
        let w = image.width, h = image.height
        let bytes = w * h * 4
        guard w > 0, h > 0,
              let raw = calloc(bytes, 1)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        defer { free(raw) }
        guard let ctx = CGContext(data: raw, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let cutoff = UInt8(max(1, min(255, Int((threshold * 255).rounded()))))
        var i = 0
        while i < bytes {
            let alpha = raw[i + 3]
            if alpha < cutoff {
                raw[i] = 0; raw[i + 1] = 0; raw[i + 2] = 0; raw[i + 3] = 0
            } else if alpha < 255 {
                let f = 255.0 / Double(alpha)
                raw[i]     = UInt8(min(255.0, (Double(raw[i]) * f).rounded()))
                raw[i + 1] = UInt8(min(255.0, (Double(raw[i + 1]) * f).rounded()))
                raw[i + 2] = UInt8(min(255.0, (Double(raw[i + 2]) * f).rounded()))
                raw[i + 3] = 255
            }
            i += 4
        }
        return ctx.makeImage()
    }
}
