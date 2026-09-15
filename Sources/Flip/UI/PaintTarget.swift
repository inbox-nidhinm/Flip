import SwiftUI

/// What the colour card is pointed at.
///
/// Carries the swatch's colour rather than its index because the palette is two
/// lists joined on the fly and an index into the join means nothing to the
/// model. Two identical swatches would be indistinguishable here, which costs a
/// file that holds the same colour twice the ability to edit the second one —
/// a trade for not threading positions through three views.
enum PaintTarget: Equatable {
    case fill
    case stroke
    /// The artboard's own colour.
    case background
    /// One of the file's own swatches, identified by the colour it holds now.
    case swatch(RGBA)
    /// The plus tile: a colour that is not in the palette yet.
    case newSwatch
}

/// Where the control that opened the card is, so the card can be put beside it.
struct PaintAnchorKey: PreferenceKey {
    static let defaultValue: SwiftUI.Anchor<CGRect>? = nil
    static func reduce(value: inout SwiftUI.Anchor<CGRect>?, nextValue: () -> SwiftUI.Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Publishes this control's frame, but only while it is the one being
    /// picked from — every control in the panel carries this, and the key holds
    /// one anchor.
    func paintAnchor(_ target: PaintTarget, _ model: AppModel) -> some View {
        anchorPreference(key: PaintAnchorKey.self, value: .bounds) {
            model.picking == target ? $0 : nil
        }
    }
}

/// The card itself: the picker, in the same chrome every floating panel wears.
struct PaintCard: View {
    /// The app's inset: what the tools panel pads its contents by, what the
    /// panel headers and the layer rows are indented by. Matching it means a
    /// hex field in this card and a hex field in the panel beside it sit the
    /// same distance from their own edge. (`ShortcutsCard` uses 14, which is
    /// the one place in the app that does.)
    static let padding: CGFloat = 12
    static let width: CGFloat = 240
    /// Known without laying it out, because it has to be positioned first.
    static var height: CGFloat { PaintPicker.height + padding * 2 }

    @Binding var color: RGBA

    var body: some View {
        PaintPicker(color: $color)
            .padding(Self.padding)
            .frame(width: Self.width)
            .floatingPanel()
    }
}
