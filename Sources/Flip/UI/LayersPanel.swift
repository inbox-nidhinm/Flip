import SwiftUI

/// The current frame's stack, top layer first.
///
/// Layers belong to the frame, not to the document — each frame owns its own
/// stack, which is what makes this a flipbook rather than a timeline. A boolean
/// or a group expands to show what it is made of, because those layers are still
/// there — to any depth, since a group can hold a group.
struct LayersPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded: Set<UUID> = []
    @State private var draft = ""
    @FocusState private var renameFocused: Bool
    /// The row a range runs from: the last one clicked without shift. Panel
    /// state, not the model's — it is a fact about this list, and it means
    /// nothing to a selection made on the canvas or from the menu bar.
    @State private var anchor: UUID?

    /// Renaming the file. Moved here from the title bar along with the name
    /// itself — the name is in this panel now, so the field that edits it is.
    @State private var renamingFile = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    /// Whether the frames list is open, and how tall it is when it is.
    ///
    /// Panel state, not the model's: it is a fact about how this panel is
    /// arranged, and it means nothing to the document or to anything else that
    /// reads the frames.
    @State private var framesOpen = true
    @State private var framesHeight: CGFloat = 148
    @State private var gripping = false
    @State private var gripHover = false
    @State private var gripStart: CGFloat = 0
    /// The frame row under the pointer. Panel state rather than the model's,
    /// unlike `hoveredLayer` — a hovered layer has something to say to the
    /// canvas, and a hovered frame has nothing to say to anything but this row.
    @State private var hoveredFrame: Int?
    @State private var homeHover = false

    /// Where the layer list is scrolled to, and how tall its window is — enough
    /// to answer whether a given row is on screen. Both are read off the layout
    /// rather than tracked, because `ScrollView` will not say.
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    // MARK: Dragging a row
    //
    // Nothing in the document moves until the hand comes up. The rows being
    // dragged are *drawn* where the cursor is and the list underneath holds
    // still; a line shows where they would land.
    //
    // Reordering live, on every tick of the drag, was the first attempt and it
    // is why this reads the way it does: applying the move reflows the list, the
    // reflow moves the row out from under the cursor, and the next tick measures
    // against a list that has already answered — so it jitters between two
    // places and the row never sits where the hand is. Held still, the drag is
    // one move made once, and the arithmetic has a fixed layout to work in.

    /// The row the hand went down on.
    @State private var dragging: UUID?
    /// How far it has travelled. This is the offset the moving rows are drawn
    /// at, so the block tracks the cursor exactly rather than snapping by rows.
    @State private var dragDY: CGFloat = 0
    /// Sideways travel, which is what chooses the depth: out of a group, or
    /// into the one it is passing.
    @State private var dragDX: CGFloat = 0
    /// Where the moving block started, which rows travel with it, and the indent
    /// it was picked up at — all taken once and not touched again for the length
    /// of the drag.
    @State private var dragOrigin = 0
    @State private var dragMoving: Set<Int> = []
    @State private var dragStartDepth = 0
    /// Every place the block could land, worked out once against the layout that
    /// is standing still.
    @State private var dragSlots: [DropSlot] = []
    /// Where it would land, and where it started — equal means the drag has not
    /// asked for anything, and the drop is not an edit.
    @State private var dragSlot: DropSlot?
    @State private var dragStartSlot: DropSlot?
    /// The row-level targets that sit *inside* a layer row and take their own
    /// click — the disclosure chevron and the eye. Held by layer id, because a
    /// row's own hover says nothing about which of its two controls you are on.
    @State private var hoveredChevron: UUID?
    @State private var hoveredEye: UUID?
    @State private var framesHeaderHover = false
    @State private var nameHover = false

    /// Taller than the 24 a panel control takes. A layer row is a *list* row —
    /// it is scanned down rather than aimed at, and it carries five things
    /// across its width. Nothing inside the row grew to get here; this is all
    /// breathing room, and it works with the gap between rows rather than
    /// instead of it. Row plus gap is a 36pt pitch, from 26 originally.
    private let rowHeight: CGFloat = 32

    /// Everything in the panel is laid out to the layer row: 32 tall, the fill
    /// inset 4 with a 4pt corner, text 12 in. The home screen's sidebar is built
    /// to the same numbers, which is why the two read as one app.
    private let pad: CGFloat = 12
    /// The fill's inset from the panel's edges, and the corner it takes.
    private let rowGap: CGFloat = 4
    /// Between one row and the next. Nothing: a row carries ten of its own
    /// above and below its text, and a gap on top of that spread a short list
    /// out over the whole panel. Held apart from `rowGap` because the drag's
    /// arithmetic reads it as the row pitch, and the fill's side inset is not
    /// the same measurement even where the two once had the same value.
    private let rowSpacing: CGFloat = 0

    /// The groups the selection is buried inside. Computed once per pass and
    /// handed down, rather than asked per row — per row it is a walk of the
    /// whole tree for every line in the list.
    private var containers: Set<UUID> {
        LayerTree.containers(of: model.selection, in: model.frame.layers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader
            PanelDivider()
            framesSection
            PanelDivider()
            sectionHeader("Layers")
            layerList
        }
        // Beside the traffic lights, in the strip the file header already keeps
        // clear of them. An overlay rather than a row in the stack, because that
        // strip is *empty space* — putting a button in the layout would push the
        // file name down by its height, and the name is where the title bar used
        // to be.
        .overlay(alignment: .topTrailing) { homeButton }
        // Selecting a shape inside a shut group opens the group. Selecting it
        // on the canvas is a claim about *that shape*, and a list that answers
        // by highlighting nothing — because the row is folded away — is a list
        // that looks broken.
        .onChange(of: model.selection) { _, _ in expanded.formUnion(containers) }
        // No fill of its own. `floatingPanel` already lays down `panel`, and a
        // second opaque copy of it here sat *over* that one — which cost
        // nothing while the two were the same flat colour, and hid the grain
        // the moment the one underneath had any.
    }

    // MARK: Home

    /// Back to the shelf, from the one place in the window that has room for it.
    ///
    /// At the far end of the strip the traffic lights sit in, with the whole gap
    /// between them: they are the window's controls and this is the app's, and a
    /// button tucked up against the green one would read as a fourth light.
    ///
    /// `TrafficLights` puts them at (20, 20) in the *window* and this padding is
    /// measured from the panel's own edge, 8 in from the window's — so 7 here is
    /// 15 there, which centres a 22pt button on their line rather than on the
    /// strip.
    private var homeButton: some View {
        Button { model.goHome() } label: {
            IconView(icon: .home, size: 15)
                .foregroundStyle(homeHover ? FlipTheme.textPrimary : FlipTheme.textTertiary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(homeHover ? FlipTheme.panelRaised : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { homeHover = $0 }
        .padding(.trailing, pad - 4)
        .padding(.top, 6)
    }

    // MARK: The file

    /// The name of the file and the folder it is filed under.
    ///
    /// Carries the window drag, because it is where the title bar used to be and
    /// the window has no other chrome left to be dragged by. The top padding is
    /// what clears the traffic lights, which now sit inside this panel — see
    /// `TrafficLights`.
    private var fileHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            if renamingFile {
                TextField("", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlipTheme.textPrimary)
                    .focused($nameFocused)
                    .onAppear { nameDraft = model.documentName
                                DispatchQueue.main.async { nameFocused = true } }
                    .onSubmit { commitFileName() }
                    .onExitCommand { renamingFile = false }
                    .onChange(of: nameFocused) { _, now in if !now, renamingFile { commitFileName() } }
            } else {
                Text(model.documentName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.statusNote == nil ? FlipTheme.textPrimary : FlipTheme.accent)
                    .lineLimit(1)
                    // Clicking the name renames it, and nothing else here says
                    // so. The fill hugs the word and bleeds back out, so the
                    // header does not shift as the pointer crosses it — and it
                    // stays away while a status note is up, because the tap is
                    // guarded then and a hover would be offering something that
                    // will not happen.
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(nameHover && model.statusNote == nil ? FlipTheme.rowHover : .clear))
                    .padding(.horizontal, -4)
                    .contentShape(Rectangle())
                    .onHover { nameHover = $0 }
                    // High priority, or the window drag below takes every click
                    // — the same thing that stopped the old title bar's own
                    // rename from ever firing.
                    .highPriorityGesture(TapGesture().onEnded {
                        guard model.statusNote == nil else { return }
                        nameDraft = model.documentName
                        renamingFile = true
                    })
            }

            Text(model.documentFolder ?? "All Projects")
                .font(.system(size: 10))
                .foregroundStyle(FlipTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, pad)
        .padding(.top, 44)
        .padding(.bottom, pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private func commitFileName() {
        if nameDraft != model.documentName { model.renameDocument(nameDraft) }
        renamingFile = false
    }

    // MARK: Frames

    private var framesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                framesOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Frames")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlipTheme.textPrimary)
                    // Only when shut. Open, the ticked row says it better than a
                    // number does; shut, the number is the only thing left that
                    // can.
                    if !framesOpen {
                        Text("\(model.frameIndex + 1)")
                            .font(.system(size: 11))
                            .foregroundStyle(FlipTheme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    IconView(icon: .chevronRight, size: 12)
                        .foregroundStyle(FlipTheme.textTertiary)
                        .rotationEffect(.degrees(framesOpen ? 90 : 0))
                }
                .padding(.leading, pad)
                .padding(.trailing, 8)
                .frame(height: rowHeight)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(framesHeaderHover ? FlipTheme.rowHover : .clear)
                    .padding(.horizontal, rowGap))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { framesHeaderHover = $0 }
            .padding(.bottom, rowGap)

            if framesOpen {
                ScrollView {
                    LazyVStack(spacing: rowSpacing) {
                        ForEach(model.doc.frames.indices, id: \.self) { i in
                            frameRow(i)
                        }
                    }
                    .padding(.bottom, rowGap)
                }
                .frame(height: framesHeight)

                framesGrip
            }
        }
    }

    private func frameRow(_ i: Int) -> some View {
        let on = i == model.frameIndex
        return Button {
            model.stop()
            model.go(to: i)
        } label: {
            Text("Frame \(i + 1)")
                .font(.system(size: 11))
                .foregroundStyle(on ? FlipTheme.textPrimary : FlipTheme.textSecondary)
                .lineLimit(1)
                .padding(.leading, pad)
                .padding(.trailing, 6)
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(on ? FlipTheme.rowCurrent
                          : hoveredFrame == i ? FlipTheme.rowHover : .clear)
                    .padding(.horizontal, rowGap))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Guarded on identity for the same reason the layer rows are: moving
        // between two rows delivers the arriving row's `true` before the leaving
        // row's `false`, and an unguarded clear would drop the highlight the
        // pointer had just landed on.
        .onHover { inside in
            if inside { hoveredFrame = i }
            else if hoveredFrame == i { hoveredFrame = nil }
        }
        .flipContextMenu {
            // Disabled rather than absent on the last frame, so the menu says
            // why the command is not there: a flipbook with no frames is not a
            // thing the app can hold.
            [.item("Delete Frame", enabled: model.doc.frames.count > 1) {
                model.deleteFrame(at: i)
            }]
        }
    }

    /// The bar between the two lists, dragged to give one of them more room.
    ///
    /// Its own hit area is taller than the line it draws — a 1pt target is not
    /// grabbable — and the line only appears under the pointer, so at rest the
    /// panel reads as two sections rather than three.
    private var framesGrip: some View {
        Rectangle()
            .fill(gripping || gripHover ? FlipTheme.border : Color.clear)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { gripHover = $0; if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !gripping { gripping = true; gripStart = framesHeight }
                        framesHeight = min(max(gripStart + g.translation.height, 60), 420)
                    }
                    .onEnded { _ in gripping = false }
            )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(FlipTheme.textPrimary)
            .padding(.horizontal, pad)
            .frame(height: rowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, rowGap)
    }

    @ViewBuilder private var layerList: some View {
        if model.frame.layers.isEmpty {
            Spacer()
        } else {
            ScrollViewReader { scroll in
            ScrollView {
                // Gaps between the rows, not just taller rows. Height alone did
                // not fix this: at any height a run of rows with no gaps is one
                // block of text, and the eye has to count swatches to find where
                // one layer ends and the next starts.
                let holding = containers
                let list = rows
                LazyVStack(spacing: rowSpacing) {
                    ForEach(Array(list.enumerated()), id: \.element.layer.id) { i, entry in
                        row(entry.layer, depth: entry.depth,
                            holds: holding.contains(entry.layer.id), at: i)
                    }
                }
                // The rows in hand, drawn over the list rather than in it.
                //
                // `zIndex` on the row inside the stack is what this was first,
                // and it does not hold in a `LazyVStack` — the row below went on
                // painting its name over the carried row's fill. Lifted out into
                // an overlay there is no ordering to argue with: the list draws,
                // then this does. The row's own copy is left in place and hidden,
                // so the hole it came out of stays open.
                .overlay(alignment: .top) {
                    if dragging != nil {
                        let pitch = rowHeight + rowSpacing
                        ForEach(dragMoving.sorted(), id: \.self) { i in
                            if list.indices.contains(i) {
                                row(list[i].layer, depth: list[i].depth,
                                    holds: holding.contains(list[i].layer.id),
                                    at: i, lifted: true)
                                    .offset(y: CGFloat(i) * pitch + dragDY)
                            }
                        }
                        // Inert. It is a picture of a row, and the gesture that
                        // is moving it belongs to the one still in the list.
                        .allowsHitTesting(false)
                    }
                }
                // Where the block would land. Drawn over the list rather than
                // between its rows: the list is holding still, so there is no
                // gap being opened for it to sit in, and a line in the gap that
                // is already there is what says "here" without moving anything.
                // Last, so the row in hand cannot cover it.
                .overlay(alignment: .topLeading) {
                    if dragging != nil, let slot = dragSlot {
                        Group {
                            if slot.onto != nil {
                                // Going *inside* a group rather than between two
                                // rows. Drawn round the group, because a line at
                                // this indent would say the same thing as the
                                // line one step out already says.
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(FlipTheme.accent, lineWidth: 2)
                                    .padding(.horizontal, 4)
                                    .frame(height: rowHeight)
                                    .offset(y: CGFloat(slot.gap) * (rowHeight + rowSpacing))
                            } else {
                                Capsule()
                                    .fill(FlipTheme.accent)
                                    .frame(height: 2)
                                    // Starts at the indent of the stack it
                                    // means, so the line says which one it is:
                                    // level with the rows it would join, stepped
                                    // in for a group it would go inside, stepped
                                    // back out for the frame's own stack. The
                                    // row fill's inset is the right-hand end.
                                    .padding(.leading, slot.indent)
                                    .padding(.trailing, 4)
                                    // The offsets are the line's centre; the
                                    // capsule is laid against the top of the
                                    // stack, so it is its own half-height that
                                    // has to come off.
                                    .offset(y: slot.y - 1)
                            }
                        }
                        .animation(.easeOut(duration: 0.09), value: slot)
                    }
                }
                .padding(.bottom, rowGap)
                // How far the list has been scrolled, read off its own top edge
                // against the scroll view's frame.
                .background(GeometryReader { inner in
                    Color.clear
                        .onChange(of: inner.frame(in: .named(Self.scrollSpace)).minY) { _, y in
                            scrollOffset = -y
                        }
                })
            }
            .coordinateSpace(name: Self.scrollSpace)
            .background(GeometryReader { outer in
                Color.clear
                    .onAppear { viewportHeight = outer.size.height }
                    .onChange(of: outer.size.height) { _, h in viewportHeight = h }
            })
            // A layer picked anywhere but this list — on the canvas, from the
            // menu bar, by ⌥-clicking a twin — is very often one this list is
            // not currently showing. Rather than leaving the panel looking as
            // though nothing happened, it opens whatever the layer is buried in
            // and scrolls to it.
            //
            // Guarded on whether the row is already on screen, which is what
            // keeps it from fighting the user: clicking a row *in* this list
            // also changes the selection, and a jump that re-centred the row you
            // had just aimed at would be the panel tugging back.
            .onChange(of: model.selection) { _, _ in reveal(with: scroll) }
            .onChange(of: model.frameIndex) { _, _ in reveal(with: scroll) }
            }
        }
    }

    /// The scroll view's own coordinate space, for measuring how far it has run.
    private static let scrollSpace = "layerScroll"

    /// Opens what the topmost selected layer is inside, and scrolls to it if it
    /// is off screen.
    private func reveal(with scroll: ScrollViewProxy) {
        guard !model.selection.isEmpty else { return }

        // Everything between the frame and the layer has to be open for the row
        // to exist at all — a shape inside a shut group has no row to scroll to.
        let buried = LayerTree.stacks(of: model.selection, in: model.frame.layers)
            .flatMap { $0 }
        let toOpen = Set(buried).subtracting(expanded)
        if !toOpen.isEmpty { expanded.formUnion(toOpen) }

        // After the expansion, so the index is the one the list will actually
        // lay out. A tick late for the same reason: the rows do not exist until
        // SwiftUI has been round again.
        DispatchQueue.main.async {
            let list = rows
            guard let index = list.firstIndex(where: { model.selection.contains($0.layer.id) })
            else { return }

            let pitch = rowHeight + rowSpacing
            let top = CGFloat(index) * pitch
            let onScreen = top >= scrollOffset
                && top + rowHeight <= scrollOffset + viewportHeight
            guard !onScreen else { return }

            withAnimation(.easeInOut(duration: 0.22)) {
                scroll.scrollTo(list[index].layer.id, anchor: .center)
            }
        }
    }

    /// The rows the panel is actually showing, top of the stack first, with the
    /// contents of anything open folded in beneath it.
    ///
    /// One flat list rather than nested `ForEach`es, for two reasons: it nests to
    /// any depth, and it *is* the order a shift-click range runs along. What lies
    /// between two rows depends on which groups are open, so only this list can
    /// say — which is why the model is handed the order rather than working it out.
    /// Each row also carries the path of containers it sits inside, which is the
    /// stack it belongs to — what a drag needs in order to drop into a stack
    /// that is not the one it came from. `depth` is that path's length, kept
    /// alongside it because the indent is read far more often than the path.
    private var rows: [Row] {
        var out: [Row] = []
        func walk(_ layers: [Layer], _ path: [UUID]) {
            for layer in layers.reversed() {
                out.append(Row(layer: layer, depth: path.count, path: path))
                if layer.hasChildren, expanded.contains(layer.id) {
                    walk(layer.children, path + [layer.id])
                }
            }
        }
        walk(model.frame.layers, [])
        return out
    }

    struct Row {
        var layer: Layer
        var depth: Int
        /// The containers between the frame and this row, outermost first. Empty
        /// for a top-level layer.
        var path: [UUID]
    }

    private func row(_ layer: Layer, depth: Int, holds: Bool, at index: Int,
                     lifted: Bool = false) -> some View {
        // `lifted` is the copy drawn in the overlay, in the hand. The one left
        // in the list is hidden while it is, which is what leaves the hole.
        let hidden = !lifted && dragging != nil && dragMoving.contains(index)
        let selected = model.selection.contains(layer.id)
        let hovered = model.hoveredLayer == layer.id
        // How far the whole selection reaches, not this row's own twins: what the
        // row needs to warn about is where an edit will land, and an edit lands on
        // the selection. Allocation-free and early-exiting, so per-row is fine.
        let span = model.frameSpan(of: model.selection)

        return HStack(spacing: 5) {
            if layer.hasChildren {
                // A `highPriorityGesture`, not a `Button`. The row carries a tap
                // of its own for selection, and an ancestor's tap beats a
                // descendant's button — the chevron was drawn, hit, and did
                // nothing, because every tap on it selected the row instead.
                // High priority is the one ordering that reverses that.
                IconView(icon: .chevronRight, size: 13)
                    // It takes its own click, so it answers the pointer on its
                    // own — the row's band says you are on the row, not that
                    // this is the part of it that opens the group.
                    .foregroundStyle(hoveredChevron == layer.id ? FlipTheme.textPrimary
                                                                : FlipTheme.textTertiary)
                    .rotationEffect(.degrees(expanded.contains(layer.id) ? 90 : 0))
                    // Full row height: 9×13 was a small target for the one
                    // control that has to be hit to navigate a deep stack.
                    .frame(width: 9, height: rowHeight)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredChevron = layer.id }
                        else if hoveredChevron == layer.id { hoveredChevron = nil }
                    }
                    .highPriorityGesture(TapGesture().onEnded {
                        if expanded.contains(layer.id) { expanded.remove(layer.id) }
                        else { expanded.insert(layer.id) }
                    })
            } else {
                Spacer().frame(width: 9)
            }

            // Passive, and it has to say so. The row's tap sits *behind* its
            // contents (see the background below), and anything in front of it
            // that answers a hit swallows that tap — which is what made a click
            // on a layer's own name do nothing at all, and left the empty strip
            // beside it as the only place the row could be selected from. The
            // chevron, the eye and the rename field keep their hits; nothing
            // else here has any use for one.
            swatch(layer)
                .allowsHitTesting(false)

            if model.renamingLayer == layer.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textPrimary)
                    .focused($renameFocused)
                    // The field opens from the menu bar and from a right-click
                    // now, and neither of those leaves the keyboard in it, so it
                    // claims focus itself. It seeds the draft here too, since ⌘R
                    // has no row in hand to read the current name from. The hop
                    // is needed: focus set in the same pass that creates the
                    // field does not stick.
                    .onAppear {
                        draft = layer.name
                        DispatchQueue.main.async { renameFocused = true }
                    }
                    .onSubmit { commitRename(layer) }
                    .onExitCommand { model.renamingLayer = nil }
                    // Clicking away commits, the way the Finder does.
                    .onChange(of: renameFocused) { _, focused in
                        if !focused, model.renamingLayer == layer.id { commitRename(layer) }
                    }
            } else {
                Text(layer.name)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? FlipTheme.textPrimary : FlipTheme.textSecondary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }

            Spacer(minLength: 0)

            // The panel can only ever highlight rows of the frame on screen, so a
            // selection that reaches further has to say so on the row itself —
            // otherwise an edit quietly lands on frames you cannot see.
            if selected, span > 1 {
                IconView(icon: .link, size: 14)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(FlipTheme.accent)
                    // A badge, not a control — it says something about the row
                    // rather than doing something to it.
                    .allowsHitTesting(false)
            }

            if let op = layer.op {
                IconView(icon: op.icon, size: 14)
                    .font(.system(size: 9))
                    .foregroundStyle(FlipTheme.textTertiary)
                    .allowsHitTesting(false)
            }

            // A rig on this layer, or on anything inside it. A group carries no
            // rig of its own — armatures own shapes — so without this a grouped
            // character says nothing anywhere about being rigged until you have
            // opened every group in the list to find out.
            if model.frame.rigIndex(of: layer) != nil {
                IconView(icon: .bone, size: 14)
                    .font(.system(size: 9))
                    .foregroundStyle(FlipTheme.textTertiary)
                    // A badge, not a control — it says something about the row
                    // rather than doing something to it, like the link and the
                    // boolean's operation above.
                    .allowsHitTesting(false)
            }

            // Same reason as the chevron: as a button, every tap on it selected
            // the row instead of toggling the layer.
            IconView(icon: layer.visible ? .eye : .eyeSlash, size: 15)
                // Same as the chevron: its own click, so its own hover. Hidden
                // it is already dimmed, and brightening to secondary is what
                // says the dimming is a state rather than the control being off.
                .foregroundStyle(hoveredEye == layer.id ? FlipTheme.textPrimary
                                 : layer.visible ? FlipTheme.textTertiary
                                 : FlipTheme.textSecondary.opacity(0.5))
                // Out of sight until the pointer is on the row. A column of eyes
                // down a long list is a row of controls nobody asked for, and
                // every one of them competes with the drawing's own swatch for
                // the eye. A layer that is *off* keeps its crossed eye whatever
                // the pointer is doing: that is the layer saying something about
                // itself, not the panel offering a control.
                //
                // Faded rather than removed, so the badge beside it cannot shift
                // sideways when the pointer arrives — the slot is always there.
                .opacity(layer.visible && !hovered ? 0 : 1)
                .frame(width: 20, height: rowHeight)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredEye = layer.id }
                    else if hoveredEye == layer.id { hoveredEye = nil }
                }
                .highPriorityGesture(TapGesture().onEnded {
                    model.setVisible(layer.id, !layer.visible)
                })
        }
        .padding(.leading, CGFloat(12 + depth * 14))
        .padding(.trailing, 6)
        .frame(height: rowHeight)
        // The row's own tap sits **behind** its controls rather than over them.
        // A `contentShape` on the row made the whole thing one hit target, and a
        // tap on the disclosure chevron or the eye never reached the button
        // inside it — the row's gesture took every one, so a group could not be
        // opened. Behind them, the name and the spacers pass taps down to it
        // while the buttons keep their own.
        .background {
            // Rounded and inset, which is what every other hover in the app
            // already is — the frame tiles and the shortcut rows both sit in a
            // rounded well, and this row's square full-bleed band was the
            // outlier. With gaps between the rows it has to be: a bare
            // rectangle butting into the panel's edges reads as a stripe rather
            // than as a row.
            //
            // The *fill* is inset. The hit target is not, and must not be, or
            // there would be a four-point dead strip down each side of the list
            // where a click lands on nothing.
            RoundedRectangle(cornerRadius: 4)
                // The strong band is the selection's now — it is the one thing
                // in this panel nothing else on screen tells you. A group the
                // selection is buried in takes a weaker draw of the same colour,
                // so you can trace where the shape lives without the trail
                // competing with the shape itself.
                .fill(selected ? FlipTheme.rowSelected
                      : lifted ? FlipTheme.panelRaised
                      : holds ? FlipTheme.rowSelected.opacity(0.45)
                      : hovered ? FlipTheme.rowHover : Color.clear)
                // The lift, on the fill rather than on the row: it is the only
                // thing in a row with a shape to cast one, and a `shadow` on
                // every row of a hundred-layer list is a render pass each even
                // when the colour is clear.
                .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 8, y: 3)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // A zero-distance drag, not a `TapGesture`.
                //
                // `TapGesture` cancels the moment the pointer moves a hair, and
                // shift-clicking down a list is exactly when the hand drifts —
                // which is why range-selecting worked on the third or fourth
                // try rather than the first. This fires whatever the hand does;
                // the threshold below only exists so a genuine drag across the
                // panel is not mistaken for a click.
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    // Past the slop this is a reorder, not a click. The same 6pt
                    // the click below allows itself for hand drift is what tells
                    // the two apart, so nothing is both.
                    .onChanged { g in
                        // Measured in the window, not in the row. The list is
                        // inside a `ScrollView`, and a gesture's local
                        // translation is expressed in the scrolling content's
                        // own space — so anything that moves the content moves
                        // the number too, and the drag reads as jumping about
                        // while the hand is holding still.
                        let dy = g.location.y - g.startLocation.y
                        let dx = g.location.x - g.startLocation.x
                        if dragging != layer.id {
                            guard abs(dy) >= 6 else { return }
                            beginDrag(of: layer, at: index)
                        }
                        dragDY = dy
                        dragDX = dx
                        dragSlot = chooseSlot(dx: dx, dy: dy)
                    }
                    .onEnded { g in
                    if dragging == layer.id { endDrag(); return }
                    guard abs(g.location.x - g.startLocation.x) < 6,
                          abs(g.location.y - g.startLocation.y) < 6 else { return }
            let mods = NSEvent.modifierFlags
            if mods.contains(.option) {
                // ⌥ takes the same layer in every frame, so one edit covers the
                // whole animation instead of one edit per frame. ⌥ pans on the
                // canvas, but a panel row is not the canvas and cannot be panned.
                model.selectLinked(layer.id, additive: mods.contains(.shift))
            } else if mods.contains(.shift) {
                // Everything from the last plain click to here, which is what
                // shift means in every list on this platform. Picking layers out
                // one at a time moved to ⌘, where the rest of the system also
                // keeps it — and with thirty shapes in a frame, a run is what you
                // reach for far more often than a scattering.
                if let anchor, anchor != layer.id {
                    model.selectRange(in: rows.map { $0.layer.id }, from: anchor, to: layer.id)
                } else {
                    model.selection = [layer.id]
                    model.selectedNodes = []
                    anchor = layer.id
                }
            } else if mods.contains(.command) {
                if model.selection.contains(layer.id) { model.selection.remove(layer.id) }
                else { model.selection.insert(layer.id) }
                model.selectedNodes = []
                anchor = layer.id
            } else {
                model.selection = [layer.id]
                model.selectedNodes = []
                anchor = layer.id
            }
                })
        }
        // Carried with the cursor, and lifted off the list while it is: a shadow
        // and a hair of transparency, so the rows it is passing over stay
        // readable underneath it and it reads as picked up rather than as
        // having already landed.
        // The hole. Kept in the layout rather than removed from it, so the rows
        // around it do not close up and every measurement the drag took stays
        // true for as long as the drag lasts.
        .opacity(hidden ? 0 : 1)
        // Guarded on identity, not written blind. Moving between two rows fires
        // the arriving row's `true` before the leaving row's `false`, so an
        // unguarded `nil` on exit would wipe the row the pointer had just
        // reached and the highlight would drop out every time it moved.
        //
        // Nothing hovers while a drag is up. The block is over the list, so the
        // rows under it would light one after another as it passed.
        .onHover { inside in
            guard dragging == nil else { return }
            if inside { model.hoveredLayer = layer.id }
            else if model.hoveredLayer == layer.id { model.hoveredLayer = nil }
        }
        // A row scrolled out of a lazy stack, or removed under the pointer by an
        // undo or a frame change, never gets its `false`. Without this the box
        // would be left drawn on the canvas around a shape nothing is pointing at.
        .onDisappear {
            if model.hoveredLayer == layer.id { model.hoveredLayer = nil }
        }
        // Rename is a right-click and ⌘R, never a double-click. A double-tap
        // gesture on this row would make SwiftUI hold the single tap above for the
        // whole double-click interval before it could rule a second click out —
        // half a second of nothing happening on every selection, which read as
        // the app being slow.
        .flipContextMenu {
            // The count is read when the menu opens rather than promised: a
            // layer drawn on one frame has no twins, and the menu says so
            // instead of offering a no-op.
            let span = model.frameSpan(of: model.linked(layer.id))
            return [
                .item("Rename", shortcut: "⌘R") {
                    // Keeps a linked selection intact, so renaming a layer that is
                    // selected across frames renames it in all of them — right-clicking
                    // the row you are already looking at should not narrow the reach.
                    if !model.selection.contains(layer.id) {
                        model.selection = [layer.id]
                        model.selectedNodes = []
                    }
                    model.beginRename(layer.id)
                },
                .separator,
                .item(span > 1 ? "Select in All \(span) Frames" : "Select in All Frames",
                      shortcut: "⌥⌘L", enabled: span > 1) {
                    model.selectLinked(layer.id)
                },
            ]
        }
    }

    // MARK: Dragging a row

    /// Takes the layout's measurements and works out every place the block could
    /// land. Nothing is edited here — the drag is one move, made when the hand
    /// comes up.
    private func beginDrag(of layer: Layer, at index: Int) {
        // A drag moves the *selection*. A row dragged from outside it becomes
        // the selection first — dragging one row while three others move would
        // be a surprise. A selection spread across several stacks is fine now:
        // the move pulls its layers out of wherever they are and puts them down
        // together, which is a definite answer even when "one place along" is
        // not.
        if !model.selection.contains(layer.id) {
            model.selection = [layer.id]
            model.selectedNodes = []
            anchor = layer.id
        }
        let list = rows
        // The block starts at its topmost row, which for a multiple selection is
        // not the row the hand went down on.
        let moving = movingRows(in: list)
        let origin = moving.min() ?? index
        let slots = dropSlots(in: list, moving: Set(moving))

        dragOrigin = origin
        dragMoving = Set(moving)
        dragSlots = slots
        // Anchored on the block's reference row, the same one its vertical
        // position is measured from — not on the row the hand happened to go
        // down on, which for a multiple selection can be a different depth.
        dragStartDepth = list.indices.contains(origin) ? list[origin].depth : 0
        dragging = layer.id
        dragDX = 0
        dragDY = 0
        // Read off the locals rather than the state just written to them.
        let here = Self.choose(slots, origin: origin, dx: 0, dy: 0,
                               startDepth: dragStartDepth, pitch: rowHeight + rowSpacing)
        dragStartSlot = here
        dragSlot = here
    }

    /// The drop. One move and one undo step, and neither if the block came back
    /// to where it started.
    private func endDrag() {
        if let slot = dragSlot, slot != dragStartSlot {
            model.commit()
            model.moveSelection(into: slot.path, fromTop: slot.ordinal)
        }
        dragging = nil
        dragDX = 0
        dragDY = 0
        dragMoving = []
        dragSlots = []
        dragSlot = nil
        dragStartSlot = nil
    }

    /// Every visible row the drag carries: the selected rows and, for a
    /// container among them that is open, the rows of what is inside it. A
    /// subtree runs until the next row that is no deeper than its root.
    private func movingRows(in list: [Row]) -> [Int] {
        var out: [Int] = []
        var i = 0
        while i < list.count {
            guard model.selection.contains(list[i].layer.id) else { i += 1; continue }
            let root = list[i].depth
            out.append(i)
            var j = i + 1
            while j < list.count, list[j].depth > root { out.append(j); j += 1 }
            i = j
        }
        return out
    }

    /// One place the block could be dropped: a stack, and a position in it.
    struct DropSlot: Equatable {
        /// The containers to descend to reach the stack, outermost first. Empty
        /// is the frame's own stack.
        var path: [UUID]
        /// Counted from the top of the panel's list, among that stack's members
        /// that are staying put.
        var ordinal: Int
        /// The indent the line draws at.
        var depth: Int
        /// How many steps right of the outermost option this is — what the
        /// sideways travel is measured against. Usually the same as `depth`, and
        /// deliberately not when a container's inside would otherwise share an
        /// indent with the stack that container sits in.
        var reach: Int
        /// Set when the target is a container itself rather than a gap: the
        /// block goes inside it, and the row is outlined rather than a line
        /// drawn. This is the only way into a group that is shut, and the only
        /// way into one that is empty — neither shows any rows to drop between.
        var onto: UUID?
        /// Which gap between rows this sits in — and, for an `onto`, the index
        /// of the row it outlines.
        var gap: Int
        var y: CGFloat
        var indent: CGFloat
    }

    /// Every gap between the rows, and at every gap every stack that gap could
    /// mean.
    ///
    /// A gap between two rows is not one place — it is as many places as there
    /// are stacks open at that point. The gap after the last child of a group is
    /// both "the end of the group" and "after the group, in whatever holds it",
    /// and after a deeply nested row it is one of those for every level. They
    /// are told apart by how far right the hand is, which is why each slot
    /// carries the indent it draws at: the line moves out and in with the depth
    /// it means.
    ///
    /// One step further right again is the container the gap sits *above*, if
    /// there is one — the block goes inside it. That case cannot be a line: it
    /// would draw at the same indent as the end of the group the line above it
    /// already means. It is the row outlined instead.
    private func dropSlots(in list: [Row], moving: Set<Int>) -> [DropSlot] {
        let pitch = rowHeight + rowSpacing
        // Nothing may be dropped inside itself.
        let carried = Set(moving.map { list[$0].layer.id })
        func clean(_ path: [UUID]) -> Bool { !path.contains(where: { carried.contains($0) }) }

        var out: [DropSlot] = []
        for gap in 0...list.count {
            let above = gap > 0 ? list[gap - 1] : nil
            let below = gap < list.count ? list[gap] : nil
            // A gap buried inside the block is not a place to put the block.
            if moving.contains(gap - 1), moving.contains(gap) { continue }

            let y = max(1, CGFloat(gap) * pitch - rowSpacing / 2)
            let lowest = below?.depth ?? 0
            var deepest = lowest
            if let above {
                deepest = max(deepest, above.depth)
                if isOpenContainer(above) { deepest = max(deepest, above.depth + 1) }
            }

            for depth in lowest...max(lowest, deepest) {
                guard let path = stackPath(depth: depth, above: above, below: below),
                      clean(path) else { continue }
                // How many of that stack's stayers are already above this gap.
                let ordinal = (0..<gap).filter { !moving.contains($0) && list[$0].path == path }.count
                out.append(DropSlot(path: path, ordinal: ordinal, depth: depth, reach: depth,
                                    onto: nil, gap: gap, y: y,
                                    indent: Self.lineIndent(depth)))
            }

            // Inside the row below, at the top of it.
            if let below, below.layer.hasChildren, !moving.contains(gap),
               clean(below.path + [below.layer.id]) {
                out.append(DropSlot(path: below.path + [below.layer.id], ordinal: 0,
                                    depth: below.depth + 1,
                                    reach: max(deepest, below.depth) + 1,
                                    onto: below.layer.id, gap: gap, y: y,
                                    indent: Self.lineIndent(below.depth + 1)))
            }
        }
        return out
    }

    /// Where a drop line starts, for the stack it means.
    ///
    /// Flush with the row fills at the top level and stepped in by one indent
    /// per level after that. Not the rows' *content* indent, which is 12 further
    /// in again: a line starting there would read as an indented item of its own
    /// rather than as the space between two rows.
    private static func lineIndent(_ depth: Int) -> CGFloat { 4 + CGFloat(depth) * 14 }

    private func isOpenContainer(_ row: Row) -> Bool {
        row.layer.hasChildren && expanded.contains(row.layer.id)
    }

    /// Which stack a given depth means at a given gap.
    ///
    /// Read off the row above wherever there is one — that is the stack being
    /// continued. One level deeper than an open container above means inside it,
    /// at the end. Everything shallower is an ancestor's stack, which is how a
    /// layer comes back *out* of a group: the gap after the last child is also
    /// the gap after the group.
    private func stackPath(depth: Int, above: Row?, below: Row?) -> [UUID]? {
        if let above {
            if isOpenContainer(above), depth == above.depth + 1 {
                return above.path + [above.layer.id]
            }
            if depth <= above.depth { return Array(above.path.prefix(depth)) }
        }
        if let below, depth == below.depth { return below.path }
        return above == nil && depth == 0 ? [] : nil
    }

    /// The slot the hand is asking for: the gap its top edge is nearest, and
    /// within that gap the one its sideways travel has reached.
    ///
    /// Depth is chosen by *how far the hand has moved*, not by where it is. The
    /// row was picked up somewhere along its width — usually over the name, four
    /// or five indents in — so an absolute reading would nest everything the
    /// moment it was lifted. A step per indent, out from where it started, is
    /// the same gesture every time whatever part of the row was grabbed.
    private static func choose(_ slots: [DropSlot], origin: Int, dx: CGFloat, dy: CGFloat,
                               startDepth: Int, pitch: CGFloat) -> DropSlot? {
        let top = CGFloat(origin) * pitch + dy
        let gap = Int((top / pitch).rounded())
        let wanted = startDepth + Int((dx / 14).rounded())
        let here = slots.filter { $0.gap == gap }
        // Past the ends of the list, or over a gap that had nothing to offer.
        guard !here.isEmpty else {
            return slots.min { abs($0.y - top) < abs($1.y - top) }
        }
        return here.min { abs($0.reach - wanted) < abs($1.reach - wanted) }
    }

    private func chooseSlot(dx: CGFloat, dy: CGFloat) -> DropSlot? {
        Self.choose(dragSlots, origin: dragOrigin, dx: dx, dy: dy,
                    startDepth: dragStartDepth, pitch: rowHeight + rowSpacing)
    }

    /// Empty names are floored to "Shape" by the model. Renaming to the same name
    /// is skipped so that opening the field and dismissing it costs no undo step.
    private func commitRename(_ layer: Layer) {
        if draft != layer.name { model.rename(layer.id, draft) }
        model.renamingLayer = nil
    }

    private func swatch(_ layer: Layer) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(layer.fill?.opaque ?? Color.clear)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(layer.stroke?.opaque ?? FlipTheme.edge,
                                  lineWidth: layer.stroke == nil ? 1 : 1.5)
            )
            .opacity(layer.visible ? 1 : 0.35)
    }
}
