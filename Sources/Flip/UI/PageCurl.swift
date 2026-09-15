import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// One plate curling away to reveal the next, the way a book turns a leaf.
///
/// Core Image's own page curl rather than a shader of our own. That filter is
/// the real thing — the page bends around a cylinder as a developable surface,
/// so it never stretches; the back of the leaf comes over as you look at it;
/// and a shadow travels with the fold and falls on the page underneath. Writing
/// that in Metal would be a day's work to arrive back here, and this machine has
/// no Metal compiler installed to do it with.
///
/// It works on images rather than on the live view, which costs nothing here:
/// the plates *are* images — six PNGs at 740×880 — so there is no view to
/// rasterise on the way in.
struct PageCurlPlate: View {
    /// The leaf coming off. Nil when nothing is turning, which is the ordinary
    /// state and draws the target straight through with no filter at all.
    let from: String?
    let to: String
    var progress: Double

    /// Interpolated by SwiftUI, so `withAnimation` on `progress` drives the
    /// curl and the easing curve comes for free. Without this the view would
    /// only ever see the start and end values.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Group {
            if let composed {
                Image(nsImage: composed)
                    .resizable()
                    .scaledToFill()
            } else if let plain = PlateArt.image(resting) {
                Image(nsImage: plain)
                    .resizable()
                    .scaledToFill()
            } else {
                FlipTheme.panelRaised
            }
        }
    }

    /// The curled frame, or nil when there is nothing to curl — at rest, and at
    /// either end of the turn, where the filter would only be reproducing one
    /// of its two inputs at the cost of a render.
    private var composed: NSImage? {
        guard let from, from != to, progress > 0.001, progress < 0.999 else { return nil }
        return PlateArt.curl(from: from, to: to, t: progress)
    }

    /// What to draw when the filter is not running.
    ///
    /// At rest that is the target. But on the frame the click lands, `to` is
    /// already the new plate while `progress` is still 0 — and drawing the
    /// target then showed the incoming graphic for a frame before the leaf had
    /// moved at all. The page coming off is what is on screen until it starts
    /// to lift.
    private var resting: String {
        guard let from, from != to, progress <= 0.001 else { return to }
        return from
    }
}

extension PageCurlPlate: Animatable {}

/// The plates, and the filter that turns one into the next.
enum PlateArt {
    /// Held for the session, the same bargain `Plate` makes: six plates at
    /// 740×880, and decoding one again on every turn is work for nothing.
    private static var decoded: [String: NSImage] = [:]
    private static var sources: [String: CIImage] = [:]
    private static var backs: [String: CIImage] = [:]

    /// The grid the plates are drawn on, and so the extent the curl is solved
    /// over. Taken from the artwork rather than from the view: the filter needs
    /// a fixed rectangle to bend, and the card it lands in is a different size
    /// on every window.
    static let grid = CGSize(width: 740, height: 880)

