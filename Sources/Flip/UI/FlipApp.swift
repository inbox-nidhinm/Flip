import SwiftUI
import AppKit

@main
struct FlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Flip", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
                .preferredColorScheme(.dark)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1440, height: 920)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { model.newDocument(); model.showingHome = false }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Home") { model.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Open") { model.presentOpen() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As") { model.save(as: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export Animated SVG") { model.exportSVG() }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Export Animated GIF") { model.exportGIF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { model.cutSelection() }
                    .keyboardShortcut("x", modifiers: .command)
                    .disabled(!model.canCopy)
                Button("Copy") { model.copySelection() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(!model.canCopy)
                Button("Paste in Place") { model.paste() }
                    .keyboardShortcut("v", modifiers: .command)
                    .disabled(!model.canPaste)
                Button("Paste into All Frames") { model.pasteIntoAllFrames() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                    .disabled(!model.canPaste)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Select All in Frame") { model.selectAllInFrame() }
                    .keyboardShortcut("a", modifiers: .command)
                Button("Select All in All Frames") { model.selectAllInAllFrames() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                // The same *one* layer everywhere, rather than everything
                // everywhere: ⌥⌘L, matching the ⌥-click on a layers-panel row.
                Button("Select in All Frames") { model.selectLinkedFromSelection() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                    .disabled(!model.canSelectLinked)
                Button("Deselect All  (esc)") { model.deselectAll() }
                    .disabled(model.selection.isEmpty)
                Divider()
                // Bare R is the rectangle tool, so rename takes the ⌘ pair. The
                // canvas hands every ⌘ keystroke to the responder chain, so this
                // is reachable while the canvas has the keyboard.
                Button("Rename Layer") { model.beginRenameSelection() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.canRename)
                Divider()
                // A plain group, not a boolean: it does nothing to what is inside
                // it, which is the point — it is how thirty shapes become four
                // things you can navigate.
                Button("Group") { model.groupSelection() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(!model.canGroup)
                Button("Ungroup") { model.ungroupSelection() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!model.canUngroup)
                Divider()
                // Bare `[` and `]` are handled by the canvas rather than declared
                // here, so they cannot fire while a rename field has the keyboard
                // — the same reason the frame keys are not declared either.
                Button("Bring to Front  ]") { model.moveSelectionToEnd(front: true) }
                    .disabled(!model.canReorder)
                Button("Send to Back  [") { model.moveSelectionToEnd(front: false) }
                    .disabled(!model.canReorder)
                Button("Bring Forward") { model.reorderSelection(up: true) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!model.canReorder)
                Button("Send Backward") { model.reorderSelection(up: false) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canReorder)
            }
            CommandMenu("Frame") {
                Button("Duplicate Frame") { model.addFrame(duplicate: true) }
                    .keyboardShortcut("d", modifiers: .command)
                // Bare `N` only. It had ⇧⌘D as well, which was a second key for
                // one action and the only thing in the app with two.
                Button("New Blank Frame  N") { model.addFrame(duplicate: false) }
                Button("Delete Frame") { model.deleteFrame() }
                    .disabled(model.doc.frames.count < 2)
                Divider()
                // Bare , and . are handled by the canvas rather than declared
                // here, so they cannot fire while a rename field has the keyboard.
                Button("Previous Frame  <") { model.stop(); model.step(-1) }
                Button("Next Frame  >") { model.stop(); model.step(1) }
                Divider()
                // Labelled rather than declared, for the reason in the canvas's
                // `keyDown`: a comma key equivalent does not survive SwiftUI.
                Button("Move Frame Left  ⇧⌘<") { model.moveFrame(by: -1) }
                Button("Move Frame Right  ⇧⌘>") { model.moveFrame(by: 1) }
            }
            CommandGroup(after: .toolbar) {
                // The title bar used to carry these. Nothing else does now, so
                // without them a hidden panel could not be brought back.
                Button(model.showLayers ? "Hide Layers" : "Show Layers") {
                    model.showLayers.toggle()
                }
                .keyboardShortcut("1", modifiers: .command)
                Button(model.showTools ? "Hide Tools" : "Show Tools") {
                    model.showTools.toggle()
                }
                .keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Fit to Window") {
                    NotificationCenter.default.post(name: .flipFitToWindow, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            // Replacing rather than adding: the group's own item is a "Flip
            // Help" that opens a help book this app does not have.
            //
            // The shortcuts legend lives here rather than under View, where it
            // sat because it is a thing you show and hide. It is a list of what
            // the app can do, which is what someone opens a Help menu looking
            // for — and it is the only other thing in this one, so a menu that
            // held one item now holds the two that answer the same question.
            CommandGroup(replacing: .help) {
                Button(model.showShortcuts ? "Hide Shortcuts" : "Shortcuts") {
                    model.showShortcuts.toggle()
                }
                .keyboardShortcut("/", modifiers: .command)
                Divider()
                Button("Show Onboarding Again") { model.showOnboarding = true }
            }
        }
    }
}

/// A Swift-package executable is not a real app bundle, so it launches without
/// focus and behind other windows. This drags it back to the front.
/// Where the close, minimise and zoom buttons sit.
///
/// AppKit puts them against the top-left of the window. This app has no title
/// bar of its own, so on the home screen that is *outside* the sidebar panel and
/// on the artboard it is hard against the top bar's edge — either way they read
/// as sitting on nothing. Moved in by the panel's own inset plus its own
/// padding, they land where any other control in that panel would.
///
/// Reapplied on resize and on becoming key, because AppKit lays them out again
/// on both and would otherwise put them straight back.
@MainActor
enum TrafficLights {
    /// `floatInset` + the padding every panel gives its contents.
    static let origin = CGPoint(x: 20, y: 20)

    static func place() {
        for window in NSApplication.shared.windows { place(in: window) }
    }

    static func place(in window: NSWindow) {
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = kinds.compactMap { window.standardWindowButton($0) }
        guard let close = buttons.first, let bar = close.superview else { return }
        // The titlebar view is not flipped, so "down the screen" is a smaller y.
        let wantedMaxY = bar.frame.height - origin.y
        let dy = wantedMaxY - close.frame.maxY
        let dx = origin.x - close.frame.minX
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        for b in buttons {
            b.setFrameOrigin(CGPoint(x: b.frame.minX + dx, y: b.frame.minY + dy))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // The window is not up yet at this point, and AppKit lays the buttons
        // out again after it is — so this waits a turn rather than running now
        // and being undone.
        DispatchQueue.main.async { TrafficLights.place() }
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TrafficLights.place() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Autosave coalesces changes into one write a second or so, so quitting can
    /// land inside that window. Flush on the way out, or the last second of work
    /// is the one thing the feature loses.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.current?.flushAutosave() }
    }

    /// Double-clicking a `.flip` in the Finder, or `open -a Flip file.flip`, lands
    /// here. The Info.plist advertises the document type, so Launch Services hands
    /// the file over whether or not the app does anything with it — without this
    /// the app opened its own empty document and looked like it had lost the file.
    func application(_ application: NSApplication, open urls: [URL]) {
        let flips = urls.filter { $0.pathExtension.lowercased() == "flip" }
        guard let url = flips.first ?? urls.first else { return }
        MainActor.assumeIsolated {
            if let model = AppModel.current {
                model.loadDocument(from: url)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } else {
                // Arrived before the scene built its model; `AppModel.init` drains it.
                AppModel.pendingOpen = url
            }
        }
    }
}
