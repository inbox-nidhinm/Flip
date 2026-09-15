import SwiftUI
import AppKit

// MARK: - Theme

enum FlipTheme {
    static let canvas       = Color(red: 0.118, green: 0.118, blue: 0.118)
    static let panel        = Color(red: 0.173, green: 0.173, blue: 0.173)
    static let panelRaised  = Color(red: 0.220, green: 0.220, blue: 0.220)
    static let border       = Color(red: 0.259, green: 0.259, blue: 0.259)
    /// A hover for something that already sits **on** `panelRaised` — the tools
    /// tray, and so the chevrons beside the tools. Everything else in the app
    /// hovers by lifting `panelRaised` over `panel`, which has nothing left to
    /// lighten once the ground is already raised, so this is one step further up
    /// the same ramp: canvas, panel, panelRaised, this.
    static let panelHover   = Color(red: 0.282, green: 0.282, blue: 0.282)
    /// The row the sidebar is showing. Taken from the reference rather than
    /// mixed from `accent`: the accent over `panel` at any opacity comes out
    /// darker and bluer than this, because the accent's red channel is *below*
    /// the panel's and mixing can only pull it down.
    static let rowSelected   = Color(red: 0.231, green: 0.341, blue: 0.282)   // #3B5748
    /// The frame you are on. Quieter than `rowSelected` deliberately: which
    /// frame is up is already answered by the artboard in front of you and by
    /// the filmstrip, so a band as strong as the layer selection's competed with
    /// the one thing in the panel that has nothing else to say it.
    static let rowCurrent    = FlipTheme.accent.opacity(0.22)
    /// A row hover in a panel. This is `panelRaised` by another route: white at
    /// 5.7% over `panel` resolves to 0.220, the same value the solid token
    /// carries, so the ramp is unchanged. Translucent rather than solid because
    /// the panel underneath is grained, and an opaque row would stamp a flat
    /// patch into the texture as the pointer ran down the list.
    static let rowHover      = Color.white.opacity(0.057)
    /// A hairline over something whose colour the theme does not control — a
    /// swatch, a colour well, a frame thumbnail, the inside of a slider track.
    /// Translucent rather than the solid `border` so it lifts off a bright
    /// yellow and a near-black alike; over a panel it lands within a shade of
    /// `border`, so the two read as one edge everywhere they meet.
    static let edge         = Color.white.opacity(0.12)
    /// #1B8F51. Everything that means *selected* reads this: layer rows, the
    /// current frame's tile, the chosen swatch, a tool in hand, and the canvas's
    /// outlines, handles and marquee. One constant, so they cannot disagree.
    static let accent       = Color(red: 27/255, green: 143/255, blue: 81/255)
    /// The accent under the pointer. Lightened rather than darkened: the accent
    /// is already dark enough that a step down reads as disabled rather than as
    /// a button answering the pointer.
    static let accentHover  = Color(red: 34/255, green: 170/255, blue: 97/255)
    /// `edge` under the pointer. A swatch, a colour well and the toggle's track
    /// all show a colour, so a hover cannot touch the fill without lying about
    /// what that colour is — the hairline is the only part of them the theme
    /// owns, so it is the part that answers.
    static let edgeHover    = Color.white.opacity(0.32)

    /// How hard a panel takes its grain, as a fraction of the weight the
    /// artwork was drawn at. 1.0 is the sheet as authored — it is drawn
    /// source-over, so its own alpha is already the answer. Turn it down to
    /// soften. See `Grain`.
    static let grain: Double = 1.0

    static let textPrimary   = Color(white: 1.0)
    static let textSecondary = Color(white: 0.70)
    static let textTertiary  = Color(white: 0.50)

    static let panelWidth: CGFloat = 232
    static let rowHeight: CGFloat  = 24
    static let labelWidth: CGFloat = 58

