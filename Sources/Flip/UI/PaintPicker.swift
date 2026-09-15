import SwiftUI
import AppKit

/// The colour picker, in place of the system colour panel.
///
/// Built from the three sub-views of the vendored `Colorful` — see
/// `Vendor/Colorful/VENDOR.md` — rather than from its own `Colorful` wrapper,
/// which stacks them flush and configures itself by mutating an
/// `@ObservedObject` from inside `body`. Standing them apart with gaps and
/// giving each its own rounding is the whole difference, and it needs the
/// pieces rather than the assembly.
struct PaintPicker: View {
    @Binding var color: RGBA
    var onChange: () -> Void = {}

    /// Hue, saturation and brightness are the picker's own state rather than
    /// derived from `color`, because two of the three are undefined at the ends
    /// of the range: every grey has the same hue, and black has the same
    /// saturation whatever hue you picked it under. Held here, dragging the
    /// brightness to zero and back leaves you where you started instead of at
    /// red.
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 0
    @State private var brightness: CGFloat = 0
    @State private var alpha: CGFloat = 1
    /// Raised while `color` is being read *into* the three, so the changes that
    /// causes do not turn round and write it back.
    @State private var syncing = false

    /// One gap between every part, so the card reads as evenly spaced rather
    /// than as a box with things after it.
    static let gap: CGFloat = 14
    static let boxHeight: CGFloat = 144
    /// The bars are thinner than the circles riding them, which is what makes
    /// the handle read as a handle rather than as a segment of the bar.
    static let track: CGFloat = 8
    /// The indicator, and so the height each bar's row actually takes. Mirrors
    /// `AlphaSliderModel.pointSize` in the vendored picker.
    static let thumb: CGFloat = 14
    /// What one costs in a card, so the card can be placed without measuring
    /// itself first — it has to be positioned before it is laid out.
    static var height: CGFloat {
        boxHeight + gap + thumb + gap + thumb + gap + FlipTheme.control
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            // Clipped. The indicator is drawn centred on its position, so at
            // any edge half of it falls outside — at the bottom that is 7pt
            // into the gap, which is most of the way to the hue bar.
            // 5, the radius every control in the app takes — the same one the
            // hex field below it and the swatches in the panel are drawn at.
            //
            // It was 8, which read as *rounder* than the card holding it. Nested
            // corners look concentric when the inner radius is the outer one
            // less the gap between them; here that is 10 − 12, so anything
            // positive is already too round and the job is to keep it small.
            // Squaring it off would satisfy the geometry and match nothing.
            Saturation(saturation: $saturation, brightness: $brightness,
                       hue: hue, cornerRadius: 5)
                .frame(height: Self.boxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            // Capsules: at 8pt tall a 4pt radius is a full round end, which is
            // what stops a thin bar reading as a cut-off strip.
            HueSlider(hue: $hue, cornerRadius: Self.track / 2, trackHeight: Self.track)

            AlphaSlider(alpha: $alpha, hue: hue,
                        saturation: saturation, brightness: brightness,
                        cornerRadius: Self.track / 2, trackHeight: Self.track)

            HStack(spacing: 8) {
                EyedropperButton { picked in
                    color = picked
                    onChange()
                }
                HexField(color: $color, onChange: onChange)
            }
        }
        .onAppear { pull(color) }
        .onChange(of: color) { _, now in pull(now) }
        .onChange(of: hue) { _, _ in push() }
        .onChange(of: saturation) { _, _ in push() }
        .onChange(of: brightness) { _, _ in push() }
        .onChange(of: alpha) { _, _ in push() }
    }

    private var composed: RGBA {
        RGBA(Color(hue: Double(hue), saturation: Double(saturation),
                   brightness: Double(brightness), opacity: Double(alpha)))
    }

    private func push() {
        guard !syncing, composed != color else { return }
        color = composed
        onChange()
    }

    /// Seeds the three from a colour set somewhere else — the hex field, a
    /// swatch, a selection change.
    ///
    /// Compared with a tolerance rather than exactly. The round trip through
    /// HSB and back is lossy in the last bit, and an exact test would find the
    /// colour "different" from the one the picker had just written, reseed from
    /// it, and set the whole thing oscillating.
    private func pull(_ c: RGBA) {
        guard !near(composed, c) else { return }
        syncing = true
        let swatch = c.color
        let s = swatch.saturation, b = swatch.brightness
        if s > 0.0001 { hue = swatch.hue }
        if b > 0.0001 { saturation = s }
        brightness = b
        alpha = c.a
        // After the four `onChange`s this pass will fire, not during them.
        DispatchQueue.main.async { syncing = false }
    }

    /// Within one 8-bit level on every channel, which is the finest difference
    /// the picker can show or the hex field can name.
    private func near(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.r - b.r) < 0.004 && abs(a.g - b.g) < 0.004
            && abs(a.b - b.b) < 0.004 && abs(a.a - b.a) < 0.004
    }
}

/// Picks a colour from anywhere on screen.
///
/// `NSColorSampler` is the system's own loupe — the same one the stock colour
/// panel offers — and it is the one piece of that panel worth keeping. It needs
/// no permission and no window of its own.
struct EyedropperButton: View {
    let pick: (RGBA) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            NSColorSampler().show { sampled in
                guard let c = sampled?.usingColorSpace(.sRGB) else { return }
                pick(RGBA(Double(c.redComponent), Double(c.greenComponent),
                          Double(c.blueComponent), Double(c.alphaComponent)))
            }
        } label: {
            IconView(icon: .eyedropper, size: 15)
                .foregroundStyle(FlipTheme.textSecondary)
                .frame(width: FlipTheme.control, height: FlipTheme.control)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? FlipTheme.border : FlipTheme.panelRaised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
