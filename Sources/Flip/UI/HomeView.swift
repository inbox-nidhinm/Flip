import SwiftUI
import AppKit

/// What the app opens onto: everything in `Flip Creations`, as a shelf.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var library = Library()

    /// The card being renamed. Inline, the way a layer row renames, rather than
    /// through a dialog — it is the same gesture and there is no reason it
    /// should feel like a different one.
    @State private var renaming: URL?
    @State private var draft = ""
    @State private var addingFolder = false
    @State private var folderDraft = ""
    @State private var hovered: URL?
    /// The sidebar row under the pointer, by its title — the titles in this list
    /// are unique by construction, folders included, because two folders cannot
    /// share a name on disk.
    @State private var hoveredRow: String?
    @State private var settings = false
    @FocusState private var focused: Bool
    /// Separate from the card rename's. One `FocusState` shared between two
    /// fields means opening either one takes the other's focus, and the other's
    /// focus is what commits it.
    @FocusState private var folderFocused: Bool

    // The shelf's own metrics. Taken off the reference at 2×, so the numbers
    // here are half the ones measured there.
    /// 216 and not 232, because the panel and the gap around it together are
    /// what the eye reads as the column — and 216 + 8 + 8 is `panelWidth`, the
    /// width the layers panel occupies in the editor.
    private let sidebar: CGFloat = 216
    /// The sidebar floats rather than butting into the window, and it floats by
    /// the same amount the editor's panels do. At 4 it sat visibly tighter to
    /// the window than the layers panel does.
    private var inset: CGFloat { FlipTheme.floatInset }
    /// What every panel in the app insets its contents by — the tools panel's
    /// content, its section headers, and the layer rows' text all sit 12 in.
    private let pad: CGFloat = 12
    /// The layer row, borrowed whole: 32 tall, 4 apart, the fill inset 4 with a
    /// 4pt corner. A folder in this list is the same kind of thing as a layer in
    /// that one, so it should not be a different size.
    private let row: CGFloat = 32
    private let rowGap: CGFloat = 4
    /// Where the rule under both titles lands, measured from the top of the
    /// window. Shared, because the sidebar's wordmark and the shelf's title sit
    /// on one line and a rule that broke across the seam would say they do not.
    ///
    /// 94 rather than 78: the wordmark is bottom-aligned in this block, so the
    /// block's height is the only thing standing between it and the traffic
    /// lights above. At 78 that gap came out at 5pt and the two read as one
    /// stack; this puts about 21 between them. Raising it moves the shelf's
    /// title and every folder's title by the same amount, which is the point of
    /// there being one number.
    private let titleBlock: CGFloat = 94
    private let card: CGFloat = 158
    private let cardPad: CGFloat = 5
    /// The card's foot. Not `cardPad`: that number exists to inset the
    /// thumbnail from the card's edge, and under the date there is no picture
    /// to inset — just a caption that was sitting on the bottom edge.
    private let cardFoot: CGFloat = 12
    private let gutter: CGFloat = 24
    private let margin: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            Group {
                if settings { SettingsPane(margin: margin, titleBlock: titleBlock,
                                           showVersionHistory: { model.showVersionHistory = true }) } else { shelf }
            }
        }
        // Grained like the panels and the editor's canvas — the shelf's ground
        // is the same material as everything else, and flat here beside a
        // grained sidebar read as two different surfaces.
        .background(FlipTheme.canvas.grained())
        // Over the shelf and the settings page alike, and centred on the
        // window: it is a thing you open, read and shut, so for the moment it
        // is up it does not have to keep clear of anything.
        .overlay {
            if model.showVersionHistory {
                VersionHistoryCard { model.showVersionHistory = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: model.showVersionHistory)
        // Clicking away from the field has to be caught here, not by its own
        // focus: a click on empty panel gives first responder to nothing, so the
        // field never loses it and `onChange(of:)` never runs.
        //
        // Deliberately *not* `simultaneousGesture`. That fires for every tap in
        // the subtree, including taps on the field itself — clicking into the
        // name to move the caret would have closed the thing you were typing in.
        // A plain container tap only picks up what the children did not want,
        // which is exactly "somewhere empty"; the controls end the edit through
        // their own actions instead.
        .contentShape(Rectangle())
        .onTapGesture { endFolderEdit() }
        .onAppear { library.refresh() }
        // The library reports filing failures — a name already taken, a file it
        // could not move — and the app already has one place for that.
        .onChange(of: library.note) { _, note in
            if let note { model.errorMessage = note; library.note = nil }
        }
    }

    // MARK: Folders

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Bottom-aligned in a block of known height, which is what puts it
            // on the shelf title's line — the two are different sizes, so
            // matching their top padding would not have.
            Text("Flip")
                .flipTitle(24)
                .foregroundStyle(FlipTheme.textPrimary)
                .padding(.horizontal, pad)
                .padding(.bottom, 12)
                .frame(height: titleBlock - inset, alignment: .bottomLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(FlipTheme.border)
                .frame(height: 1)
                .padding(.horizontal, pad)
                .padding(.bottom, rowGap)

            folderRow(title: "All Projects", value: nil)
            ForEach(library.folders, id: \.self) { name in
                folderRow(title: name, value: name)
            }

            if addingFolder {
                // Exactly the row it replaces — same height, same corner, same
                // insets — so opening it does not shunt the list around. A field
                // with padding of its own was a second layout in the same place.
                TextField("Folder name", text: $folderDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textPrimary)
                    .focused($folderFocused)
                    .padding(.leading, pad)
                    .padding(.trailing, 6)
                    .frame(height: row)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(FlipTheme.panelRaised)
                        .padding(.horizontal, rowGap))
                    .onAppear { DispatchQueue.main.async { folderFocused = true } }
                    .onSubmit { endFolderEdit() }
                    // Clicking away commits what was typed and abandons what was
                    // not. An empty field is someone who opened it and changed
                    // their mind, and that should cost nothing — least of all a
                    // folder called nothing.
                    .onChange(of: folderFocused) { _, now in if !now { endFolderEdit() } }
                    .onExitCommand { folderDraft = ""; addingFolder = false }
            } else {
                sidebarRow(title: "New Folder", dim: true) { addingFolder = true }
            }

            Spacer()

            // Opens settings; it does not close them. A row that toggles is a
            // row you have to remember the state of, and every other row here
            // takes you somewhere — picking a folder is what comes back.
            sidebarRow(title: "Settings", icon: .settings, on: settings) {
                endFolderEdit()
                settings = true
            }
            // Only the last row needs this. The rows carry no gap of their own
            // any more, which is right between two of them and wrong against
            // the panel's foot — the fill would sit 4 clear at the sides and
            // hard against the bottom.
            .padding(.bottom, rowGap)
        }
        .frame(width: sidebar)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(FlipTheme.panel)
            .grained()
            .clipShape(RoundedRectangle(cornerRadius: 10)))
        .padding(inset)
    }

    /// Ends the new-folder field, making the folder only if there is a name to
    /// make it from.
    ///
    /// Guarded, because submitting removes the field and losing focus fires
    /// again on the way out — without this the second pass would run against an
    /// already-cleared draft.
    private func endFolderEdit() {
        guard addingFolder else { return }
        addingFolder = false
        let name = folderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        folderDraft = ""
        guard !name.isEmpty else { return }
        library.newFolder(named: name)
        settings = false
    }

    /// Picking a folder is also how you leave settings — there is no other way
    /// out, and needing one would mean settings were a mode rather than a place.
    @ViewBuilder
    private func folderRow(title: String, value: String?) -> some View {
        let row = sidebarRow(title: title, on: !settings && library.folder == value) {
            endFolderEdit()
            library.folder = value
            settings = false
        }
        // Only a folder that exists on disk has anything to offer. "All
        // Projects" is a way of looking at the shelf rather than a directory,
        // and there is nothing to do to it.
        if let value {
            row.flipContextMenu {
                let n = library.count(inFolder: value)
                return [
                    // The count is in the label rather than behind a
                    // confirmation: a folder with nothing in it costs nothing to
                    // trash, and one with nine drawings in it should say nine
                    // before the click, not after.
                    .item(n > 0 ? "Move Folder to Trash  (\(n) drawing\(n == 1 ? "" : "s"))"
                                : "Move Folder to Trash") {
                        library.deleteFolder(value)
                    }
                ]
            }
        } else {
            row
        }
    }

    /// One line in the sidebar, built to the layer row's measurements.
    private func sidebarRow(title: String, icon: Icon? = nil,
                            dim: Bool = false, on: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    IconView(icon: icon, size: 15)
                }
                Text(title).font(.system(size: 11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? FlipTheme.textPrimary
                             : dim ? FlipTheme.textTertiary : FlipTheme.textSecondary)
            .lineLimit(1)
            .padding(.leading, pad)
            .padding(.trailing, 6)
            .frame(height: row)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(on ? FlipTheme.rowSelected
                      : hoveredRow == title ? FlipTheme.rowHover : .clear)
                .padding(.horizontal, rowGap))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Guarded on identity: moving down the list delivers the arriving row's
        // `true` before the leaving row's `false`.
        .onHover { inside in
            if inside { hoveredRow = title }
            else if hoveredRow == title { hoveredRow = nil }
        }
    }

    // MARK: Projects

    private var shelf: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text(library.folder ?? "All Projects")
                    .flipTitle(21)
                    .foregroundStyle(FlipTheme.textPrimary)
                Spacer()
                NewAnimationButton {
                    model.newDocument()
                    model.showingHome = false
                }
            }
            .padding(.leading, margin)
            // Wider than the title's own inset. A line of type can sit close to
            // the edge; a filled control at the same distance reads as though it
            // is about to fall off it.
            .padding(.trailing, margin + 10)
            .padding(.bottom, 12)
            .frame(height: titleBlock, alignment: .bottom)

            Rectangle().fill(FlipTheme.border).frame(height: 1)

            if library.visible.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing here yet")
                        .font(.system(size: 12))
                        .foregroundStyle(FlipTheme.textSecondary)
                    Text("New animations are saved to Flip Creations automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(FlipTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: card, maximum: card),
                                                 spacing: gutter, alignment: .topLeading)],
                              alignment: .leading, spacing: gutter) {
                        ForEach(library.visible) { p in tile(p) }
                    }
                    .padding(margin)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ p: Project) -> some View {
        let lit = hovered == p.url || renaming == p.url
        return VStack(alignment: .leading, spacing: 0) {
            ProjectThumbnail(project: p, library: library)
                .frame(width: card - cardPad * 2, height: card - cardPad * 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(FlipTheme.panelRaised))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // The name and the date sit in from the thumbnail's edge rather than
            // flush with it — the picture is the thing with a hard edge, and a
            // caption starting on that same line reads as part of the frame
            // rather than as a label under it. The rename field goes with them,
            // so what you type lands where the name was.
            Group {
            if renaming == p.url {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textPrimary)
                    .focused($focused)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(FlipTheme.panelRaised))
                    .padding(.top, 8)
                    .onAppear { draft = p.name; DispatchQueue.main.async { focused = true } }
                    .onSubmit { library.rename(p, to: draft); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                Text(p.name)
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 10)
                Text(p.modified.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10))
                    .foregroundStyle(FlipTheme.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, cardPad)
        .padding(.top, cardPad)
        .padding(.bottom, cardFoot)
        .frame(width: card, alignment: .leading)
        // The sidebar's own colour, so a lit card reads as the same material as
        // the panel beside it rather than as a fourth grey.
        .background(RoundedRectangle(cornerRadius: 10).fill(lit ? FlipTheme.panel : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? p.url : (hovered == p.url ? nil : hovered) }
        // The same zero-distance drag the layer rows use, and for the same
        // reason: a `TapGesture` gives up the moment the hand drifts.
        .gesture(DragGesture(minimumDistance: 0).onEnded { g in
            guard abs(g.translation.width) < 6, abs(g.translation.height) < 6 else { return }
            open(p)
        })
        .flipContextMenu {
            var moves: [MenuEntry] = [
                .item("Top Level", enabled: p.folder != nil) { library.move(p, toFolder: nil) }
            ]
            if !library.folders.isEmpty { moves.append(.separator) }
            moves += library.folders.map { name in
                .item(name, enabled: p.folder != name) { library.move(p, toFolder: name) }
            }
            return [
                .item("Open") { open(p) },
                .separator,
                .item("Rename") { renaming = p.url },
                .submenu("Move to Folder", moves),
                .separator,
                .item("Move to Trash") { library.delete(p) },
            ]
        }
    }

    private func open(_ p: Project) {
        endFolderEdit()
        model.loadDocument(from: p.url)
        model.showingHome = false
    }
}