    /// The panels float over the canvas rather than butting against the window,
    /// so they need a gutter, a corner and a gap to the rail beside them.
    static let floatInset: CGFloat = 8
    static let floatGap: CGFloat   = 8
    static let corner: CGFloat     = 10
    /// The big square button. The tools in the bar and the rail beside the tools
    /// panel are both mode switches rather than actions, so they are the same
    /// button — same size, same padding around them, same tray.
    static let modeButton: CGFloat = 36
    static let trayPadding: CGFloat = 2
    /// The rail is inset further than the tools tray it otherwise matches. The
    /// tray cannot be: at 4 it would stand taller than the bar's inner height and
    /// push the whole bar out. The rail is a card of its own with nothing to
    /// agree with, so it gets the room.
    /// Every pressable thing is this tall: the hex field set it, and a panel of
    /// controls that disagree about their height reads as several panels.
    static let control: CGFloat    = 24
    /// Labelled buttons carry a glyph *and* a word, and at `control` height they
    /// read as cramped in a way a bare field does not. One step up, derived so
    /// the two stay related.
    static let button: CGFloat     = control + 8
    /// The edge of the 24-unit grid an icon is drawn onto. One number, so the
    /// tools and the frame controls beside them carry the same weight.
    static let icon: CGFloat       = 20
}

extension Color {
    /// Bridge for the CoreGraphics side of the app, which never sees SwiftUI.
    var rgba: RGBA { RGBA(self) }
}

/// The typeface the home screen sets its titles in.
///
/// Registered with the process rather than declared in the Info.plist, because
/// `ATSApplicationFontsPath` wants a folder inside the bundle's Resources and
/// SwiftPM puts its own resources in a bundle of their own. Registration is
/// lazy and its result thrown away on purpose: `Font.custom` falls back to the
/// system face when the name is unknown, so a font that failed to load costs a
/// different-looking title rather than a crash.
enum FlipFont {
    /// The PostScript name, which is what `Font.custom` matches on — not the
    /// family, which for this face is "PP Kyoto" with the weight held apart.
    private static let face = "PPKyoto-Light"

    private static let registered: Bool = {
        guard let url = Bundle.module.url(forResource: face,
                                          withExtension: "otf", subdirectory: "Fonts")
                     ?? Bundle.module.url(forResource: face, withExtension: "otf")
        else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func title(_ size: CGFloat) -> Font {
        _ = registered
        return .custom(face, size: size)
    }

    /// What `lineSpacing` has to be for the face to sit on 130% leading.
    ///
    /// SwiftUI has no line-height control; `lineSpacing` is the gap *added*
    /// between lines, so the figure depends on how tall the face already sets
    /// itself — which for Kyoto is not 1em and is not the system font's either.
    /// Asked of the font rather than guessed, so a change of face does not
    /// quietly change the leading with it.
    static func leading(_ size: CGFloat) -> CGFloat {
        _ = registered
        guard let font = NSFont(name: face, size: size) else { return size * 0.3 }
        let natural = font.ascender - font.descender + font.leading
        return max(0, size * 1.3 - natural)
    }

    /// The same answer for the system face, at whatever multiple is asked for.
    ///
    /// Split out rather than folded into `leading(_:)` because that one is the
    /// title face at 130% and has callers; this is the body face and the
    /// multiple varies. Both exist for the same reason — `lineSpacing` is the
    /// gap *added* between lines, so the figure depends on how tall the face
    /// already sets itself, which is not 1em and differs between the two.
    static func bodyLeading(_ size: CGFloat, _ multiple: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        let natural = font.ascender - font.descender + font.leading
        return max(0, size * multiple - natural)
    }
}

extension View {
    /// The title face at 130% leading. One call, so no caller has to remember
    /// the second half.
    func flipTitle(_ size: CGFloat) -> some View {
        font(FlipFont.title(size)).lineSpacing(FlipFont.leading(size))
    }
}

// MARK: - Rows

/// Label above, then a chunky track the whole width of the panel with the value
/// alongside. The thumb is a wide white pill rather than a knob: at panel width
/// a 12pt circle is a small target for a fine adjustment, and the pill reads as
/// something to push. Nothing carries helper text: a label and a number are the
/// whole of what a slider has to say.
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// How the number reads. Always a whole number: a decimal place that is
    /// permanently `.0` is noise, and a 0–1 fraction reads better as a percentage
    /// than as `0.35`. The underlying value stays continuous — only the reading
    /// is rounded, so the handle still slides rather than stepping.
    var style: ValueStyle = .whole
    var unit: String = ""
    /// The first change of a drag. A slider that writes to the document on every
    /// step needs somewhere to push undo *once* — see `AppModel.beginSliderEdit`.
    var onBegin: (() -> Void)?
    var onCommit: (() -> Void)?

