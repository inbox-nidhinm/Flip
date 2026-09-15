import SwiftUI
import AppKit

// The app's own context menu.
//
// `.contextMenu` puts up an `NSMenu`, and an `NSMenu` cannot be restyled: it
// draws in the system's vibrant material with the system's corner, the system's
// row height and the system's blue highlight, none of which are this app's. In
// a window that has no title bar, panels it drew itself and a palette of four
// greys, a stock menu is the one surface that announces it came from somewhere
// else. So the menu is drawn here, out of the same parts as everything else:
// `panel` over `border`, `rowHover` under the pointer, `accent` for anything
// chosen, 11pt system text.
//
// What that costs, and what is paid back:
//
//   * A menu has to escape its parent. Panels clip their contents, so a menu
//     drawn where it was asked for would be cut off at the panel's edge. It is
//     drawn instead by one `MenuLayer` at the root of the window — the same
//     move the colour card makes, and for the same reason.
//   * SwiftUI has no right-click gesture, so the trigger is an `NSView` that
//     hit-tests to itself for right and control-clicks and to nothing at all
//     otherwise, leaving every other click to pass straight through to the
//     SwiftUI view underneath.
//   * `NSMenu` brings keyboard navigation with it. Arrow keys, Return and
//     Escape are re-implemented below rather than given up.

// MARK: - Entries

/// One line of a menu: a command, a rule, or a row that opens another menu.
struct MenuEntry: Identifiable {
    let id = UUID()
    var title = ""
    /// Drawn dim and right-aligned. The keystroke, not a second sentence — the
    /// old menus carried theirs inside the title as "Rename  (⌘R)", which left
    /// every title a different length and none of the keys lined up.
    var shortcut: String?
    var enabled = true
    /// The one currently in force, where the menu is a choice between states
    /// rather than a list of commands. Ticked, and the tick reserves a gutter
    /// down the whole panel so the titles still line up with each other.
    var selected = false
    var isSeparator = false
    /// Non-nil makes this a submenu. A submenu never has an action of its own:
    /// there is nothing sensible for clicking the parent row to mean.
    var children: [MenuEntry]?
    var action: (() -> Void)?

    /// A picture of what the row *is*, under its name, for a choice whose whole
    /// point is how it looks. A list of brushes named Light and Soft tells you
    /// nothing you could act on; a stroke of each tells you everything.
    var preview: CGImage?

    static func item(_ title: String, shortcut: String? = nil,
                     enabled: Bool = true, selected: Bool = false,
                     _ action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, shortcut: shortcut, enabled: enabled,
                  selected: selected, action: action)
    }

    static var separator: MenuEntry { MenuEntry(isSeparator: true) }

    /// A row that shows what it means as well as naming it.
    static func choice(_ title: String, preview: CGImage?, selected: Bool = false,
                       _ action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, selected: selected, action: action, preview: preview)
    }

    static func submenu(_ title: String, enabled: Bool = true,
                        _ children: [MenuEntry]) -> MenuEntry {
        // An empty submenu is a row that opens onto nothing, so it is disabled
        // rather than left to be discovered.
        MenuEntry(title: title, enabled: enabled && !children.isEmpty, children: children)
    }

    var isChoosable: Bool { !isSeparator && enabled }
}

// MARK: - Host

/// The one menu that is up, if any. Held at the root so a menu outlives the row
/// that opened it — a layer row can be scrolled away, or removed by the very
/// command the menu is offering, while the menu is still on screen.
@MainActor
final class MenuHost: ObservableObject {
    struct Presentation {
        var entries: [MenuEntry]
        /// Where the pointer was, in the window's own coordinates with the
        /// origin at the top left — the space the root `ZStack` lays out in.
        var point: CGPoint
    }

    @Published var open: Presentation?

    func show(_ entries: [MenuEntry], at point: CGPoint) {
        guard !entries.isEmpty else { return }
        open = Presentation(entries: entries, point: point)
    }

    func dismiss() { open = nil }
}

// MARK: - Trigger