    /// One context for the app. `CIContext` carries compiled kernels and a
    /// command queue, and building one per frame would cost more than the curl.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(_ name: String) -> NSImage? {
        if let hit = decoded[name] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png",
                                          subdirectory: "Onboarding")
                     ?? Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        decoded[name] = image
        return image
    }

    private static func source(_ name: String) -> CIImage? {
        if let hit = sources[name] { return hit }
        guard let ns = image(name),
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        // Deliberately *not* clamped. Clamping gives the image an infinite
        // extent, and the filter solves its geometry over that rather than over
        // the page — the leaf then starts the transition already turned, so
        // t=0 shows the back of a page that has not moved yet. The plates are
        // opaque to their own edges, so there is nothing to clamp for.
        let ci = CIImage(cgImage: cg)
        sources[name] = ci
        return ci
    }

    /// What the back of the leaf shows: the plate's own ground, lightened.
    ///
    /// Not the front image over again — that would read as printing on both
    /// sides. And not the desaturated version it started as: draining a magenta
    /// plate to 12% saturation gave a grey leaf, which read as a sheet from some
    /// other book. A page's reverse is the same stock as its face, so this takes
    /// the colour the plate is printed on and lifts it toward the light.
    private static func back(_ name: String) -> CIImage? {
        if let hit = backs[name] { return hit }
        guard let ground = ground(name) else { return nil }
        // Toward white rather than up in brightness: brightness alone on a dark
        // ground goes muddy before it goes light, where a mix keeps the hue.
        let lift: CGFloat = 0.28
        let lighter = CIColor(red: ground.red + (1 - ground.red) * lift,
                              green: ground.green + (1 - ground.green) * lift,
                              blue: ground.blue + (1 - ground.blue) * lift)
        let sheet = CIImage(color: lighter)
            .cropped(to: CGRect(origin: .zero, size: grid))
        backs[name] = sheet
        return sheet
    }

    /// The colour a plate is printed on, read off its four corners.
    ///
    /// The corners rather than the whole image: every plate is a solid ground
    /// with a dark card and some line work laid over the middle of it, and an
    /// average across the lot comes back a muddy version of the card. Four
    /// patches so a squiggle crossing one of them is outvoted by the other three.
    private static func ground(_ name: String) -> CIColor? {
        guard let front = source(name) else { return nil }
        let patch: CGFloat = 64
        let corners = [
            CGRect(x: 0, y: 0, width: patch, height: patch),
            CGRect(x: grid.width - patch, y: 0, width: patch, height: patch),
            CGRect(x: 0, y: grid.height - patch, width: patch, height: patch),
            CGRect(x: grid.width - patch, y: grid.height - patch, width: patch, height: patch),
        ]
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, n: CGFloat = 0
        for corner in corners {
            guard let c = average(front, in: corner) else { continue }
            r += c.red; g += c.green; b += c.blue; n += 1
        }
        guard n > 0 else { return nil }
        return CIColor(red: r / n, green: g / n, blue: b / n)
    }

    private static func average(_ image: CIImage, in rect: CGRect) -> CIColor? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = rect
        guard let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return CIColor(red: CGFloat(px[0]) / 255,
                       green: CGFloat(px[1]) / 255,
                       blue: CGFloat(px[2]) / 255)
    }

    /// Renders one frame and throws it away, off the main thread.
    ///
    /// The first curl of a session is much slower than the rest: Core Image
    /// compiles the filter's kernels on first use and the plates have to be
    /// decoded. On the click that cost landed between the leaf lifting and the
    /// first curled frame appearing, which is the other half of why the new
    /// plate was visible for a moment. Done here, before the page is ever
    /// reached, the click has nothing left to pay for.
    static func warm() {
        guard !warmed else { return }
        warmed = true
        let pair = ("connect", "layers")
        DispatchQueue.global(qos: .utility).async {
            _ = curl(from: pair.0, to: pair.1, t: 0.5)
        }
    }

    private static var warmed = false

    /// One frame of the turn.
    static func curl(from: String, to: String, t: Double) -> NSImage? {
        guard let outgoing = source(from), let incoming = source(to),
              let backside = back(from) else { return nil }

        let extent = CGRect(origin: .zero, size: grid)
        let filter = CIFilter.pageCurlWithShadowTransition()
        filter.inputImage = outgoing
        filter.targetImage = incoming
        filter.backsideImage = backside
        filter.extent = extent
        filter.time = Float(t)
        // 225°, which is the top-right corner lifting and travelling in toward
        // the bottom-left. The filter's angle is the direction the fold sweeps,
        // and the four diagonals are the four corners: 45 is bottom-left, 135
        // bottom-right, 225 top-right, 315 top-left.
        filter.angle = 5 * .pi / 4
        // Against a 740pt page. At the filter's default of 100 the fold was a
        // fat tube more than a turning leaf.
        filter.radius = 72
        filter.shadowSize = 0.5
        filter.shadowAmount = 0.65
        // The shadow is solved over the page itself; given the zero rect the
        // filter draws none at all.
        filter.shadowExtent = extent

        guard let output = filter.outputImage?.cropped(to: extent),
              let cg = context.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: cg, size: grid)
    }
}