    enum ValueStyle { case whole, percent }

    private var readout: String {
        switch style {
        case .whole:   return "\(Int(value.rounded()))" + unit
        case .percent: return "\(Int((value * 100).rounded()))%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textSecondary)
                .lineLimit(1)

            PillTrack(value: $value, range: range, readout: readout,
                      onBegin: onBegin, onCommit: onCommit)
        }
        .padding(.vertical, 2)
    }
}

/// The track itself, split out so the value readout above does not re-lay it out
/// on every tick of a drag.
private struct PillTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Drawn inside the track's right-hand end rather than in a column beside
    /// it, which buys the track the whole width of the panel.
    let readout: String
    var onBegin: (() -> Void)?
    var onCommit: (() -> Void)?

    /// Where in the thumb the drag started, so grabbing it by an edge does not
    /// snap its centre to the pointer. Nil until the first change of a gesture;
    /// a press on the bare track seeds it with half the thumb, which centres the
    /// thumb under the pointer and makes a click on the track a jump-to.
    @State private var grab: CGFloat?
    @State private var hovering = false

    /// The grip: the little bar marking the right-hand end of the pill as the
    /// thing to take hold of.
    ///
    /// Shown only under the pointer or during a drag, and lighter than it used
    /// to be. Standing there permanently at 0.62 it read as a text caret parked
    /// beside the readout — worst at 100%, where the fill reaches the number and
    /// the two sit a couple of points apart on the same white. Nothing is lost
    /// by hiding it: the pill's end is the handle whether or not the grip is
    /// drawn on it, so this only ever had to say *grabbable*, which is a thing
    /// to say when the pointer is there to read it.
    private var grip: Color {
        hovering || grab != nil ? Color(white: 0.72) : .clear
    }

    /// The handle is narrow, because the covered area is drawn in the same white
    /// and the two read as one pill — the handle is just its right-hand end, and
    /// a wide one would make an empty slider look half full.
    private let thumbWidth: CGFloat = 16
    private let height: CGFloat = 26
    /// Room kept for the readout at the right-hand end.
    private let readoutWidth: CGFloat = 46
    /// The pill sits inside the track rather than flush with it, so the travel
    /// is the track less the handle and both gutters.
    private let inset: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - thumbWidth - inset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let t = min(max((value - range.lowerBound) / span, 0), 1)
            // Once the fill reaches the number it would be white on white, so the
            // number goes dark instead of moving or dimming out of the way.
            let fillRight: CGFloat = inset + thumbWidth + travel * CGFloat(t)
            let readoutLeft: CGFloat = geo.size.width - readoutWidth - 4
            let onFill = fillRight > readoutLeft

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(FlipTheme.canvas)
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(FlipTheme.edge, lineWidth: 1))

                // Covered area and handle in one shape. Drawing the fill as a
                // separate rectangle behind a white thumb would show a seam
                // between two whites; one pill that grows to the right cannot.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: thumbWidth + travel * t, height: height - 4)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(grip)
                            .frame(width: 2, height: 10)
                            .padding(.trailing, thumbWidth / 2 - 1)
                    }
                    .padding(.leading, inset)

                Text(readout)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(onFill ? Color(white: 0.32) : FlipTheme.textTertiary)
                    .lineLimit(1)
                    .frame(width: readoutWidth, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let thumbX = inset + travel * t
                        if grab == nil {
                            grab = (g.startLocation.x >= thumbX && g.startLocation.x <= thumbX + thumbWidth)
                                ? g.startLocation.x - thumbX
                                : thumbWidth / 2
                            // `grab` is nil until the first change of a gesture,
                            // so this is the one place that knows a drag has just
                            // started rather than continued.
                            onBegin?()
                        }
                        let x = min(max(g.location.x - (grab ?? 0) - inset, 0), travel)
                        value = range.lowerBound + (x / travel) * span
                    }
                    .onEnded { _ in
                        grab = nil
                        onCommit?()
                    }
            )
        }
        .frame(height: height)
    }
}