/// `PanelButton` in everything but the `Spacer` — the shelf's one button stands
/// on its own rather than filling a slot, so it is sized to its label; the
/// padding, height, corner, fill and type are the panel button's own.
private struct NewAnimationButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                IconView(icon: .plus, size: 12)
                Text("New Animation").font(.system(size: 11))
            }
            .foregroundStyle(FlipTheme.textSecondary)
            // Not symmetric, because the two ends are not the same thing. The
            // plus is drawn inside a 12pt box and its ink stops about 2pt short
            // of it, so 8 on the left reads as 10; the text has no such margin
            // and 8 on the right read as 8. This puts the same air at both ends
            // of what you can actually see.
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: FlipTheme.button)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? FlipTheme.panelRaised : FlipTheme.panelRaised.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Everything the app keeps outside a document. One thing so far.
private struct SettingsPane: View {
    let margin: CGFloat
    let titleBlock: CGFloat
    let showVersionHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .flipTitle(21)
                .foregroundStyle(FlipTheme.textPrimary)
                .padding(.horizontal, margin)
                .padding(.bottom, 12)
                .frame(height: titleBlock, alignment: .bottomLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(FlipTheme.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Auto save location")
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppModel.creationsFolder.path
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11))
                        .foregroundStyle(FlipTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        // The button's height, not the panel control's — the two
                        // sit one above the other and a field a few points
                        // shorter than the button under it reads as a mistake.
                        .frame(height: FlipTheme.button)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(FlipTheme.panelRaised))

