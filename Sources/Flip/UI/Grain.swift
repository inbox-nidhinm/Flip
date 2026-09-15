import SwiftUI
import AppKit

// Grain.
//
// One sheet of photographic noise, tiled across every panel surface so the
// panels read as a material rather than as flat fills. It is the only bitmap
// the app loads at runtime; everything in `Icon` and `CursorArt` is vector data
// compiled in.
//
// It is drawn *source-over*, with no blend mode, and that is the whole point —
// which took a wrong turn to establish, so it is worth writing down.
//
// The artwork is an alpha-keyed speckle: no ground, just grains, 72% of them
// darker than mid-grey and 28% lighter. A blend mode was the obvious move and
// is the wrong one, because every surface here is dark. Overlay computes
// `2 × backdrop × source` for any backdrop under 50% grey, so over #2C2C2C a
// grain of pure white reaches 88 — it cannot lift a pixel past twice the
// panel's own value however light the grain is. The light 28% is crushed into
// invisibility and what survives is one-sided dark speckle. Measured over
// #2C2C2C, overlay leaves 3% of pixels lighter than the panel and 80% darker;
// the artwork's own balance is 28/72, and source-over reproduces it at 38/23.
// Multiply is worse still — it cannot lighten at all. Screen and plusLighter
// fail the other way, dropping the dark 72%.
//
// So there is nothing to fix with a blend mode. The artwork already encodes
// both polarities in its own alpha, and the honest thing is to draw it.
//
// (Overlay *is* right for this artwork over a light ground, which is where it
// was authored and why it was asked for. Over #ECDBBE it keeps the grain and
// holds the ground within half a level, where source-over would let the dark
// grains punch 16 levels down. The mode belongs to the ground, not to the file.)
enum Grain {
    /// One image pixel to one device pixel — the tile drawn at half its pixel
    /// size in points, so 454×264px covers 227×132pt.
    ///
    /// This is a separate control from strength and neither substitutes for the
    /// other: strength sets how much tone the grain carries, scale sets how big
    /// each grain is. Drawn a point per pixel the grain is twice this size in
    /// each direction and reads as coarse for a 232pt panel; halving it lands
    /// the grain at the display's own resolution, which is as fine as it can go
    /// before a grain stops being a grain and starts being a dither.
    private static let assetScale: CGFloat = 2

    /// Loaded once. Nil when the app runs outside its bundle — `swift run`
    /// rather than the built `.app` — in which case the panels simply come up
    /// ungrained rather than the app failing to start.
    static let image: NSImage? = {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "grain", withExtension: "png", subdirectory: "Textures")
                     ?? bundle.url(forResource: "grain", withExtension: "png"),
              let image = NSImage(contentsOf: url),
              let pixels = image.representations.first else { return nil }
        image.size = NSSize(width: CGFloat(pixels.pixelsWide) / assetScale,
                            height: CGFloat(pixels.pixelsHigh) / assetScale)
        return image
    }()

    /// The same sheet as a pattern colour, for the one surface that is not a
    /// SwiftUI view: the editor's canvas is an `NSView` drawing itself with
    /// Core Graphics, and there is no `Canvas` there to tile by hand.
    ///
    /// `NSColor(patternImage:)` tiles at the image's *point* size, which is
    /// already halved above, so the pattern lands at the same grain size as the
    /// panels'. Its phase comes from the view, so the grain sits on the glass —
    /// panning and zooming the artboard move under it rather than dragging it
    /// along.
    static let pattern: NSColor? = image.map(NSColor.init(patternImage:))
}

extension View {
    /// Presses the grain into a surface. Applied to the *fill* of a panel, not
    /// to the panel itself, so the grain sits under the panel's content — text
    /// and glyphs are read off it rather than through it.
    ///
    /// No `compositingGroup` here, deliberately. It is mandatory for a real
    /// blend mode — without it the blend reaches past the fill and picks up the
    /// canvas and any panel underneath — but source-over onto an opaque fill
    /// gives the same result grouped or not, and the group costs an offscreen
    /// pass on every panel that redraws. Put it back if the mode ever changes.
    func grained(_ strength: Double = FlipTheme.grain) -> some View {
        overlay(GrainOverlay(strength: strength))
    }

    /// The same sheet over a *light* surface, which is the case the note at the
    /// top of this file sets aside: overlay is wrong for the app's greys and
    /// right here. Over #FAF7F2 it keeps both polarities of the artwork and
    /// holds the ground where it is, where source-over would let the dark 72%
    /// punch sixteen levels down and grey the drawing out.
    ///
    /// `compositingGroup` is mandatory this time, and that is the cost of the
    /// blend mode: without it the blend reaches past the surface and picks up
    /// whatever is behind it.
    func grainedOnLight(_ strength: Double = FlipTheme.grain) -> some View {
        overlay(GrainOverlay(strength: strength).blendMode(.overlay))
            .compositingGroup()
    }
}

private struct GrainOverlay: View {
    let strength: Double

    var body: some View {
        if let image = Grain.image {
            // Tiled by hand rather than with `resizingMode: .tile`, which draws
            // nothing at all for an `NSImage` whose point size has been set away
            // from its pixel size. A `Canvas` also pins the tile origin to the
            // surface's top-left, so the grain does not crawl when a panel
            // changes height.
            //
            // Tiled, never fitted. A panel is 232pt wide and as tall as the
            // window; fitting a 454×264 tile to that would stretch fine noise
            // into vertical streaks. The seams do not show, because there is no
            // structure in the noise for a seam to interrupt.
            Canvas { context, size in
                let tile = context.resolve(Image(nsImage: image))
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        context.draw(tile, in: CGRect(origin: CGPoint(x: x, y: y),
                                                      size: tile.size))
                        x += tile.size.width
                    }
                    y += tile.size.height
                }
            }
            .opacity(strength)
            .allowsHitTesting(false)
        }
    }
}