extension View {
    /// A right-click menu drawn by the app rather than by AppKit.
    ///
    /// Replaces `.contextMenu`, and the two must not both be attached — the
    /// system menu would come up over this one.
    func flipContextMenu(_ entries: @escaping () -> [MenuEntry]) -> some View {
        modifier(FlipContextMenu(entries: entries))
    }
}

private struct FlipContextMenu: ViewModifier {
    @EnvironmentObject private var host: MenuHost
    let entries: () -> [MenuEntry]

    func body(content: Content) -> some View {
        // An overlay rather than a background: it has to be above the content to
        // be hit-tested at all. It gives every click but a right-click back.
        content.overlay(RightClickCatcher { point in
            host.show(entries(), at: point)
        })
    }
}

/// An `NSView` that exists only to see right-clicks.
private struct RightClickCatcher: NSViewRepresentable {
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView { Catcher(onClick: onClick) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? Catcher)?.onClick = onClick
    }

    final class Catcher: NSView {
        var onClick: (CGPoint) -> Void

        init(onClick: @escaping (CGPoint) -> Void) {
            self.onClick = onClick
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        /// The whole trick. Hit testing runs during event dispatch with the
        /// event in hand, so this view can claim the clicks it wants and be
        /// invisible to the rest — a plain `NSView` that always claimed itself
        /// would swallow every left click in the row it covers.
        ///
        /// Control-click is a right-click on this platform and arrives as a
        /// `leftMouseDown` with the modifier set, so it is matched here too.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return self
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control) ? self : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) { report(event) }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { report(event) }
            else { super.mouseDown(with: event) }
        }

        /// Reported in the content view's coordinates, flipped to put the origin
        /// at the top left. The window has no title bar and the SwiftUI root
        /// fills the content view, so those are the root's own coordinates.
        private func report(_ event: NSEvent) {
            guard let content = window?.contentView else { return }
            let p = content.convert(event.locationInWindow, from: nil)
            onClick(CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y))
        }
    }
}

// MARK: - The layer that draws it

/// Sits at the root of the window, over everything. Nothing is drawn until a
/// menu is up, so at rest this costs one `if`.
struct MenuLayer: View {
    @EnvironmentObject private var host: MenuHost

    var body: some View {
        GeometryReader { proxy in
            if let open = host.open {
                ZStack(alignment: .topLeading) {
                    // Catches the click that shuts it — left, right or a press
                    // of Escape. Over the whole window, because a menu is modal
                    // in the small: while it is up it is the thing you are using.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { host.dismiss() }
                        .overlay(RightClickCatcher { _ in host.dismiss() })

                    MenuPanel(entries: open.entries, dismiss: host.dismiss,
                              bounds: proxy.size)
                        .fixedSize()
                        .modifier(PlaceMenu(point: open.point, bounds: proxy.size))
                }
                // Escape, and the keyboard focus it needs to hear one. Taken
                // only while a menu is up, so the canvas keeps the keyboard the
                // rest of the time.
                .onExitCommand { host.dismiss() }
            }
        }
    }
}

/// Puts the menu at the pointer and keeps it inside the window.
///
/// Measured after the fact rather than guessed at: a menu's height depends on
/// how many rows it has and its width on the longest label in it, and both are
/// only known once it has been laid out. It flips above the pointer when it
/// would run off the bottom and back to the left when it would run off the
/// right — the same two rules AppKit's own menus follow.
private struct PlaceMenu: ViewModifier {
    let point: CGPoint
    let bounds: CGSize
    @State private var size: CGSize = .zero

    private let margin: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, new in size = new }
            })
            .offset(x: x, y: y)
    }

    private var x: CGFloat {
        guard size.width > 0 else { return point.x }
        return min(max(margin, point.x), bounds.width - size.width - margin)
    }

    private var y: CGFloat {
        guard size.height > 0 else { return point.y }
        if point.y + size.height + margin <= bounds.height { return point.y }
        // Above the pointer, and if it does not fit there either, hard against
        // the top — a menu taller than the window is still better read from its
        // first row than from its last.
        return max(margin, min(point.y - size.height, bounds.height - size.height - margin))
    }
}