                    // Under the path rather than beside it, and without a glyph:
                    // the path is the wide thing and the button is one short
                    // phrase, so side by side either the field was cramped or
                    // the button had a hand's width of empty space in it.
                    PanelButton(title: "Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppModel.creationsFolder])
                    }
                    .frame(width: 140)
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .padding(margin)

            Spacer()

            // At the foot of the page, under everything. It is not a setting —
            // nothing here changes what the app does — so it does not belong in
            // the column of things that do; it is the one thing on this page
            // you read rather than set.
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(FlipTheme.border).frame(height: 1)

                HStack(spacing: 10) {
                    // No glyph, like Show in Finder above it. Both are one
                    // short phrase on a page with two buttons on it, and a
                    // drawing on one of them would ask what the other's is.
                    PanelButton(title: "Version history") {
                        showVersionHistory()
                    }
                    .frame(width: 140)

                    // The same words the card's header uses, so the button and
                    // what it opens agree about what the number is called.
                    Text("v\(VersionHistory.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(FlipTheme.textTertiary)
                }
                .padding(.horizontal, margin)
                .padding(.bottom, margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A drawing's first frame. Its own view so the grid can render one card at a
/// time as it appears, rather than reading every file in the folder before the
/// window will draw at all.
private struct ProjectThumbnail: View {
    let project: Project
    let library: Library

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: project.url) { image = await library.thumbnail(for: project) }
    }
}