/// Integer value with − / + on either side. Used where a slider would be silly:
/// frame counts, onion range.
struct StepRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textSecondary)
                .frame(width: FlipTheme.labelWidth, alignment: .leading)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                stepButton(.minus) { value = max(range.lowerBound, value - 1) }
                Text("\(value)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(FlipTheme.textPrimary)
                    .frame(width: 28)
                stepButton(.plus) { value = min(range.upperBound, value + 1) }
            }
            .background(RoundedRectangle(cornerRadius: 5).fill(FlipTheme.panelRaised))
        }
        .frame(height: FlipTheme.rowHeight)
    }

    private func stepButton(_ icon: Icon, _ action: @escaping () -> Void) -> some View {
        StepButton(icon: icon, action: action)
    }
}

/// One end of a `StepRow`. Its own view because it holds a hover state and
/// there are two of them side by side — a method could not tell them apart.
private struct StepButton: View {
    let icon: Icon
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: 15)
                .foregroundStyle(hovering ? FlipTheme.textPrimary : FlipTheme.textSecondary)
                .frame(width: 22, height: FlipTheme.control)
                // The well behind the pair is already `panelRaised`, so this
                // lifts to the next rung rather than to the one underneath it.
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? FlipTheme.panelHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textSecondary)
            Spacer(minLength: 0)
            PillToggle(isOn: $isOn)
        }
        .frame(height: FlipTheme.rowHeight + 4)
    }
}

/// The switch, built out of the slider's parts.
///
/// `Toggle(.switch)` is AppKit's, and next to a panel full of dark tracks with
/// white pills in them it read as a control borrowed from somewhere else — its
/// own corner, its own fill, its own blue. This is the same track and the same
/// pill as `SliderRow`, moved to one end or the other: off it sits in the
/// canvas's own dark with the pill at the left, on it sits in the accent with
/// the pill at the right, which is the one place in the app where a state that
/// is *on* is not also a thing that is *chosen*.
struct PillToggle: View {
    @Binding var isOn: Bool

    @State private var hovering = false

    /// The slider's measurements, so the two line up down a column: its 26pt
    /// track, its 2pt gutter, its white pill inset by that.
    private let height: CGFloat = 26
    private let width: CGFloat = 46
    private let inset: CGFloat = 2

    var body: some View {
        let thumb = height - inset * 2
        Button {
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 7)
                    // On, the accent lightens; off, there is nothing in the
                    // track to lighten — it is the canvas's own dark — so the
                    // edge answers instead, the way the swatches do.
                    .fill(isOn ? (hovering ? FlipTheme.accentHover : FlipTheme.accent)
                          : FlipTheme.canvas)
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(hovering ? FlipTheme.edgeHover : FlipTheme.edge,
                                      lineWidth: 1))

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    // The slider's grip, and here it stays out: a slider's pill
                    // is obviously draggable from its position alone, where a
                    // switch sitting at one end could be a lamp rather than a
                    // handle.
                    .overlay(RoundedRectangle(cornerRadius: 1)
                        .fill(Color(white: 0.72))
                        .frame(width: 2, height: 10))
                    .padding(.horizontal, inset)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A row of mutually exclusive words, one of them lit.
///
/// The panel's own segmented control rather than `Picker(.segmented)`, which
/// brings its own chrome — its own corner radius, its own inset, its own idea
/// of what a selected segment looks like — none of which are the panel's. Lit
/// with `accent`, because that is what *chosen* reads as everywhere else here.
///
/// Unlabelled and full width. It is used under a section header that already
/// names it, and a label would take a third of a 208pt row to repeat the word
/// above it.
struct SegmentRow<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Segment(title: title(option),
                        isOn: option == selection) { selection = option }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(FlipTheme.panelRaised))
        .frame(height: FlipTheme.rowHeight + 4)
    }
}

private struct Segment: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Color.white : FlipTheme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Translucent on hover, not `panelRaised` — the strip it sits in
                // is already `panelRaised`, so an opaque hover would be invisible
                // and would flatten the grain under it besides.
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? FlipTheme.accent : hovering ? FlipTheme.rowHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A named choice that opens the app's own menu.
///
/// Shaped like `SliderRow` — name above, control filling the panel's width —
/// because it stands in the same column as one and a row that labelled itself
/// down the left would break the line the others keep.
///
/// The menu is `MenuLayer`'s, the same one a right-click puts up, opened at this
/// row instead of at the pointer. A `Picker` would have been the short way and
/// brings AppKit's pop-up button with it: system chrome, system corner, system
/// highlight, in a panel that draws all three itself.
struct MenuRow: View {
    let label: String
    /// What the control reads when shut — the choice in force, not the label.
    let value: String
    let entries: () -> [MenuEntry]

