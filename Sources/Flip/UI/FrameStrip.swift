import SwiftUI

/// Frames, floating over the canvas.
///
/// Two ways to add one, both visible. **Duplicate** carries the drawing forward,
/// since per-frame layer stacks mean nothing carries over by itself. **Blank** is
/// the classic flipbook move: an empty frame with the previous drawing showing
/// through as an onion skin.
struct FrameStrip: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovered: UUID?

    /// Which member of each pair the group button is currently offering. Kept in
    /// step with the keyboard, so pressing `P` leaves the draw button showing the
    /// pen rather than still showing the brush.
    @State private var pointerTool: Tool = .select
    @State private var drawTool: Tool = .brush
    @State private var shapeTool: Tool = .rect

    /// Whether the filmstrip is up against each end of its travel. Both true when
    /// the frames fit without scrolling, which is also when neither edge fades.
    @State private var edges = ScrollEdges()

    private struct ScrollEdges: Equatable {
        var atStart = true
        var atEnd = true
    }

    /// The bar's own inset. The tray's corner radius is derived from it, so the
    /// two curves stay concentric.
    private let barPadding: CGFloat = 6

    /// Between one button and the next. Tighter than the bar's own inset, because
    /// each button already carries its own space around its glyph.
    private let barSpacing: CGFloat = 4

    /// How much the current frame's tile stands proud of the others.
    private let selectedScale: CGFloat = 1.1

    /// What that scale adds on each edge. The tile row has to carry this much
    /// slack or the `ScrollView` around it clips the growth away — its bounds are
    /// otherwise exactly the tiles, and a scaled tile is simply cut back to size.
    private var tileBleed: CGFloat { rowHeight * (selectedScale - 1) / 2 }

    /// The tile height — and with it the bar's inner height, which is what every
    /// button in the bar is sized to and how tall a full-bleed divider has to be.
    private let rowHeight: CGFloat = 40

    var body: some View {
        // An overlay on the bar rather than a row above it in a stack: the stack
        // was as wide as the space the strip was given, not as wide as the bar,
        // so a leading-aligned card landed off at the edge of the canvas instead
        // of over the tools it belongs to. An overlay is measured against the bar
        // itself, and being applied after `floatingPanel` it escapes its clip.
        bar
            .overlay(alignment: .bottom) { raised }
            .padding(.bottom, FlipTheme.floatInset)
        .animation(.easeOut(duration: 0.18), value: model.tool)
        .onChange(of: model.tool) { _, t in
            if t == .brush || t == .bezier { drawTool = t }
            if t == .rect  || t == .ellipse { shapeTool = t }
            if t == .select || t == .hand   { pointerTool = t }
        }
    }

    /// Sits 12pt clear of the bar's top edge, at the end of the bar the buttons
    /// that raise it live on.
    @ViewBuilder private var raised: some View {
        if model.stripPopup != nil || model.tool == .bone {
            VStack(spacing: 8) {
                if let p = model.stripPopup {
                    card(p)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Centred on the strip rather than pinned to the end that raised
                // it: it belongs to the tool, not to one button, and a chevron is
                // not what brought it up.
                if model.tool == .bone {
                    RigBar()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.offset(y: 8).combined(with: .opacity))
                }
                // Stands in for the bar, whose own height is the tile plus its
                // padding. Measuring the gap off the bottom edge like this is
                // exact; an alignment guide off the top edge quietly did nothing.
                Color.clear.frame(height: rowHeight + 12)
            }
        }
    }

    // MARK: The bar

    /// One bar, two sets of contents.
    ///
    /// Not two bars swapped: the strip is the same object either way, and
    /// letting it keep its identity is what lets the width close in around the
    /// smaller set and the icons trade places rather than one panel replacing
    /// another.
    private var bar: some View {
        HStack(spacing: barSpacing) {
            if model.repositioning {
                repositionContent.transition(swap)
            } else {
                frameContent.transition(swap)
            }
        }
        .padding(barPadding)
        .floatingPanel()
        // One place, rather than every caller: `beginReposition` is reached from
        // the panel, the bar and two keys, and wrapping each of them in
        // `withAnimation` would be four chances to forget.
        .animation(.easeInOut(duration: 0.22), value: model.repositioning)
    }

    /// Both halves travel the same way — down on the way in, up on the way out —
    /// so the swap reads as one movement rather than two things crossing.
    ///
    /// The offsets are read at the moment the state changes, so they are already
    /// the *new* direction for both the arriving set and the leaving one.
    private var swap: AnyTransition {
        let d: CGFloat = model.repositioning ? 14 : -14
        return .asymmetric(insertion: .offset(y: -d).combined(with: .opacity),
                           removal: .offset(y: d).combined(with: .opacity))
    }

    /// What the bar carries while the reference is being placed. No label and no
    /// help text: the mode has cleared the screen and the two buttons are the
    /// whole vocabulary, so a sentence explaining them would be the largest
    /// thing in a bar that is meant to have shrunk.
    @ViewBuilder private var repositionContent: some View {
        // Along for the ride, and dead until this is finished — it is where the
        // reference's own controls live, and leaving it lit would offer a way
        // back into settings that are mid-change.
        BarButton(glyph: .icon(.artboard), disabled: true, size: rowHeight) { }

        divider

        BarButton(glyph: .icon(.close), size: rowHeight) { model.endReposition(keep: false) }
        BarButton(glyph: .icon(.check), size: rowHeight) { model.endReposition(keep: true) }
    }

    @ViewBuilder private var frameContent: some View {
            BarButton(glyph: .icon(model.isPlaying ? .pause : .play),
                      isOn: model.isPlaying, disabled: model.doc.frames.count < 2,
                      size: rowHeight) { model.togglePlay() }

            ScrollView(.horizontal, showsIndicators: false) {
                // A plain HStack, deliberately. LazyHStack fills the height it is
                // offered rather than sizing to its content, which stretched the
                // strip's background over the whole canvas and hid the artboard.
                // Thirty cached thumbnails cost ~1 ms to lay out, so laziness here
                // was buying nothing anyway.
                HStack(spacing: 5) {
                    ForEach(Array(model.doc.frames.enumerated()), id: \.element.id) { index, frame in
                        tile(frame, index: index)
                    }
                }
                .padding(.horizontal, tileBleed + 1)
                .padding(.vertical, tileBleed)
            }
            // Taller than the row by the bleed, then pulled back to the row's own
            // height so the bar does not grow: the scroll view gets the space to
            // draw a scaled tile, the layout never hears about it.
            .frame(width: framesWidth, height: rowHeight + tileBleed * 2)
            // A hard edge mid-thumbnail reads as a rendering fault rather than as
            // "there is more this way". The fade says the row continues, and
            // retracts at each end so it never suggests travel that is not there.
            .mask(fade)
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                let x = geometry.contentOffset.x
                let travel = geometry.contentSize.width - geometry.containerSize.width
                // A whole point of slack: scroll offsets land on fractions, and
                // an exact comparison leaves the fade flickering at the stops.
                return ScrollEdges(atStart: x <= 1, atEnd: x >= travel - 1)
            } action: { _, now in
                edges = now
            }
            .padding(.vertical, -tileBleed)

            // Two buttons rather than one plus a modifier. A blank frame is how you
            // draw the *next* drawing over the onion skin, and hiding that behind
            // ⌥ made the obvious move the wrong one: duplicating a frame leaves
            // the ghost exactly underneath its own copy, where it cannot be seen.
            BarButton(glyph: .icon(.duplicateFrame), size: rowHeight) {
                model.addFrame(duplicate: true)
            }
            BarButton(glyph: .icon(.blankFrame), size: rowHeight) {
                model.addFrame(duplicate: false)
            }
            BarButton(glyph: .icon(.trash), disabled: model.doc.frames.count < 2,
                      size: rowHeight) { model.deleteFrame() }

            // Onion skin and the artboard used to sit here. Both describe the
            // paper rather than the drawing in hand, so they are groups in the
            // tools panel now, under the two tools that make no marks — which
            // leaves this bar the frames and the tools, and nothing else.

            // The only rule left in the bar. Everything to its left acts on the
            // frames; everything to its right is a mode you are in.
        divider

        tools
    }

    /// Opaque in the middle, ramping to clear at whichever end can still scroll.
    /// A zero-width ramp is simply no fade, so both ends share one description.
    private var fade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: edges.atStart ? 0 : fadeWidth)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: edges.atEnd ? 0 : fadeWidth)
        }
        .animation(.easeOut(duration: 0.15), value: edges)
    }

    private let fadeWidth: CGFloat = 16

    /// Wide enough for the tiles and no wider, up to a ceiling. A `ScrollView`
    /// takes every point it is offered, so on a one-frame document `maxWidth`
    /// left a hand's width of empty bar between the tile and the next group.
    private var framesWidth: CGFloat {
        let aspect = model.doc.size.width / max(model.doc.size.height, 1)
        let tile = max(24, rowHeight * aspect)
        let n = CGFloat(model.doc.frames.count)
        return min(n * tile + max(n - 1, 0) * 5 + (tileBleed + 1) * 2, 420)
    }

    /// Runs the full height of the bar rather than sitting as a stub in the
    /// middle of it: an explicit height plus negative padding, because a flexible
    /// one would only ever be as tall as the row it is laid out in.
    ///
    /// Horizontally it makes up the difference between the bar's spacing and its
    /// inset. The tools tray is bounded by the bar's edge on three sides and by
    /// this rule on the fourth, so the rule has to stand off by the same amount
    /// the edge does or the tray reads as though it were shunted left.
    private var divider: some View {
        Rectangle()
            .fill(FlipTheme.border)
            .frame(width: 1, height: rowHeight + barPadding * 2)
            .padding(.vertical, -barPadding)
            .padding(.horizontal, barPadding - barSpacing)
    }

    // MARK: Tools

    /// The three tools, on a lighter ground of their own, filling the bar's full
    /// height. They are the only thing here that is a *mode* rather than an
    /// action, and being both larger and on their own ground says so without a
    /// label.
    private var tools: some View {
        HStack(spacing: FlipTheme.trayPadding) {
            groupButton(.pointer, showing: pointerTool)
            groupButton(.draw, showing: drawTool)
            groupButton(.shape, showing: shapeTool)
            BarButton(glyph: .icon(.bone), isOn: model.tool == .bone,
                      size: toolSize, iconBox: toolIcon,
                      hoverFill: FlipTheme.panelHover) { pick(.bone) }
                .help("Bone. Poses what is already drawn instead of making marks — its own bar appears above this one. (A)")
        }
        .padding(FlipTheme.trayPadding)
        // Concentric with the bar: an inner corner has to be the outer radius
        // less the gap between them, or the two curves splay apart. At the bar's
        // own radius it looked far too round for something inset 6pt inside it.
        .background(RoundedRectangle(cornerRadius: FlipTheme.corner - barPadding)
            .fill(FlipTheme.panelRaised))
    }

    /// Two tools, one slot. A press takes the one on show; the chevron beside it
    /// — or holding the button — raises the pair. The chevron is what says the
    /// slot has a second tool in it at all; the hold is the shortcut once you
    /// know. The letters still reach both directly.
    private func groupButton(_ group: StripPopup, showing tool: Tool) -> some View {
        HStack(spacing: 0) {
            HoldButton(glyph: tool.glyph, isOn: model.tool == tool, size: toolSize, iconBox: toolIcon,
                       hoverFill: FlipTheme.panelHover,
                       tap: { pick(tool) },
                       onHold: { raise(group) })
            ChevronButton(isOpen: model.stripPopup == group,
                          icon: chevronIcon, box: chevronBox,
                          height: toolSize) { raise(group) }
                // Outside the button, so it is plain tray rather than target or
                // highlight — see `chevronMargin`.
                .padding(.trailing, chevronMargin)
        }
    }

    /// The button is the bar's inner height less the tray's own padding, so the
    /// tools run from the top of the bar to the bottom of it. The glyph inside
    /// is the same size as every other glyph in the app — the big square button
    /// is what marks a tool out, not a bigger drawing.
    private var toolSize: CGFloat { FlipTheme.modeButton }
    private var toolIcon: CGFloat { FlipTheme.icon }

    /// The grid the chevron's glyph is drawn on.
    private var chevronIcon: CGFloat { 11 }

    /// How wide the chevron's *drawing* actually is.
    ///
    /// Its path spans the middle half of the 24-unit grid it is drawn on, and the
    /// stroke adds half its own width at each end. So this is a property of the
    /// artwork rather than a number to pick — and it is what the padding below
    /// has to be measured from, because the glyph box's own margin is invisible.
    /// What reads as padding is the gap between the chevron you can *see* and the
    /// edge of the highlight around it.
    private var chevronInk: CGFloat { chevronIcon * (0.5 + 1.5 / 24) }

    /// Clear space either side of that drawing, inside the highlight.
    private var chevronPad: CGFloat { 4 }

    /// The chevron's box, which is also its hover highlight. Centred on the
    /// glyph, so the two stay concentric however the padding changes.
    private var chevronBox: CGFloat { chevronInk + chevronPad * 2 }

    /// Plain tray to the right of the chevron, outside its box — margin, so it
    /// neither takes the click nor lights up on hover.
    ///
    /// Together with the padding it comes to the same 8pt the tool button carries
    /// around its own glyph, which does two things: the chevron's drawing ends up
    /// about as far from the tray's edge as the first tool's does from the other
    /// one, and the tray keeps the width it had before the padding grew. A
    /// chevron flush to the end left 4½pt against the first one's 11½pt, and the
    /// tray read lopsided.
    private var chevronMargin: CGFloat { max(0, (toolSize - toolIcon) / 2 - chevronPad) }

    private func pick(_ t: Tool) {
        model.tool = t
        if t != .bezier { model.selectedNodes = [] }
        model.stripPopup = nil
    }

    private func raise(_ p: StripPopup) {
        model.stripPopup = model.stripPopup == p ? nil : p
    }

    // MARK: What the bar raises

    @ViewBuilder private func card(_ p: StripPopup) -> some View {
        switch p {
        case .pointer: toolCard([.select, .hand])
        case .draw:  toolCard([.brush, .bezier])
        case .shape: toolCard([.rect, .ellipse])
        }
    }

    /// A named menu rather than a row of icons. Two glyphs side by side make you
    /// guess which is which; the tools each carry a name and the one you are on
    /// is ticked.
    private func toolCard(_ tools: [Tool]) -> some View {
        VStack(spacing: 4) {
            ForEach(tools, id: \.self) { t in
                ToolMenuRow(tool: t, checked: model.tool == t) { pick(t) }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 160)
        .floatingPanel()
    }

    private func tile(_ frame: Frame, index: Int) -> some View {
        let isCurrent = index == model.frameIndex
        let aspect = model.doc.size.width / model.doc.size.height

        return Button { model.stop(); model.go(to: index) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(model.doc.background.opaque)
                if let image = model.thumbnail(frame) {
                    Image(decorative: image, scale: 2, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: max(24, rowHeight * aspect), height: rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                // The current frame's ring carries most of the work of saying
                // where you are in the strip — the 1.1 scale is a tenth of a
                // 40pt tile and reads as almost nothing at a glance, so the
                // weight of the line is what actually marks it. `strokeBorder`
                // draws inward, so a heavier ring eats into the thumbnail
                // rather than growing the tile and shifting its neighbours.
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? FlipTheme.accent : FlipTheme.edge,
                                  lineWidth: isCurrent ? 2.5 : 1)
            )
            // Which frames a cross-frame selection actually reaches. Only drawn
            // when it reaches more than one, or every ordinary selection would put
            // a dot on the tile you are already looking at and mean nothing.
            .overlay(alignment: .topTrailing) {
                if model.selectionSpansFrames, model.selectionReaches(frame) {
                    Circle()
                        .fill(FlipTheme.accent)
                        .frame(width: 5, height: 5)
                        .padding(3)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(index + 1)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    // Accent on the current frame, the same green as its ring,
                    // so the tile is marked twice over — a badge that has to be
                    // read to be understood, and a colour that does not.
                    // Translucent black on the rest, which is a legibility patch
                    // rather than a state: the number has to hold up over
                    // whatever the artwork put underneath it.
                    .background(RoundedRectangle(cornerRadius: 2)
                        .fill(isCurrent ? FlipTheme.accent : .black.opacity(0.55)))
                    .padding(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A border alone was hard to pick out at a glance, so the current frame
        // stands slightly proud of the others.
        //
        // `scaleEffect` and not a larger frame: this is a drawing transform, so
        // the tile still occupies its original 40pt in the layout and neither the
        // bar's height nor the position of anything beside it moves. The extra
        // 2pt it gains on each side spills into the bar's 6pt padding and the 5pt
        // between tiles, so nothing is clipped either.
        .scaleEffect(isCurrent ? 1.1 : 1)
        // Later views in a stack draw over earlier ones, so without this the
        // tile after the current one would clip the corner it just grew.
        .zIndex(isCurrent ? 1 : 0)
        // Snap during playback. At twelve frames a second a 0.12s animation never
        // finishes, and the strip turns into a smear of half-scaled tiles.
        .animation(model.isPlaying ? nil : .easeOut(duration: 0.12), value: isCurrent)
        .onHover { hovered = $0 ? frame.id : (hovered == frame.id ? nil : hovered) }
    }
}

/// One line of a tool picker: tick, glyph, name.
private struct ToolMenuRow: View {
    let tool: Tool
    let checked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                    .opacity(checked ? 1 : 0)
                GlyphView(glyph: tool.glyph, box: FlipTheme.icon)
                    .frame(width: FlipTheme.icon)
                Text(tool.label)
                    .font(.system(size: 11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(FlipTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? FlipTheme.panelRaised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The chevron beside a two-tool slot.
///
/// A view of its own rather than a method on the bar, because it holds a hover
/// state and there are two of them — a method could not tell one from the other.
///
/// Its box is centred on the glyph, so the hover highlight is concentric with the
/// chevron, and it sits flush against the tool's own button. The chevron cannot
/// come closer to the *drawing* inside that button than the button's own 8pt of
/// padding allows; reaching into it was tried and put the chevron behind the
/// accent square, which is worse than the distance.
private struct ChevronButton: View {
    let isOpen: Bool
    let icon: CGFloat
    /// The box the glyph is centred in, and so the highlight. Wider than the
    /// glyph by the padding either side of the drawing inside it.
    let box: CGFloat
    let height: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(icon: .chevronDown, size: icon)
                .foregroundStyle(isOpen ? FlipTheme.textPrimary
                                 : hovering ? FlipTheme.textSecondary
                                 : FlipTheme.textTertiary)
                .frame(width: box, height: height)
                .background(RoundedRectangle(cornerRadius: max(5, box * 0.2))
                    .fill(hovering || isOpen ? FlipTheme.panelHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
