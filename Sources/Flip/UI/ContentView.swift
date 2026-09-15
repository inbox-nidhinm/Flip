import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    /// One per window. Held here rather than inside either screen, because the
    /// menu has to be drawn above both and outlive the row that opened it.
    @StateObject private var menus = MenuHost()

    var body: some View {
        ZStack {
            Group {
                if model.showingHome { HomeView() } else { editor }
            }
            // Last, so it is over the panels, the shelf and the shortcuts card
            // alike. Draws nothing until a menu is up.
            MenuLayer()

            // Over everything, including the menu layer: on a first run this is
            // the whole of what the app is showing, and there is nothing behind
            // it that should be reachable.
            if model.showOnboarding {
                Onboarding(dismiss: model.endOnboarding)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.showOnboarding)
        .environmentObject(menus)
        // A menu belongs to the screen it was opened on. Leaving the editor for
        // the shelf with one still up would leave it pointing at a row that is
        // no longer there.
        .onChange(of: model.showingHome) { _, _ in menus.dismiss() }
        .tint(FlipTheme.accent)
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// No title bar. The file's name, the folder it is in and the traffic
    /// lights all live in the left panel now, so a strip across the top would be
    /// an empty rule over the artboard.
    private var editor: some View {
        ZStack(alignment: .bottom) {
            // The panels float over the canvas rather than dividing the window
            // between them, so the artboard runs the full width underneath and
            // hiding a panel gives that space straight back. `fitToWindow` knows
            // the insets, so a fitted artboard still lands clear of them.
                CanvasView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Centred on the *window*, so it stays put when a panel is
                // toggled — but inset by the wider of the two gutters on both
                // sides, or its ends slide under a panel. Insetting each side by
                // its own gutter would keep it clear too, and did, but it sat
                // off-centre by half the difference between them.
                //
                // Collapsible spacers rather than fixed padding, because padding
                // is a *floor*: it made the strip demand its own width plus both
                // gutters — 1097pt — and below that the ZStack grew past the
                // window to fit it, so everything centred inside, the panels
                // included, spilled out both edges. As spacers the gutters are a
                // ceiling instead: full when there is room, shrinking evenly when
                // there is not, and the strip stays centred either way.
                HStack(alignment: .top, spacing: 0) {
                    if model.showLayers {
                        LayersPanel()
                            .frame(width: FlipTheme.panelWidth)
                            .frame(maxHeight: .infinity)
                            .floatingPanel()
                            .dismissesTransients(model)
                    }

                    Spacer(minLength: FlipTheme.floatGap)

                    if model.showTools {
                        ToolsPanel()
                            .frame(width: FlipTheme.panelWidth)
                            .frame(maxHeight: .infinity)
                            .floatingPanel()
                            .dismissesTransients(model)
                    }
                }
                .padding(FlipTheme.floatInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Centred on the *window*, so it stays put when a panel is
                // toggled — but inset by the wider of the two gutters on both
                // sides, or its ends slide under a panel. Insetting each side by
                // its own gutter would keep it clear too, and did, but it sat
                // off-centre by half the difference between them.
                //
                // Collapsible spacers rather than fixed padding, because padding
                // is a *floor*: it made the strip demand its own width plus both
                // gutters — 1097pt — and below that the ZStack grew past the
                // window to fit it, so everything centred inside, the panels
                // included, spilled out both edges. As spacers the gutters are a
                // ceiling instead: full when there is room, shrinking evenly when
                // there is not, and the strip stays centred either way.
                //
                // Over the panels rather than under them: what it raises is a
                // popup, and a popup that a panel could cover is a popup with a
                // corner missing.
                HStack(spacing: 0) {
                    Spacer(minLength: 0).frame(maxWidth: max(leftGutter, rightGutter))
                    FrameStrip()
                    Spacer(minLength: 0).frame(maxWidth: max(leftGutter, rightGutter))
                }

                // Last in the stack, so it is over the panels as well as the
                // canvas, and centred on the window: it is a thing you open,
                // read and shut, so for the moment it is up it does not have to
                // keep clear of anything.
                if model.showShortcuts {
                    ShortcutsCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // The colour card. Outside every panel, because a panel clips its
            // contents and this has to stand beside one.
            .overlayPreferenceValue(PaintAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if let target = model.picking {
                        // No backdrop. There was a full-window `Color.clear`
                        // here to catch the click that shuts the card, and it
                        // was the whole reason picking a colour and drawing took
                        // two goes: a SwiftUI shape's gesture recogniser lives on
                        // the hosting view and gets the press before the canvas's
                        // `mouseDown` ever runs, so the stroke neither dismissed
                        // the card nor drew. The canvas dismisses it itself now,
                        // and the panels each catch their own — see
                        // `dismissesTransients`.
                        PaintCard(color: pickerBinding(target))
                            .offset(x: cardX(in: proxy), y: cardY(in: proxy, anchor: anchor))
                    }
                }
            }
        .background(FlipTheme.canvas)
    }

    // MARK: Colour card

    /// Hard against the left of the tools panel, one gap clear of it — the same
    /// gap the panels keep from each other, so the card reads as one more
    /// floating thing rather than as something stuck to the panel.
    private func cardX(in proxy: GeometryProxy) -> CGFloat {
        let panelLeft = proxy.size.width - FlipTheme.floatInset - FlipTheme.panelWidth
        return max(panelLeft - FlipTheme.floatGap - PaintCard.width, FlipTheme.floatInset)
    }

    /// Level with the control that opened it, pushed back inside the window
    /// when that would hang the card off the bottom — which the swatch grid,
    /// two thirds of the way down the panel, otherwise does every time.
    private func cardY(in proxy: GeometryProxy, anchor: SwiftUI.Anchor<CGRect>?) -> CGFloat {
        let wanted = anchor.map { proxy[$0].minY }
            ?? (proxy.size.height - PaintCard.height) / 2
        return min(max(wanted, 0), max(proxy.size.height - PaintCard.height, 0))
    }

    /// Fill and stroke write straight through to the document, the way the
    /// system panel did. A swatch is held in `pickerDraft` until the card
    /// shuts — see `AppModel.endPicking`.
    private func pickerBinding(_ target: PaintTarget) -> Binding<RGBA> {
        switch target {
        case .fill:
            return Binding(get: { model.fillColor },
                           set: { model.fillColor = $0
                                  model.setFill(model.fillEnabled ? $0 : nil) })
        case .stroke:
            return Binding(get: { model.strokeColor },
                           set: { model.strokeColor = $0
                                  model.setStroke(model.strokeEnabled ? $0 : nil) })
        case .background:
            return Binding(get: { model.doc.background },
                           set: { model.doc.background = $0 })
        case .swatch, .newSwatch:
            return Binding(get: { model.pickerDraft },
                           set: { model.pickerDraft = $0 })
        }
    }

    /// How much of each side the floating panels are covering.
    private var leftGutter: CGFloat {
        model.showLayers
            ? FlipTheme.floatInset + FlipTheme.panelWidth + FlipTheme.floatGap
            : FlipTheme.floatInset
    }

    private var rightGutter: CGFloat {
        // The rail used to stand between the panel and the canvas and had to be
        // counted here too. It is gone; the panel is the whole of that side now.
        model.showTools
            ? FlipTheme.floatInset + FlipTheme.panelWidth + FlipTheme.floatGap
            : FlipTheme.floatInset
    }

    private var title: String {
        if let note = model.statusNote { return note }
        return "\(model.documentName)  ·  frame \(model.frameIndex + 1) of \(model.doc.frames.count)"
    }
}

// MARK: - Dismissing what is raised

extension View {
    /// Makes a click anywhere on this view put away whatever is raised — a
    /// colour card, one of the frame strip's popups — instead of reaching the
    /// view's own controls.
    ///
    /// Only the panels take this. The canvas does the same job from inside its
    /// own `mouseDown`, where it can dismiss *and* still draw; a SwiftUI catcher
    /// laid over the canvas cannot, because its gesture recogniser takes the
    /// press and the canvas never sees it. And the frame strip is deliberately
    /// left out: it is what raises the popups, so a catcher over it would make
    /// them impossible to use.
    func dismissesTransients(_ model: AppModel) -> some View {
        overlay {
            if model.hasTransient {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.dismissTransients() }
            }
        }
    }
}