    @EnvironmentObject private var menus: MenuHost
    /// Where this row sits in the window, so the menu can open against it. Read
    /// from the layout rather than from the click: a menu that opened at the
    /// pointer would sit a little differently every time it was used.
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconView(icon: .chevronDown, size: 11)
                    .foregroundStyle(FlipTheme.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: FlipTheme.rowHeight + 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? FlipTheme.panelHover : FlipTheme.panelRaised))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                // Just under the row and flush with its left edge, so the menu
                // reads as having come out of the control rather than as having
                // landed near it.
                menus.show(entries(), at: CGPoint(x: frame.minX, y: frame.maxY + 4))
            }
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { frame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, new in frame = new }
            })
        }
        .padding(.vertical, 2)
    }
}

/// A number with its name inside the box. Two of these sit side by side where
/// two labelled rows took two lines each — and W and H need no more explaining
/// than the letter itself.
struct UnitField: View {
    let unit: String
    @Binding var value: CGFloat

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FlipTheme.textTertiary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textPrimary)
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, now in if !now { apply() } }
                .onAppear { text = format(value) }
                .onChange(of: value) { _, now in if !focused { text = format(now) } }
        }
        .padding(.horizontal, 8)
        .frame(height: FlipTheme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).fill(FlipTheme.panelRaised))
    }

    private func format(_ v: CGFloat) -> String { String(Int(v.rounded())) }

    private func apply() {
        if let d = Double(text.trimmingCharacters(in: .whitespaces)), d > 0 { value = CGFloat(d) }
        text = format(value)
    }
}

struct ReadoutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(FlipTheme.textTertiary)
        }
        .frame(height: 20)
    }
}

// MARK: - Paint controls

/// Name on one line, then the colour: a square well, its hex typed directly, and
/// an eye. The eye is *no paint at all* rather than a transparent colour, which
/// is what keeps an unclosed line a line.
struct PaintRow: View {
    let label: String
    @Binding var color: RGBA
    @Binding var enabled: Bool
    var target: PaintTarget
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FlipTheme.textSecondary)

            HStack(spacing: 8) {
                ColorWell(color: $color, target: target)
                HexField(color: $color, onChange: onChange)
                EyeToggle(isOn: $enabled, onChange: onChange)
            }
        }
    }
}

/// Square, and exactly as tall as the field it sits beside, so the two read as
/// one control rather than a field with something bolted after it.
struct EyeToggle: View {
    @Binding var isOn: Bool
    var onChange: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle(); onChange() } label: {
            IconView(icon: isOn ? .eye : .eyeSlash, size: 17)
                .foregroundStyle(isOn ? FlipTheme.textSecondary : FlipTheme.textTertiary)
                .frame(width: FlipTheme.control, height: FlipTheme.control)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? FlipTheme.border : FlipTheme.panelRaised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A plain square of colour that opens the picker. SwiftUI's own `ColorPicker`
/// draws a capsule that cannot be restyled, and a capsule reads as a button
/// rather than as the colour it is showing.
struct ColorWell: View {
    @EnvironmentObject private var model: AppModel
    @Binding var color: RGBA
    var target: PaintTarget

    @State private var hovering = false

    static let size: CGFloat = 48

    var body: some View {
        Button { model.beginPicking(target, from: color) } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.color)
                .frame(width: Self.size, height: Self.size)
                // The hairline answers, not the fill: this square's whole job is
                // to show a colour, and a hover that tinted it would be showing
                // the wrong one.
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(hovering ? FlipTheme.edgeHover : FlipTheme.edge, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .paintAnchor(target, model)
    }
}

/// Six hex digits, typed. Commits on return or on losing focus, and puts the
/// old value back if what was typed is not a colour.
struct HexField: View {
    @Binding var color: RGBA
    var onChange: () -> Void = {}

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(FlipTheme.textPrimary)
            .autocorrectionDisabled()
            .padding(.horizontal, 8)
            .frame(height: FlipTheme.control)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(FlipTheme.panelRaised))
            .focused($focused)
            .onSubmit(apply)
            .onChange(of: focused) { _, now in if !now { apply() } }
            .onAppear { text = color.hex6 }
            .onChange(of: color) { _, now in if !focused { text = now.hex6 } }
    }

    private func apply() {
        if let parsed = RGBA(hex: text, alpha: color.a), parsed != color {
            color = parsed
            onChange()
        }
        text = color.hex6
    }
}

