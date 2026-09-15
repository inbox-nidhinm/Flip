import SwiftUI

/// What the panel is showing, worked out rather than chosen.
///
/// There was a rail of five icons here and you picked a section off it. The
/// rail is gone: the panel now shows what the tool in your hand and the thing
/// you have selected can actually be done to, which is nearly always what the
/// rail was being used to reach anyway. A brush has no use for boolean
/// operations and a cursor with nothing selected has no use for a fill.
///
/// Four of the nine are not about a mark at all. `onion` and `board` describe
/// the *paper* — the ghosts on either side of this frame, the size of the sheet
/// and what sits under it — so they come up with the cursor and the hand, the
/// two tools that move things around rather than make them. `playback` and
/// `export` describe the *document* — its rate, how it loops, what comes out of
/// it — so they sit at the foot of every context rather than appearing only
/// when nothing else does. Without that, changing the frame rate mid-brush
/// would mean putting the brush down.
private enum PanelGroup: String, CaseIterable, Identifiable {
    case select, paint, layer, boolean, path, onion, board, playback, export

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select:   return "Select"
        case .paint:    return "Colors"
        case .layer:    return "Layer"
        case .boolean:  return "Boolean"
        case .path:     return "Path"
        case .onion:    return "Onion skin"
        case .board:    return "Artboard"
        case .playback: return "Playback"
        case .export:   return "Export"
        }
    }

    /// Whether the heading folds its contents away.
    ///
    /// The paper and document groups do, and start folded. They are here so
    /// that changing the rate or the artboard's size does not mean putting the
    /// brush down — not because any of them is what you came to the panel for,
    /// and left open they are more than the panel's own height spent on
    /// settings nobody is looking at. The tool's own groups never fold: those
    /// *are* what the panel is for, and a fold on them would be one click
    /// between the hand and the work.
    var folds: Bool {
        switch self {
        case .onion, .board, .playback, .export: return true
        default:                                 return false
        }
    }
}

// MARK: - Panel

/// Whatever the tool in hand and the selection can be done to, stacked, the
/// full height of the panel.
///
/// No header: it named the tool, which the tray at the foot of the window
/// already shows lit. Nothing here explains itself in prose either — a control
/// that needs a sentence beside it is a control that has been named badly, and
/// the shortcuts card carries the keys.
struct ToolsPanel: View {
    @EnvironmentObject private var model: AppModel

    /// Shut on every launch, and remembered only for as long as the app is up.
    /// These are the two groups nobody opens the panel *for* — a rate that was
    /// left open a week ago is not a preference worth restoring, and the panel
    /// should come up quiet.
    @State private var onionOpen = false
    @State private var boardOpen = false
    @State private var playbackOpen = false
    @State private var exportOpen = false

