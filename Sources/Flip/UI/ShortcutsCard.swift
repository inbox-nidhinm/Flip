import SwiftUI

/// Every shortcut in the app, on one card.
///
/// A **legend, not a settings sheet.** Nothing here is editable: a key that can
/// be rebound has to be stored, migrated, and shown differently wherever else it
/// is named — the menu bar, for one. Three costs for a tool whose keys are
/// nearly all a single letter.
///
/// It is also the only place the app says what its keys are, now that nothing
/// hovers to explain itself, which is why it is under Help rather than View.
///
/// It lists what the app really does rather than a hand-kept copy: the menus
/// declare most of these, the canvas's `keyDown` the bare letters, and the
/// modifier drags are the canvas's own. Anything added in one of those three
/// places has to be added here as well, which is the one thing this file cannot
/// enforce — so the sections are ordered to match the way those three read.
struct ShortcutsCard: View {
    @EnvironmentObject private var model: AppModel

    /// How tall the two columns came out. The card is as tall as its contents
    /// until they outgrow the window, and then it stops and the list scrolls —
    /// a legend that runs off the bottom of the screen is a legend with entries
    /// nobody can read.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let room = max(240, proxy.size.height - 96)
            VStack(spacing: 0) {
                header
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: columnGap) {
                        column(Self.firstColumn)
                        column(Self.secondColumn)
                    }
                    .padding(pad)
                    .background(GeometryReader { inner in
                        Color.clear
                            .onAppear { contentHeight = inner.size.height }
                            .onChange(of: inner.size.height) { _, new in contentHeight = new }
                    })
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(width: cardWidth)
            .frame(height: min(headerHeight + contentHeight, room))
            .floatingPanel()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Measures

    /// Wide enough for two columns of key and meaning. The card is not a panel,
    /// so it does not take `panelWidth` — a legend read in one glance is worth
    /// more than one that agrees with the inspector about its width.
    private var cardWidth: CGFloat { 700 }
    private var pad: CGFloat { 18 }
    private var columnGap: CGFloat { 34 }
    /// A key cap. Square for a single character, and grown from that by the
    /// padding when the key is a word.
    private var capSize: CGFloat { 22 }
    /// Half again what it was. A legend is scanned down rather than read, and
    /// the thing that makes a column of twenty scannable is the air between the
    /// lines — at 21 the rules were doing all of that work on their own.
    private var rowHeight: CGFloat { 38 }
    private var headerHeight: CGFloat { 34 }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Text("Shortcuts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlipTheme.textPrimary)
            Spacer(minLength: 0)
            BarButton(glyph: .icon(.close)) {
                model.showShortcuts = false
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: headerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(FlipTheme.border).frame(height: 1) }
    }

    private func column(_ groups: [Group]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                Text(group.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlipTheme.textPrimary)
                    // Nothing above the first one; the header's rule is already there.
                    .padding(.top, group.id == groups.first?.id ? 0 : 20)
                    .padding(.bottom, 4)

                ForEach(group.rows) { row in
                    HStack(alignment: .center, spacing: 10) {
                        Text(row.means)
                            .font(.system(size: 12))
                            .foregroundStyle(FlipTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        chords(row.chords)
                    }
                    .frame(height: rowHeight)
                    // A rule under every row, the last one included: it closes
                    // the section off rather than leaving its final entry
                    // hanging into the space before the next heading. The rule
                    // is also what binds a meaning to the keys across the gap
                    // the two are pushed apart by.
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(FlipTheme.border.opacity(0.6)).frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The keys, right-aligned. Several chords on one row are alternatives or a
    /// pair — `[` and `]`, ⌥↑ and ⌥↓ — so they are spaced further apart than the
    /// keys within one chord, which is what says which grouping is which.
    private func chords(_ chords: [[String]]) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(chords.enumerated()), id: \.offset) { _, chord in
                HStack(spacing: 3) {
                    ForEach(Array(chord.enumerated()), id: \.offset) { _, key in
                        cap(key)
                    }
                }
            }
        }
    }

