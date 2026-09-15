import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Writes one frame as a PNG.
///
/// The still to the GIF's animation, and a far better fit for this artwork:
/// PNG carries eight bits of alpha, so an antialiased edge arrives as an
/// antialiased edge. Neither of the two things `GIFExport` has to do to make a
/// transparent frame passable — thresholding coverage to one bit, then
/// un-premultiplying what survives so it does not fringe — applies here. There
/// is nothing to set and nothing to get wrong.
///
/// Full size, and no scale control in the panel. A GIF is thirty frames and
/// gets very large very quickly, which is why that one is turned down; a still
/// is one image, and an export you have to remember to set back to 100% is a
/// trap rather than an option.
struct PNGExport {
    let doc: Document
    /// The one frame being written — the one you are on, not the document.
    let frame: Frame
    /// Transparent background instead of the artboard's paper colour.
    var transparent: Bool
    var scale: CGFloat = 1

    enum Failure: LocalizedError {
        case render
        case destination
        case finalize

        var errorDescription: String? {
            switch self {
            case .render:      return "The frame could not be rendered."
            case .destination: return "Could not start writing the PNG."
            case .finalize:    return "The PNG could not be completed."
            }
        }
    }

    var pixelSize: CGSize {
        CGSize(width: max(1, (doc.size.width * scale).rounded()),
               height: max(1, (doc.size.height * scale).rounded()))
    }

    func write(to url: URL) throws {
        guard let image = Render.raster(frame, doc: doc, pixelSize: pixelSize,
                                        background: transparent ? nil : doc.background)
        else { throw Failure.render }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw Failure.destination }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.finalize }
    }
}