// MARK: - The menu itself

private struct MenuPanel: View {
    let entries: [MenuEntry]
    let dismiss: () -> Void
    /// The window. A submenu needs it to know which side of its parent it fits
    /// on, and it is the same size `PlaceMenu` clamps the first panel to.
    let bounds: CGSize
    /// Submenus open beside their row and are laid out relative to it, so a
    /// nested panel is just another `MenuPanel` in an overlay.
    var depth = 0

    /// The row the pointer is on, or the one the arrow keys have walked to —
    /// one piece of state, because a menu has one highlight however it got there.
    @State private var active: UUID?
    /// The submenu that is open. Not cleared when its row loses the pointer:
    /// reaching the submenu means crossing off the row that opened it, and
    /// closing on the way would make it unreachable.
    @State private var openSubmenu: UUID?
    /// How wide this panel came out, and where each of its rows landed in the
    /// window. Both are only known after layout — a panel is as wide as its
    /// longest label — and a submenu is placed from both: the width says where
    /// its parent's right edge is, the row's frame says which window it has to
    /// fit inside and which line to start on.
    @State private var panelWidth: CGFloat = 0
    @State private var rowFrames: [UUID: CGRect] = [:]
    /// The open submenu's measured size, reported back up by the child. Zero
    /// until it has been laid out once, and it is not drawn until it is not —
    /// placing it would otherwise mean guessing at its width, and a submenu
    /// that jumped sides on its second frame is worse than one that appears a
    /// frame late.
    @State private var submenuSize: CGSize = .zero
    @FocusState private var focused: Bool