    /// One key, on its own square.
    ///
    /// A cap rather than bare text, because a shortcut is several keys and the
    /// squares are what say where one ends and the next begins — `⇧⌘D` set as
    /// text is one word until you know it is three keys. Regular weight and
    /// secondary ink: the caps are already doing the work of standing out, and at
    /// medium weight in primary they shouted over the meanings beside them.
    ///
    /// A word like `shift` or `drag` gets the same cap, just wider — the same
    /// thing is being named either way.
    private func cap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11))
            .foregroundStyle(FlipTheme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, key.count > 1 ? 7 : 0)
            .frame(minWidth: capSize, minHeight: capSize)
            // Fill alone, no edge. `panelRaised` over `panel` is already a clear
            // step, and a hairline round every cap turned a row of three keys
            // into a row of three boxes competing with the meaning beside them.
            .background(RoundedRectangle(cornerRadius: 5).fill(FlipTheme.panelRaised))
    }

    // MARK: The list

    private struct Row: Identifiable {
        let means: String
        /// One chord per alternative — a chord being the keys held together. Two
        /// of them on a row is a pair or a choice: `[` and `]`, ⌥↑ and ⌥↓.
        let chords: [[String]]
        var id: String { means + chords.flatMap { $0 }.joined() }
    }

    private struct Group: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    private static func r(_ means: String, _ chords: [String]...) -> Row {
        Row(means: means, chords: chords)
    }

    private static func g(_ title: String, _ rows: [Row]) -> Group {
        Group(title: title, rows: rows)
    }

    private static let firstColumn: [Group] = [
        g("Tools", [
            r("Cursor", ["V"]),
            r("Brush", ["B"]),
            r("Pen", ["P"]),
            r("Rectangle", ["R"]),
            r("Circle", ["O"]),
            r("Change tool in the same slot", ["Hold"]),
        ]),
        g("Frames", [
            r("Play / pause", ["Space"]),
            r("Previous / next frame", ["<"], [">"]),
            r("New blank frame", ["N"]),
            r("Duplicate frame", ["⌘", "D"]),
            r("Move frame left / right", ["⇧", "⌘", "<"], ["⇧", "⌘", ">"]),
            r("Onion skin", ["⇧", "O"]),
            r("Paste into every frame", ["⌥", "⌘", "V"]),
        ]),
        g("Selection", [
            r("Every layer in this frame", ["⌘", "A"]),
            r("Every layer in every frame", ["⇧", "⌘", "A"]),
            r("The same layer in every frame", ["⌥", "⌘", "L"]),
            r("Group layers", ["⌘", "G"]),
            r("Ungroup layers", ["⌘", "⌫"]),
            r("Rename the selected layer", ["⌘", "R"]),
            r("Duplicate as you drag it", ["⌥", "Drag"]),
            r("Delete the selection, or points", ["⌫"]),
            r("Deselect", ["Esc"]),
        ]),
    ]

    private static let secondColumn: [Group] = [
        g("Order", [
            r("Bring layer to front", ["]"]),
            r("Bring layer to back", ["["]),
            r("Bring forward", ["⌘", "]"]),
            r("Bring backward", ["⌘", "["]),
        ]),
        g("Drawing", [
            r("Constrain a shape as you draw", ["Shift"]),
            r("Lock a resize, or turn by 15°", ["Shift"]),
            r("Break a handle's symmetry", ["⌥"]),
            r("End the path open", ["Return"]),
        ]),
        g("Canvas", [
            r("Pan", ["⌃", "Drag"]),
            r("Zoom, as does a pinch", ["⌘", "Scroll"]),
            r("Move an unlocked reference", ["⌘", "Drag"]),
            r("Fit to window", ["⌘", "0"]),
            r("Show or hide layers / tools", ["⌘", "1"], ["⌘", "2"]),
            r("Show this card", ["⌘", "/"]),
        ]),
        g("File", [
            r("New", ["⌘", "N"]),
            r("Open", ["⌘", "O"]),
            r("Save", ["⌘", "S"]),
            r("Save as", ["⇧", "⌘", "S"]),
            r("Export animated SVG", ["⌘", "E"]),
            r("Export animated GIF", ["⇧", "⌘", "E"]),
        ]),
    ]
}
