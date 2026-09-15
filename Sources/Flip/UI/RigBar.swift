import SwiftUI

/// The armature's own bar, above the frame strip and only while the bone tool is
/// in hand.
///
/// It was a popup hanging off a chevron first. A rig has two modes and five
/// operations, all of which you reach repeatedly while posing — and a popup that
/// has to be reopened between every one of them is a popup in the way. A
/// contextual bar costs the same room only when the tool is out, and every
/// control in it is one click from wherever the pointer already is.
struct RigBar: View {
    @EnvironmentObject private var model: AppModel

    /// One measure for the whole surface. Shorter than the frame strip's 40 on
    /// purpose: this bar is subordinate to that one, and being the same height
    /// would read as a second bar of equal standing rather than as this tool's
    /// own.
    private let h: CGFloat = 30
    private let pad: CGFloat = 5
    private let gap: CGFloat = 2

    var body: some View {
        HStack(spacing: FlipTheme.floatGap) {
            // What a drag does. A mode, so it sits on its own ground.
            tray {
                BarButton(glyph: .icon(.bone), isOn: model.boneMode == .place,
                          size: h, iconBox: FlipTheme.icon) { model.boneMode = .place }
                    .help("Place bones. Drag on empty space to start an armature, or from a tip to chain a child onto it. A bone claims the layers it is drawn inside; click a layer to add or remove it by hand.")
                BarButton(glyph: .icon(.reposition), isOn: model.boneMode == .pose,
                          disabled: !model.hasRig, size: h, iconBox: FlipTheme.icon) { model.boneMode = .pose }
                    .help("Pose bones. Drag a round tip to move a bone, or a square root handle to move a whole chain.")
            }

            // How a drag reaches. Also a mode, and also on its own ground —
            // letters rather than glyphs, because two arrows side by side would
            // be a guess where IK and FK are what riggers already call these.
            tray {
                LetterButton(text: "IK", isOn: model.poseWithIK, size: h) { model.poseWithIK = true }
                    .help("Dragging a tip lets three bones up the chain rearrange themselves to reach it. Quicker to pose, less controllable.")
                LetterButton(text: "FK", isOn: !model.poseWithIK, size: h) { model.poseWithIK = false }
                    .help("Dragging a tip turns only that bone and swings its children along. Hold Option to stretch its length as well.")
            }

            divider

            // Operations. Plain buttons, no ground: these do something and end,
            // where everything left of the rule puts you in a state.
            BarButton(glyph: .icon(.undo), disabled: !model.canUndo, size: h,
                      iconBox: FlipTheme.icon) { model.undo() }
                .help("Undo (⌘Z)")
            BarButton(glyph: .icon(.recentre), disabled: !model.rigIsPosed, size: h,
                      iconBox: FlipTheme.icon) { model.resetRigPose() }
                .help("Return every bone to the pose it was built in. The drawing follows, because posing never wrote to it.")
            BarButton(glyph: .icon(.closePath), isOn: model.hasRigGhost,
                      disabled: !model.hasRig, size: h, iconBox: FlipTheme.icon) { model.toggleRigGhost() }
                .help("Leave this pose behind as an outline and keep posing, so the change between the two can be read. Onion skin does this across frames; this does it within one.")
            BarButton(glyph: .icon(model.showRig ? .eye : .eyeSlash), isOn: !model.showRig,
                      disabled: !model.hasRig, size: h, iconBox: FlipTheme.icon) { model.showRig.toggle() }
                .help("Take the bones off the screen to see the pose as a drawing.")
            BarButton(glyph: .icon(.trash), disabled: !model.hasRig, size: h,
                      iconBox: FlipTheme.icon) { model.deleteRig() }
                .help("Remove the armature and release every layer it held. The artwork is left exactly as its rest pose.")
        }
        .padding(pad)
        .floatingPanel()
        .dismissesTransients(model)
    }

    private func tray<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: gap) { content() }
            .padding(FlipTheme.trayPadding)
            // Concentric with the bar: an inner corner is the outer radius less
            // the gap between them, or the two curves splay apart.
            .background(RoundedRectangle(cornerRadius: FlipTheme.corner - pad)
                .fill(FlipTheme.panelRaised))
    }

    /// Full height of the bar's inside, like the frame strip's rule.
    private var divider: some View {
        Rectangle()
            .fill(FlipTheme.border)
            .frame(width: 1, height: h + pad * 2)
            .padding(.vertical, -pad)
            .padding(.horizontal, pad - gap)
    }
}

/// A two-letter button, for the pair whose names are shorter than any glyph for
/// them would be clear.
private struct LetterButton: View {
    let text: String
    let isOn: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? .white : FlipTheme.textSecondary)
                .frame(width: size + 4, height: size)
                .background(RoundedRectangle(cornerRadius: max(5, size * 0.2))
                    .fill(isOn ? FlipTheme.accent : (hovering ? FlipTheme.panelHover : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