    private let minWidth: CGFloat = 168
    /// Between a panel and the submenu beside it, and between either and the
    /// window's edge.
    private let gap: CGFloat = 4
    private let margin: CGFloat = 8
    /// What the panel puts above its first row. A submenu is lifted by this so
    /// that its first row lines up with the row that opened it, rather than its
    /// border doing.
    private let panelPad: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                if entry.isSeparator {
                    Rectangle()
                        .fill(FlipTheme.border)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else {
                    row(entry)
                }
            }
        }
        .padding(.vertical, panelPad)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { panelWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, new in panelWidth = new }
        })
        .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(FlipTheme.panel)
            .grained()
            .clipShape(RoundedRectangle(cornerRadius: 8)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(FlipTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        // Only the menu the pointer opened takes the keyboard; a submenu is
        // walked into from its parent.
        .focusable(depth == 0)
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { if depth == 0 { focused = true } }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.return) { choose() }
        .onKeyPress(.space) { choose() }
    }

    /// Whether this panel is a choice rather than a list of commands, and so
    /// needs the tick column. Decided once for the panel: a gutter on some rows
    /// and not others would step the titles in and out down the list.
    private var ticked: Bool { entries.contains { $0.selected } }

    private func row(_ entry: MenuEntry) -> some View {
        let lit = active == entry.id && entry.isChoosable
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if ticked {
                    IconView(icon: .check, size: 11)
                        .foregroundStyle(FlipTheme.accent)
                        .frame(width: 12)
                        // Held in the layout rather than left out of it, so the
                        // titles do not shift when the choice moves.
                        .opacity(entry.selected ? 1 : 0)
                }
                Text(entry.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let shortcut = entry.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(entry.enabled ? FlipTheme.textTertiary
                                                       : FlipTheme.textTertiary.opacity(0.5))
                } else if entry.children != nil {
                    IconView(icon: .chevronRight, size: 11)
                }
            }
            .frame(height: 24)

            if let preview = entry.preview {
                // Indented to the title, not to the row: the tick's gutter is
                // part of the name's column, and a stroke starting left of the
                // word it belongs to reads as a rule between rows.
                Image(decorative: preview, scale: 2, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, ticked ? 22 : 0)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
            }
        }
        // A disabled row is still a row — it says what is not available and why
        // the command is not there, which is why the menus offer them at all.
        .foregroundStyle(entry.enabled ? FlipTheme.textPrimary : FlipTheme.textTertiary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(lit ? FlipTheme.rowHover : .clear)
            .padding(.horizontal, 4))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: RowFrames.self,
                                   value: [entry.id: proxy.frame(in: .global)])
        })
        .contentShape(Rectangle())
        .onHover { inside in
            guard entry.isChoosable else {
                if inside { active = nil }
                return
            }
            if inside {
                active = entry.id
                // Landing on any other row closes whatever was open, which is
                // what makes the sticky submenu above safe.
                if entry.children != nil { openSubmenu = entry.id }
                else { openSubmenu = nil }
            }
        }
        .onTapGesture { fire(entry) }
        .overlay(alignment: .topLeading) {
            if let children = entry.children, openSubmenu == entry.id, entry.enabled {
                MenuPanel(entries: children, dismiss: dismiss,
                          bounds: bounds, depth: depth + 1)
                    .fixedSize()
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { submenuSize = proxy.size }
                            .onChange(of: proxy.size) { _, new in submenuSize = new }
                    })
                    .offset(x: submenuX(from: rowFrames[entry.id]),
                            y: submenuY(from: rowFrames[entry.id]))
                    // Held back for the one frame it takes to measure. See
                    // `submenuSize`.
                    .opacity(submenuSize == .zero ? 0 : 1)
            }
        }
    }

    private func fire(_ entry: MenuEntry) {
        guard entry.isChoosable, entry.children == nil else { return }
        // Dismissed first. Several of these actions put up a sheet or take the
        // keyboard for a rename field, and a menu still on screen behind one is
        // a menu that has to be dismissed twice.
        dismiss()
        entry.action?()
    }

    // MARK: Placing a submenu

    /// Right of the parent by `gap` when it fits, left of it by the same when it
    /// does not — and right anyway if it fits on neither side, because running
    /// off the window's right edge loses the ends of the labels while running
    /// off the left loses the labels themselves.
    ///
    /// Measured from the row's leading edge, which is the panel's: the overlay
    /// is anchored `.topLeading` on the row.
    private func submenuX(from anchor: CGRect?) -> CGFloat {
        let right = panelWidth + gap
        guard submenuSize.width > 0, let anchor else { return right }
        if anchor.minX + right + submenuSize.width <= bounds.width - margin { return right }
        let left = -(submenuSize.width + gap)
        return anchor.minX + left >= margin ? left : right
    }

    /// Lifted by the panel's own top padding, so the submenu's *first row* sits
    /// on the row that opened it rather than its border or its corner.
    ///
    /// Pushed back up only when the submenu would otherwise run off the bottom
    /// of the window — a menu whose last folders are unreachable is worse than
    /// one that does not quite line up.
    private func submenuY(from anchor: CGRect?) -> CGFloat {
        let aligned = -panelPad
        guard let anchor, submenuSize.height > 0 else { return aligned }
        let top = anchor.minY + aligned
        let lowest = bounds.height - margin - submenuSize.height
        guard top > lowest else { return aligned }
        return max(margin, lowest) - anchor.minY
    }

    // MARK: Keyboard

    private var choosable: [MenuEntry] { entries.filter(\.isChoosable) }

    private func move(_ step: Int) -> KeyPress.Result {
        let list = choosable
        guard !list.isEmpty else { return .ignored }
        let current = list.firstIndex { $0.id == active }
        let next: Int
        if let current { next = (current + step + list.count) % list.count }
        else { next = step > 0 ? 0 : list.count - 1 }
        active = list[next].id
        openSubmenu = list[next].children != nil ? list[next].id : nil
        return .handled
    }

    private func choose() -> KeyPress.Result {
        guard let active, let entry = entries.first(where: { $0.id == active }) else { return .ignored }
        // Return on a submenu row opens it rather than doing nothing, so the
        // keyboard can reach the same places the pointer can.
        if entry.children != nil { openSubmenu = entry.id; return .handled }
        fire(entry)
        return .handled
    }
}

/// Where each row of a panel landed, in the window's coordinates. Collected by
/// the panel so it can place a submenu against the row that opened it.
private struct RowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