/// Between one property and the next. Bleeds past the content inset so it runs
/// the full width of the panel, the way the section headers' rules do.
struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(FlipTheme.border)
            .frame(height: 1)
            .padding(.horizontal, -12)
            .padding(.vertical, 2)
    }
}

struct SwatchGrid: View {
    /// The nine that ship with the app.
    let colors: [RGBA]
    /// The document's own, shown after them, and the only ones that can be
    /// edited or dropped. A built-in stays as it is: they are the app's
    /// constants, and a file that could rewrite them could be left with no
    /// palette and no way back to one.
    var custom: [RGBA] = []
    var current: RGBA?
    let pick: (RGBA) -> Void
    /// Whether the plus tile is offered. The colour it produces goes to the
    /// model directly, so there is nothing to hand back through here.
    var add: Bool = false
    var edit: ((RGBA, RGBA) -> Void)?
    var remove: ((RGBA) -> Void)?

    var body: some View {
        // Square, and the same square as every other control. Nine of them will
        // not fit across a 232pt panel at that size, so the grid wraps rather
        // than squashing them into stripes.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: FlipTheme.control,
                                               maximum: FlipTheme.control),
                                     spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            // Keyed on position rather than on the colour. `id: \.self` was fine
            // for a fixed nine that are all different, but a file is free to add
            // a colour it already has, and two equal colours under `\.self`
            // collapse into a single tile.
            ForEach(Array((colors + custom).enumerated()), id: \.offset) { index, c in
                SwatchTile(color: c,
                           selected: current == c,
                           owned: index >= colors.count,
                           pick: { pick(c) },
                           editable: edit != nil,
                           remove: remove.map { r in { r(c) } })
            }
            if add { AddSwatchTile(initial: current ?? RGBA(1, 1, 1)) }
        }
    }
}

/// One colour in the grid.
///
/// A left click sets the fill and nothing else — it is the shortest path in the
/// panel and putting a popover in front of it would cost a dismissal every
/// time. Editing is on the right click instead, where it does not get in the
/// way of the thing you do a hundred times an hour.
private struct SwatchTile: View {
    let color: RGBA
    let selected: Bool
    /// Whether the document owns this one. Built-ins get no menu at all.
    let owned: Bool
    let pick: () -> Void
    let editable: Bool
    let remove: (() -> Void)?

    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        let tile = Button(action: pick) {
            RoundedRectangle(cornerRadius: 5)
                // Its own alpha, not `opaque`. A swatch can now be picked at
                // less than full opacity, and drawing it solid would hide that.
                .fill(color.color)
                .frame(width: FlipTheme.control, height: FlipTheme.control)
                // Like the colour well, the edge is the only part of this the
                // theme owns. The selected ring outranks a hover: which one is
                // in hand matters more than which one the pointer is over.
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(selected ? FlipTheme.accent
                                      : hovering ? FlipTheme.edgeHover : FlipTheme.edge,
                                      lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }

        // Branched rather than always attached: a menu with nothing in it does
        // not open at all, but the branch says so here rather than leaving it to
        // be discovered by right-clicking a built-in swatch.
        if owned {
            tile
                .flipContextMenu {
                    var entries: [MenuEntry] = []
                    if editable {
                        entries.append(.item("Edit Colour") {
                            model.beginPicking(.swatch(color), from: color)
                        })
                    }
                    if let remove {
                        if !entries.isEmpty { entries.append(.separator) }
                        entries.append(.item("Remove from Palette", remove))
                    }
                    return entries
                }
                .paintAnchor(.swatch(color), model)
        } else {
            tile
        }
    }
}

/// The tile that adds a colour to the file's palette. Drawn as a control rather
/// than as a colour — panel fill, a hairline, and a plus — because it is the one
/// square in the grid that is not itself a swatch.
private struct AddSwatchTile: View {
    /// Handed the colour once, when the popover shuts. A swatch is a thing you
    /// end up with rather than a thing you drag towards, so committing on every
    /// step of the pick would put a row of near-identical greens in the palette
    /// and an undo step behind each one.
    var initial: RGBA

    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        Button { model.beginPicking(.newSwatch, from: initial) } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? FlipTheme.border : FlipTheme.panelRaised)
                .frame(width: FlipTheme.control, height: FlipTheme.control)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(FlipTheme.edge, lineWidth: 1))
                .overlay(IconView(icon: .plus, size: 13)
                    .foregroundStyle(FlipTheme.textSecondary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .paintAnchor(.newSwatch, model)
    }
}