    var body: some View {
        // No header. It named the tool in hand, which the tool tray at the foot
        // of the window already shows lit — and the groups below say what the
        // tool can do more usefully than its name does.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let showing = groups
                    ForEach(showing) { group in
                        // Nothing above the first one; the header's rule is
                        // already there.
                        if group != showing.first { PanelDivider().padding(.vertical, 2) }
                        heading(group)
                        if isOpen(group) { contents(of: group) }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What the tool in hand and the selection can be done to, in the order the
    /// hand reaches for them: what you are drawing with, then what you have
    /// drawn, then the paper it is on, then the document itself.
    private var groups: [PanelGroup] {
        var out: [PanelGroup] = []
        let hasLayers = !model.selection.isEmpty

        switch model.tool {
        case .select:
            // With nothing picked there is nothing to paint, and the panel drops
            // to the document's own settings.
            if hasLayers {
                out.append(.select)
                // A group has no paint of its own — its children keep theirs —
                // so a panel offering a fill for one would be offering an edit
                // that goes nowhere. Opacity and blend still apply: those act on
                // the group as a unit, which is the whole point of grouping.
                if model.selectionTakesPaint { out.append(.paint) }
                out.append(.layer)
                // Only where there is something for it to do. The operations
                // need two layers to work on, and Release needs a boolean —
                // shown at one selected layer the whole group sits dead, which
                // is a section of the panel spent saying no.
                if model.canBoolean || model.canRelease { out.append(.boolean) }
            }
        case .hand:
            // A way of moving the paper, not of marking it.
            break
        case .bone:
            // Makes no marks either — it moves what is already drawn. Its own
            // settings live in the popup the bottom bar raises, not here.
            break
        case .brush, .rect, .ellipse:
            // Fill, stroke and width here are the *next* mark as much as the
            // selected one, which is why they show with nothing selected.
            out += [.paint, .layer]
        case .bezier:
            out += [.paint, .layer]
        }

        // Points can be selected with the cursor as well as drawn with the pen,
        // and these three act on points rather than on the tool.
        if model.tool == .bezier || !model.selectedNodes.isEmpty { out.append(.path) }

        // The paper, between the drawing and the document. Only under the two
        // tools that make no marks: onion skin and the artboard are things you
        // set up and then work over, and with a brush in hand the rows you want
        // are the ones above these — pushing them down for settings you are not
        // reaching for mid-stroke.
        if model.tool == .select || model.tool == .hand || model.tool == .bone { out += [.onion, .board] }

        out += [.playback, .export]
        return out
    }

    /// A group's name — and, for the two that fold, the control that folds it.
    @ViewBuilder private func heading(_ group: PanelGroup) -> some View {
        if group.folds {
            Button {
                withAnimation(.easeOut(duration: 0.14)) { setOpen(group, !isOpen(group)) }
            } label: {
                HStack(spacing: 6) {
                    Text(group.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlipTheme.textPrimary)
                    Spacer(minLength: 0)
                    IconView(icon: .chevronRight, size: 12)
                        .foregroundStyle(FlipTheme.textTertiary)
                        .rotationEffect(.degrees(isOpen(group) ? 90 : 0))
                }
                // The whole line, not the word — a 12pt chevron is a small
                // target for something whose only job is to open a drawer.
                //
                // No hover. It was tried: a band behind a section heading reads
                // as a selected row rather than as a control answering the
                // pointer, and these sit against the panel's own rules, which
                // gave the fill two edges to disagree with. The chevron is what
                // says the line opens.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(group.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlipTheme.textPrimary)
        }
    }

    private func isOpen(_ group: PanelGroup) -> Bool {
        switch group {
        case .onion:    return onionOpen
        case .board:    return boardOpen
        case .playback: return playbackOpen
        case .export:   return exportOpen
        default:        return true
        }
    }

    private func setOpen(_ group: PanelGroup, _ open: Bool) {
        switch group {
        case .onion:    onionOpen = open
        case .board:    boardOpen = open
        case .playback: playbackOpen = open
        case .export:   exportOpen = open
        default:        break
        }
    }

    @ViewBuilder private func contents(of group: PanelGroup) -> some View {
        switch group {
        case .select:   selectAll
        case .paint:    paint
        case .layer:    layerProperties
        case .boolean:  boolean
        case .path:     path
        case .onion:    onion
        case .board:    board
        case .playback: playback
        case .export:   export
        }
    }

    // MARK: Select

    /// Selection spans frames, so recolouring a drawing that exists once per
    /// frame is one action rather than one per frame.
    @ViewBuilder private var selectAll: some View {
        HStack(spacing: 4) {
            PanelButton(title: "This frame", glyph: .icon(.thisFrame)) {
                model.selectAllInFrame()
            }
            PanelButton(title: "All frames", glyph: .icon(.allFrames)) {
                model.selectAllInAllFrames()
            }
        }
    }

    // MARK: Colors

    @ViewBuilder private var paint: some View {
        PaintRow(label: "Fill", color: $model.fillColor, enabled: $model.fillEnabled,
                 target: .fill) {
            model.setFill(model.fillEnabled ? model.fillColor : nil)
        }

        // Under Fill, because that is the only thing a swatch sets. At the foot
        // of the panel it sat below the stroke, the width and the opacity, and
        // read as belonging to all four.
        SwatchGrid(colors: RGBA.swatches,
                   custom: model.doc.swatches ?? [],
                   current: model.fillColor,
                   pick: { c in
                       model.fillEnabled = true
                       model.setFill(c)
                   },
                   add: true,
                   edit: { old, new in model.editSwatch(old, to: new) },
                   remove: { c in model.removeSwatch(c) })
        .padding(.top, 2)

        PanelDivider()

        PaintRow(label: "Stroke", color: $model.strokeColor, enabled: $model.strokeEnabled,
                 target: .stroke) {
            model.setStroke(model.strokeEnabled ? model.strokeColor : nil)
        }
        // Applied on every step, so the canvas answers under your hand — the
        // onion and reference sliders already did, by writing straight to the
        // document, and these two were the only ones that waited for the mouse
        // to come up. Undo is pushed once, as the drag begins.
        SliderRow(label: "Width", value: Binding(
            get: { Double(model.strokeWidth) },
            set: { model.setStrokeWidth(CGFloat($0)) }
        ), range: 0...24,
           onBegin: { model.beginSliderEdit() },
           onCommit: { model.endSliderEdit() })

        // What lays the line down, above how it wanders: the nib is a choice
        // about the mark itself, where the three below are adjustments to it.
        //
        // A menu rather than a row of segments. Five names across a 208pt panel
        // already truncated "Medium" to "Medi…", and the next brush added would
        // have had nowhere to go — but the real reason is that the names are not
        // the choice. A stroke of each says what Soft means; the word does not.
        MenuRow(label: "Nib", value: model.selectionNib.label,
                preview: NibPreview.image(model.selectionNib,
                                          tint: FlipTheme.textPrimary.rgba)) {
            let current = model.selectionNib
            return Nib.allCases.map { nib in
                MenuEntry.choice(nib.label,
                                 preview: NibPreview.image(nib, tint: FlipTheme.textPrimary.rgba),
                                 selected: nib == current) {
                    model.setNib(nib)
                }
            }
        }
        .onAppear { model.nib = model.selectionNib }
        .onChange(of: model.selection) { _, _ in model.nib = model.selectionNib }

        // Under the width, because these are the same question about the same
        // mark: how thick the line is, then how steadily it is drawn. They were
        // a group of their own and that was wrong — it put the hand holding the
        // pen in a different part of the panel from the pen.
        //
        // In this order because it is the order the three questions come in:
        // how many bumps, how big, how jagged. Boil is last because it is the
        // only one that asks about the frames rather than about the line.
        SliderRow(label: "Frequency", icon: .frequency, value: Binding(
            get: { model.wiggle.frequency },
            set: { var w = model.wiggle; w.frequency = $0; model.setWiggle(w) }
        ), range: 0...1, style: .percent, onBegin: { model.beginSliderEdit() },
           onCommit: { model.endSliderEdit() })

        SliderRow(label: "Wiggle", icon: .wiggle, value: Binding(
            get: { model.wiggle.amount },
            set: { var w = model.wiggle; w.amount = $0; model.setWiggle(w) }
        ), range: 0...1, style: .percent, onBegin: { model.beginSliderEdit() },
           onCommit: { model.endSliderEdit() })

        SliderRow(label: "Smoothen", icon: .smoothen, value: Binding(
            get: { model.wiggle.smoothen },
            set: { var w = model.wiggle; w.smoothen = $0; model.setWiggle(w) }
        ), range: 0...1, style: .percent, onBegin: { model.beginSliderEdit() },
           onCommit: { model.endSliderEdit() })

        // At zero every frame wanders identically and a held drawing is
        // perfectly still — which is the setting for texture rather than life,
        // and the reason this is a dial and not a switch.
        SliderRow(label: "Boil", icon: .boil, value: Binding(
            get: { model.wiggle.boil },
            set: { var w = model.wiggle; w.boil = $0; model.setWiggle(w) }
        ), range: 0...1, style: .percent, onBegin: { model.beginSliderEdit() },
           onCommit: { model.endSliderEdit() })
        // Same reason opacity does it: the dials read what is selected, so
        // picking a line shows the hand it was drawn with.
        .onAppear { model.wiggle = model.selectionWiggle }
        .onChange(of: model.selection) { _, _ in model.wiggle = model.selectionWiggle }
        .onChange(of: model.frameIndex) { _, _ in model.wiggle = model.selectionWiggle }
    }

    // MARK: Layer

    /// What acts on the whole layer rather than on the paint in it. Its own
    /// group for exactly that reason — opacity fades a layer as a unit, and a
    /// group as one thing rather than as its children, so a group at 40% does
    /// not show its own shapes through each other.
    @ViewBuilder private var layerProperties: some View {
        SliderRow(label: "Opacity", value: Binding(
            get: { model.opacity },
            set: { model.setOpacity($0) }
        ), range: 0...1, style: .percent, onBegin: { model.beginSliderEdit() },
           onCommit: { model.endSliderEdit() })
        // Unlike fill and stroke, which are the *next* thing you will draw as
        // much as the thing you have selected, opacity only ever means the
        // selection's — so the slider reads what you just picked rather than
        // whatever it was last dragged to.
        .onAppear { model.opacity = model.selectionOpacity }
        .onChange(of: model.selection) { _, _ in model.opacity = model.selectionOpacity }
        .onChange(of: model.frameIndex) { _, _ in model.opacity = model.selectionOpacity }

        // Under opacity, because it is the other half of the same question:
        // opacity says how much of the layer meets what is under it, and this
        // says how the two are mixed when they do. Both act on the layer as a
        // unit — a multiplied group meets the backdrop once rather than its
        // children multiplying with each other on the way down.
        MenuRow(label: "Blend",
                value: model.selectionBlend.label) {
            let current = model.selectionBlend
            return Blend.groups.enumerated().flatMap { i, group -> [MenuEntry] in
                // The modes fall into families — darkening, lightening,
                // contrast, and the ones that take a single component of the
                // colour. Sixteen unbroken lines is a list to read; six short
                // ones is a list to pick from.
                let rows = group.map { mode in
                    MenuEntry.item(mode.label, selected: mode == current) {
                        model.setBlend(mode)
                    }
                }
                return i == 0 ? rows : [.separator] + rows
            }
        }
    }

    // MARK: Boolean

    @ViewBuilder private var boolean: some View {
        HStack(spacing: 4) {
            ForEach(BoolOp.allCases, id: \.self) { op in
                BarButton(glyph: .icon(op.icon), disabled: !model.canBoolean) { model.makeBoolean(op) }
            }
        }

        if let layer = model.selectedLayersHere.first(where: { $0.isBoolean }), let op = layer.op {
            Picker("", selection: Binding(
                get: { op },
                set: { model.changeOp(layer.id, to: $0) }
            )) {
                ForEach(BoolOp.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .font(.system(size: 11))
        }

        PanelButton(title: "Release", glyph: .icon(.release),
                    disabled: !model.canRelease) {
            model.releaseBoolean()
        }
    }

    private func description(_ op: BoolOp) -> String {
        switch op {
        case .unite:     return "one shape covering both"
        case .subtract:  return "everything above cut out of the lowest layer"
        case .intersect: return "only where they all overlap"
        case .exclude:   return "everything except the overlap"
        }
    }

    // MARK: Path

    @ViewBuilder private var path: some View {
        PanelButton(title: "Join points", glyph: .icon(.link),
                    disabled: model.selectedNodes.count != 2) {
            let refs = Array(model.selectedNodes)
            model.join(refs[0], refs[1])
        }
        PanelButton(title: "Close path", glyph: .icon(.closePath),
                    disabled: !canClose) {
            if let ref = model.selectedNodes.first { model.closeSubpath(ref, pushUndo: true) }
        }
        PanelButton(title: "Delete point", glyph: .icon(.deletePoint),
                    disabled: model.selectedNodes.isEmpty) {
            model.deleteSelectedNodes()
        }
    }

    private var canClose: Bool {
        guard model.selectedNodes.count == 1, let ref = model.selectedNodes.first,
              let layer = LayerTree.find(ref.layer, in: model.frame.layers),
              let shape = layer.shape,
              shape.subpaths.indices.contains(ref.subpath) else { return false }
        let sp = shape.subpaths[ref.subpath]
        return !sp.closed && sp.anchors.count >= 3
    }

    // MARK: Playback

    @ViewBuilder private var playback: some View {
        SliderRow(label: "Rate", value: Binding(
            get: { model.doc.fps },
            set: { model.doc.fps = ($0).rounded() }
        ), range: 1...30, unit: " fps", onCommit: { model.retimeIfPlaying() })

        PanelDivider()

        SegmentRow(selection: Binding(get: { model.doc.mode },
                                      set: { model.doc.mode = $0 }),
                   options: PlaybackMode.allCases,
                   title: { $0.label })

        PanelDivider()

        ReadoutRow(label: "Duration", value: String(format: "%.2fs", model.doc.duration))
        ReadoutRow(label: "Frames", value: "\(model.doc.frames.count)")
    }

    // MARK: Export

    @ViewBuilder private var export: some View {
        PanelButton(title: "Animated SVG", glyph: .icon(.railExport)) {
            model.exportSVG()
        }
        PanelButton(title: "Animated GIF", glyph: .icon(.exportGIF)) {
            model.exportGIF()
        }
        // Under the two that write the whole document, because it is the one
        // that writes a single frame — the list goes from most to least.
        PanelButton(title: "Frame as PNG", glyph: .icon(.chooseRef)) {
            model.exportPNG()
        }

        PanelDivider()

        SliderRow(label: "GIF size", value: $model.gifScale, range: 0.1...1, style: .percent)
        ToggleRow(label: "Transparent", isOn: $model.exportTransparent)
        if model.exportTransparent {
            SliderRow(label: "Cutoff", value: $model.gifThreshold, range: 0.05...0.95, style: .percent)
        }

        PanelDivider()

        ReadoutRow(label: "GIF frame", value: "\(Int(model.gifPlan.pixelSize.width))×\(Int(model.gifPlan.pixelSize.height))")
        ReadoutRow(label: "GIF length", value: String(format: "%.2fs", model.gifPlan.estimatedDuration))
    }
}

// MARK: - Onion skin

/// Ghosts of the neighbouring frames. `Show` rather than the eye the card in
/// the frame strip carried: in the panel the switch stands in a column of
/// labelled rows, and the reference below it already asks the same question the
/// same way.
private extension ToolsPanel {
    @ViewBuilder var onion: some View {
        ToggleRow(label: "Show", isOn: $model.onionEnabled)

        PanelDivider()

        StepRow(label: "Before", value: $model.onionBack, range: 0...8)
        StepRow(label: "After", value: $model.onionForward, range: 0...8)

        PanelDivider()

        SliderRow(label: "Opacity", value: $model.onionOpacity, range: 0.05...0.9, style: .percent)
    }

    // MARK: Artboard

    /// Artboard and reference in one group. Both describe the paper rather than
    /// the drawing on it: the size is the exported viewBox, and the reference is
    /// a document-level guide that sits under every frame.
    @ViewBuilder var board: some View {
        HStack(spacing: 8) {
            UnitField(unit: "W", value: Binding(
                get: { model.doc.size.width },
                set: { model.doc.size.width = $0 }
            ))
            UnitField(unit: "H", value: Binding(
                get: { model.doc.size.height },
                set: { model.doc.size.height = $0 }
            ))
        }

        PanelDivider()

        Text("Ground")
            .font(.system(size: 11))
            .foregroundStyle(FlipTheme.textSecondary)
        HStack(spacing: 8) {
            ColorWell(color: Binding(
                get: { model.doc.background },
                set: { model.doc.background = $0 }
            ), target: .background)
            HexField(color: Binding(
                get: { model.doc.background },
                set: { model.doc.background = $0 }
            ))
        }

        PanelDivider()

        Text("Reference")
            .font(.system(size: 11))
            .foregroundStyle(FlipTheme.textSecondary)

        if let ref = model.doc.reference {
            ReadoutRow(label: ref.name, value: "\(Int(ref.pixelSize.width))×\(Int(ref.pixelSize.height))")
            ToggleRow(label: "Show", isOn: refBinding(\.visible, or: true))
            SliderRow(label: "Opacity", value: refBinding(\.opacity, or: 0.45),
                      range: 0.05...1, style: .percent)
            SliderRow(label: "Scale", value: Binding(
                get: { Double(model.doc.reference?.scale ?? 1) },
                set: { model.doc.reference?.scale = CGFloat($0) }
            ), range: 0.1...4, style: .percent)
            PanelButton(title: "Reposition", glyph: .icon(.reposition)) {
                model.beginReposition()
            }
            PanelButton(title: "Recentre", glyph: .icon(.recentre)) {
                model.recentreReference()
            }
            PanelButton(title: "Replace", glyph: .icon(.replaceRef)) { model.presentReferencePanel() }
            PanelButton(title: "Remove", glyph: .icon(.removeRef)) { model.clearReference() }
        } else {
            PanelButton(title: "Choose image", glyph: .icon(.chooseRef)) {
                model.presentReferencePanel()
            }
        }
    }

    func refBinding<T>(_ path: WritableKeyPath<Reference, T>, or fallback: T) -> Binding<T> {
        Binding(get: { model.doc.reference?[keyPath: path] ?? fallback },
                set: { if model.doc.reference != nil { model.doc.reference![keyPath: path] = $0 } })
    }
}