// MARK: - Buttons

/// The glyph every bar button is drawn from, shared so that the plain one and
/// the press-and-hold one cannot drift apart.
struct BarGlyph: View {
    let glyph: Glyph
    var isOn: Bool = false
    var hovering: Bool = false
    var disabled: Bool = false
    var accentWhenOn: Bool = true
    /// The tools are drawn larger than everything else in the bar, so the box
    /// and the glyph inside it are both adjustable. Square either way.
    var size: CGFloat = FlipTheme.control
    var iconBox: CGFloat = FlipTheme.icon
    /// What a hover lifts to. The default lifts `panelRaised` over the bar's
    /// `panel`, which is right everywhere except *on* a raised ground — the
    /// tools tray — where it has nothing left to lighten and the hover simply
    /// does not show. Those pass `panelHover`, the next rung of the same ramp.
    var hoverFill: Color = FlipTheme.panelRaised.opacity(0.6)

    private var fill: Color {
        if isOn { return accentWhenOn ? FlipTheme.accent : FlipTheme.panelRaised }
        return hovering && !disabled ? hoverFill : .clear
    }

    var body: some View {
        GlyphView(glyph: glyph, box: iconBox)
            .frame(width: size, height: size)
            .foregroundStyle(isOn && accentWhenOn ? Color.white
                             : disabled ? FlipTheme.textTertiary.opacity(0.4)
                             : isOn ? FlipTheme.textPrimary
                             : FlipTheme.textSecondary)
            .background(RoundedRectangle(cornerRadius: max(5, size * 0.2)).fill(fill))
            .contentShape(Rectangle())
    }
}

struct BarButton: View {
    let glyph: Glyph
    var isOn: Bool = false
    var disabled: Bool = false
    var accentWhenOn: Bool = true
    var size: CGFloat = FlipTheme.control
    var iconBox: CGFloat = FlipTheme.icon
    var hoverFill: Color = FlipTheme.panelRaised.opacity(0.6)
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            BarGlyph(glyph: glyph, isOn: isOn, hovering: hovering,
                     disabled: disabled, accentWhenOn: accentWhenOn,
                     size: size, iconBox: iconBox, hoverFill: hoverFill)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// Press for one thing, hold for another.
///
/// The press is tracked in AppKit, which is the only layer here that reliably
/// reports one. Three SwiftUI routes were tried first and all three failed on a
/// press that is held without moving: a `LongPressGesture` alongside a `Button`
/// never fires at all, because the button's own recogniser wins; a
/// zero-distance `DragGesture` reports nothing until the pointer actually moves;
/// and `onLongPressGesture` — and a `ButtonStyle` watching `isPressed` — never
/// saw the press begin. `mouseDown` always arrives.
struct HoldButton: View {
    let glyph: Glyph
    var isOn: Bool = false
    var hold: TimeInterval = 0.3
    var size: CGFloat = FlipTheme.control
    var iconBox: CGFloat = FlipTheme.icon
    var hoverFill: Color = FlipTheme.panelRaised.opacity(0.6)
    let tap: () -> Void
    let onHold: () -> Void

    @State private var hovering = false

    var body: some View {
        BarGlyph(glyph: glyph, isOn: isOn, hovering: hovering,
                 size: size, iconBox: iconBox, hoverFill: hoverFill)
            .overlay(PressCatcher(hold: hold, tap: tap, onHold: onHold,
                                  hovering: { hovering = $0 }))
    }
}

/// A transparent `NSView` that times the press it is sitting on.
private struct PressCatcher: NSViewRepresentable {
    var hold: TimeInterval
    var tap: () -> Void
    var onHold: () -> Void
    var hovering: (Bool) -> Void

    func makeNSView(context: Context) -> Catcher { configured(Catcher()) }
    func updateNSView(_ view: Catcher, context: Context) { _ = configured(view) }

    private func configured(_ v: Catcher) -> Catcher {
        v.hold = hold; v.tap = tap; v.onHold = onHold; v.hovering = hovering
        return v
    }

    final class Catcher: NSView {
        var hold: TimeInterval = 0.3
        var tap: () -> Void = {}
        var onHold: () -> Void = {}
        var hovering: (Bool) -> Void = { _ in }

        private var timer: Timer?
        private var fired = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { hovering(true) }
        override func mouseExited(with event: NSEvent)  { hovering(false) }

        override func mouseDown(with event: NSEvent) {
            fired = false
            let t = Timer(timeInterval: hold, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.fired = true
                self.onHold()
            }
            timer = t
            // Both modes: AppKit may be tracking the drag by the time this lands.
            RunLoop.current.add(t, forMode: .eventTracking)
            RunLoop.current.add(t, forMode: .default)
        }

        override func mouseUp(with event: NSEvent) {
            timer?.invalidate()
            timer = nil
            // A release after the hold has already fired is not also a tap.
            guard !fired else { return }
            if bounds.contains(convert(event.locationInWindow, from: nil)) { tap() }
        }
    }
}

/// Wide labelled button for the panels, where an icon alone would be a riddle.
struct PanelButton: View {
    let title: String
    var glyph: Glyph?
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let glyph {
                    GlyphView(glyph: glyph, box: 16)
                }
                Text(title).font(.system(size: 11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(disabled ? FlipTheme.textTertiary.opacity(0.45) : FlipTheme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: FlipTheme.button)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(hovering && !disabled ? FlipTheme.panelRaised : FlipTheme.panelRaised.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// An icon, from the app's own set or — until its artwork lands — from SF
/// Symbols. The tools are the only holdouts.
enum Glyph: Hashable {
    case icon(Icon)
    case sf(String)
}

/// `box` is the edge of the 24-unit grid the artwork is drawn on. SF Symbols
/// size by *font* size and draw a glyph noticeably smaller than the number
/// suggests, so the fallback is scaled to land in the same place.
struct GlyphView: View {
    let glyph: Glyph
    var box: CGFloat

    var body: some View {
        switch glyph {
        case .icon(let icon): IconView(icon: icon, size: box)
        case .sf(let name):   Image(systemName: name).font(.system(size: box * 0.7))
        }
    }
}

// MARK: - Floating chrome

extension View {
    /// The card the panels and the frame strip are drawn on. They float over the
    /// canvas rather than butting against the window edge, so each one needs its
    /// own edge — a border alone reads as a seam, and a shadow alone as a smudge.
    func floatingPanel(corner: CGFloat = FlipTheme.corner) -> some View {
        // Behind the fill, so it is invisible and cannot take a click — it is
        // here only to claim the arrow back from the canvas underneath.
        background(CursorArea())
            // Grained inside the background rather than over the finished
            // panel, so the texture stays under the content: grain laid over
            // the whole panel would run across the labels and glyphs too.
            .background(RoundedRectangle(cornerRadius: corner)
                .fill(FlipTheme.panel)
                .grained()
                .clipShape(RoundedRectangle(cornerRadius: corner)))
            .overlay(RoundedRectangle(cornerRadius: corner)
                .strokeBorder(FlipTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

/// One icon in the rail beside the tools panel. Squarer and a shade larger than
/// `BarButton`, because it is the only thing naming the section it opens.
struct RailButton: View {
    let glyph: Glyph
    var isOn: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            GlyphView(glyph: glyph, box: FlipTheme.icon)
                .frame(width: FlipTheme.modeButton, height: FlipTheme.modeButton)
                .foregroundStyle(isOn ? Color.white : FlipTheme.textSecondary)
                .background(RoundedRectangle(cornerRadius: FlipTheme.modeButton * 0.2)
                    .fill(isOn ? FlipTheme.accent
                          : hovering ? FlipTheme.panelRaised : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The card the frame strip raises. Not an `NSPopover`: that draws an arrow and
/// a light vibrant backing of its own, neither of which can be turned off, so
/// the popups were the only things in the app that did not look like the panels.
/// This is the same floating card, at the same width, with the same header rule.
struct PopupCard<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlipTheme.textPrimary)
                Spacer(minLength: 0)
                accessory()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(FlipTheme.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12)
        }
        .frame(width: FlipTheme.panelWidth)
        .floatingPanel()
    }
}

extension PopupCard where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}
