import SwiftUI
import AppKit

// What the app opens onto the very first time, and nothing after that.
//
// A card on the canvas: the app's own panel down the left with a sentence and a
// button, artwork filling the right. Three pages — what the app is, where it
// keeps your work, and what it can do — and the button turns them like the
// leaves of a book.
//
// The first page's artwork is a `.flip` document played by `Render`, the same
// code that draws the artboard. It could have been a movie or an animated SVG
// in a web view, and either would have been a picture *of* the app rather than
// the app running. The first thing the onboarding shows is the thing itself.

struct Onboarding: View {
    @EnvironmentObject private var model: AppModel
    let dismiss: () -> Void

    @State private var page = 0
    /// Which of the five the last page is showing. It opens on the first, so
    /// there is always something on the right; clicking down the list changes
    /// what that is, and going straight for the button skips the whole thing.
    @State private var feature = Feature.allCases[0]
    /// Set when the folder page has actually been used, so the row can say so
    /// rather than the path silently changing under a line of instruction.
    @State private var folderChosen = false
    @State private var folderHover = false
    /// The feature whose plate is turning away, and how far it has turned.
    /// Nil at rest, which is when the artwork draws straight through with no
    /// filter behind it.
    @State private var curlFrom: Feature?
    @State private var curlProgress: Double = 0
    /// The feature row under the pointer.
    @State private var hovered: Feature?

    /// The leaf's angle. See `turn`.
    @State private var leaf: Double = 0
    @State private var turning = false

    private let card = CGSize(width: 760, height: 540)
    /// The artwork is 740×880 in every case, and the panel is the rest of the
    /// card — together they come out at the proportion the reference was drawn
    /// at.
    /// Wide enough for the longest of the five feature rows to sit on one line.
    /// "Select the same layer in all frames" is the one that sets it, and a row
    /// that had to truncate would be a row that could not say what it was.
    private let panelWidth: CGFloat = 290

    var body: some View {
        ZStack {
            // The app's own ground, grained like everything else, rather than a
            // scrim over the window: on a first launch there is nothing behind
            // this worth showing through, and a dimmed empty shelf reads as the
            // app having failed to load.
            FlipTheme.canvas
                .grained()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                panel
                artwork
                    .frame(width: card.width - panelWidth)
            }
            .frame(width: card.width, height: card.height)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(FlipTheme.panel)
                .grained()
                .clipShape(RoundedRectangle(cornerRadius: 12)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(FlipTheme.border, lineWidth: 1))
            // The leaf, hinged on its left edge like a page on a spine, with
            // enough perspective that the far edge foreshortens on the way over
            // instead of the whole card squashing sideways.
            .rotation3DEffect(.degrees(leaf), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.35)
            // Lifted while it is moving. A page that turns flat against the
            // ground reads as a slide; the shadow is what puts air under it.
            .shadow(color: .black.opacity(turning ? 0.65 : 0.5),
                    radius: turning ? 48 : 32,
                    x: turning ? -18 : 0, y: 12)
        }
        // Escape is the way out at any point. Not drawn as a control: three
        // pages is not a thing to need an escape hatch from, and a Skip sitting
        // beside the first one invites you to take it.
        .onExitCommand(perform: dismiss)
        // The curl on the last page costs its first frame dearly — kernels to
        // compile, plates to decode. Paid here, two pages ahead of anyone
        // reaching it, rather than on the click.
        .onAppear { PlateArt.warm() }
    }

    // MARK: The left-hand page

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .flipTitle(21)
                .foregroundStyle(FlipTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .id(title)

            Spacer(minLength: 20)

            switch page {
            case 1:  folderRow
            case 2:  featureList
            default: EmptyView()
            }

            HStack(spacing: 8) {
                cta(Self.pages[page].button, filled: true, action: advance)
                // Only where there is something to go back to. A disabled Back
                // on the first page is a control that exists to say no.
                if page > 0 {
                    cta("Back", filled: false, action: retreat)
                }
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: panelWidth, height: card.height, alignment: .topLeading)
        .background(FlipTheme.panel.grained())
        // Everything on the leaf is drawn on one side of it. Turned edge-on
        // there is nothing to read, which is what hides the change of page.
        .opacity(leaf.magnitude > 88 ? 0 : 1)
    }

    /// The pair at the foot of the page. The one that moves you on is the
    /// accent; the one that takes you back is a step up from the panel it sits
    /// on — enough to be a button, not enough to compete with the other.
    private func cta(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        OnboardingButton(label: label, filled: filled, action: action)
    }

    /// Where the drawings go. The path is the control — the row *is* the button,
    /// because a line of grey text beside a "Choose…" is two things saying one.
    private var folderRow: some View {
        Button {
            if model.chooseCreationsFolder() { folderChosen = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textTertiary)
                    .frame(width: 15)
                Text(Self.shortPath(AppModel.creationsFolder))
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bled the same way the feature rows are, so the two pages put
            // their one control's left edge in the same place.
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(folderHover ? FlipTheme.panelHover : FlipTheme.panelRaised)
                .padding(.horizontal, -8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // It sits on `panelRaised` already, so it lifts to the next rung rather
        // than to the one it is drawn on — the same step the tools tray takes.
        .onHover { folderHover = $0 }
        // Redrawn when a folder is picked: `creationsFolder` is read from
        // defaults rather than published, so nothing else would notice.
        .id(folderChosen)
    }

    /// The five things the app does. Clicking one changes the artwork beside it
    /// and the sentence above it; ignoring them entirely and pressing the button
    /// is a perfectly good way through.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Feature.allCases) { item in
                Button {
                    select(item)
                } label: {
                    HStack(spacing: 8) {
                        IconView(icon: item.icon, size: 15)
                        Text(item.label)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(item == feature ? FlipTheme.textPrimary
                                                     : FlipTheme.textSecondary)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The row's *content* starts where the button below it
                    // starts, and the lit fill bleeds out past it rather than
                    // pushing it in. Padding the content instead would step the
                    // icons in from the button and leave the column's left edge
                    // saying two different things.
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(item == feature ? FlipTheme.rowSelected
                              : hovered == item ? FlipTheme.rowHover : .clear)
                        .padding(.horizontal, -8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Guarded on identity, the same way every other list in the app
                // is: running down the five delivers the arriving row's `true`
                // before the leaving row's `false`, and an unguarded clear would
                // wipe the row the pointer had just reached.
                .onHover { inside in
                    if inside { hovered = item }
                    else if hovered == item { hovered = nil }
                }
            }
        }
    }

    // MARK: The right-hand page

    @ViewBuilder private var artwork: some View {
        ZStack {
            switch page {
            case 0:  HeroReel()
            // The plate carries the folder but not its name — the name is
            // whichever folder was chosen, so the app writes it rather than the
            // artwork claiming one.
            case 1:  Plate(name: "folder",
                           caption: AppModel.creationsFolder.lastPathComponent)
                        .id(folderChosen)
            // Always the same view, curling or not. Swapping between a plain
            // plate and a curling one would change the view's identity halfway
            // through the turn, and SwiftUI would cross-fade the handoff.
            default: PageCurlPlate(from: curlFrom?.plate, to: feature.plate,
                                   progress: curlProgress)
            }
        }
        // The same grain the panels take, so the artwork is the same material as
        // the card holding it rather than a picture pasted onto it. Over its own
        // light ground it has to be blended rather than laid on — see
        // `grainedOnLight`.
        .grainedOnLight()
        .clipped()
        .opacity(leaf.magnitude > 88 ? 0 : 1)
    }

    /// Picking a feature turns its plate like a leaf.
    ///
    /// The same gesture the card itself makes when the page changes, at the
    /// scale of the artwork rather than the whole page — so the two reads agree
    /// about what this app does to paper.
    private func select(_ item: Feature) {
        guard item != feature else { return }
        // Mid-turn, the new choice takes effect without a second curl rather
        // than queueing one: clicking down the list quickly should keep up with
        // the hand, not play out five animations after it has stopped.
        guard curlFrom == nil else {
            withAnimation(.easeOut(duration: 0.16)) { feature = item }
            return
        }
        let leaving = feature
        curlFrom = leaving
        curlProgress = 0
        // The sentence above changes on its own timing; the plate takes longer,
        // because a turn read at the speed of a cross-fade is just a flicker.
        withAnimation(.easeOut(duration: 0.16)) { feature = item }
        withAnimation(.easeInOut(duration: 0.62)) { curlProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            // Cleared without animating: at 1 the filter is already showing the
            // target exactly, so there is nothing left to move.
            curlFrom = nil
            curlProgress = 0
        }
    }

    // MARK: Turning the page

    /// A leaf lifting off the right edge, sweeping to the spine, and the next
    /// one coming down onto it — the turn a book makes.
    ///
    /// One hinge and two halves rather than a continuous 180: the card carries
    /// its content on one face, so past edge-on it would show that face
    /// mirrored. The swap happens at 90, where there is nothing to see.
    private func advance() {
        guard !turning else { return }
        guard page + 1 < Self.pages.count else { dismiss(); return }
        turn(to: page + 1, forwards: true)
    }

    private func retreat() {
        guard !turning, page > 0 else { return }
        turn(to: page - 1, forwards: false)
    }

    /// The leaf lifts, the page changes while it is edge-on, and it comes down
    /// again from the other side. Backwards is the same move with the two sides
    /// swapped, so a page turned by mistake comes back the way it went.
    private func turn(to next: Int, forwards: Bool) {
        turning = true
        let away: Double = forwards ? 90 : -90
        withAnimation(.easeIn(duration: 0.22)) { leaf = away }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            page = next
            // Set without animating, so the leaf arrives from the far side
            // rather than unwinding through the face it has just hidden.
            leaf = -away
            withAnimation(.easeOut(duration: 0.26)) { leaf = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { turning = false }
        }
    }

    // MARK: The pages

    private var title: String {
        page == Self.pages.count - 1 ? feature.title : Self.pages[page].text
    }

    private static let pages: [(text: String, button: String)] = [
        ("re-Flip, a frame by frame vector animation tool with bones in it.", "Flip over"),
        ("Select a folder to autosave your files.", "Flip again"),
        // The last page's sentence comes from whichever feature is showing.
        ("", "Start flipping"),
    ]

    enum Feature: String, CaseIterable, Identifiable {
        case connect, layers, autosave, shortcuts, svg

        var id: String { rawValue }

        var label: String {
            switch self {
            case .connect:   return "Shapes close by themselves"
            case .layers:    return "Select the same layer in all frames"
            case .autosave:  return "Auto saves your every move"
            case .shortcuts: return "Easy shortcuts"
            case .svg:       return "SVG animation export"
            }
        }

        var title: String {
            switch self {
            case .connect:
                return "Draw freely and get closed shapes with start and end points connecting automatically."
            case .layers:
                return "Apply properties to a single layer or all layers across frames in one go."
            case .autosave:
                return "You can forget to save your files. Flip doesn't."
            case .shortcuts:
                return "All shortcuts on hand to help you Flip faster."
            case .svg:
                return "Export your animation in SVG to retain resolution when scaled up."
            }
        }

        var icon: Icon {
            switch self {
            case .connect:   return .featureConnect
            case .layers:    return .featureLayers
            case .autosave:  return .featureAutosave
            case .shortcuts: return .featureShortcuts
            case .svg:       return .featureSVG
            }
        }

        var plate: String {
            switch self {
            case .connect:   return "connect"
            case .layers:    return "layers"
            case .autosave:  return "autosave"
            case .shortcuts: return "shortcuts"
            case .svg:       return "svg"
            }
        }
    }

    /// `~/Documents/Flip Creations` rather than the whole way from the root —
    /// the part that is the same for everyone says nothing.
    private static func shortPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Artwork

/// One of the bundled plates, filling its side of the card.
private struct Plate: View {
    let name: String
    /// Written under the artwork, where the plate leaves room for it.
    var caption: String?

    /// The plates are drawn on this grid, and `captionCentre` is where the gap
    /// under the folder falls on it — measured off the artwork rather than
    /// guessed, so the line sits where the picture was drawn to leave room.
    private static let grid = CGSize(width: 740, height: 880)
    private static let captionCentre: CGFloat = 637

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = Self.load(name) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    FlipTheme.panelRaised
                }

                if let caption {
                    // Placed in the plate's own coordinates and carried through
                    // the same fill the image takes, so it stays under the
                    // folder whatever shape the card is.
                    let scale = max(proxy.size.width / Self.grid.width,
                                    proxy.size.height / Self.grid.height)
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 16)
                        .offset(y: (Self.captionCentre - Self.grid.height / 2) * scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .transition(.opacity)
    }

    /// Held for the session. The plates are 740×880 and there are six of them;
    /// decoding one again every time the page turns back is work for nothing.
    private static var cache: [String: NSImage] = [:]

    private static func load(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png",
                                          subdirectory: "Onboarding")
                     ?? Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// A bundled `.flip` document, played by the app's renderer.
///
/// Rendered to a bitmap per frame once, off the main thread, and then flipped
/// between. Drawing the document live on every tick would mean 185 layers of
/// path work twelve times a second behind a card the user is reading — the
/// frames never change, so they are drawn once and kept.
private struct HeroReel: View {
    @StateObject private var reel = Reel()

    var body: some View {
        ZStack {
            // The artboard's own paper, so the panel's edge does not sit against
            // a hole while the first render is still going.
            reel.paper
            if let image = reel.image {
                Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: reel.image == nil)
        .onAppear { reel.start() }
        .onDisappear { reel.stop() }
    }

    @MainActor
    final class Reel: ObservableObject {
        @Published var image: CGImage?
        @Published var paper: Color = FlipTheme.panel

        private var frames: [CGImage] = []
        /// The document's own play order, so a document saved as a bounce
        /// bounces here too rather than being re-timed by the thing showing it.
        private var order: [Int] = []
        private var step = 0
        private var timer: Timer?
        private var fps: Double = 12
        private var loaded = false

        func start() {
            guard !loaded else { run(); return }
            loaded = true
            Task.detached(priority: .userInitiated) {
                guard let url = Bundle.module.url(forResource: "hero", withExtension: "flip",
                                                  subdirectory: "Onboarding")
                              ?? Bundle.module.url(forResource: "hero", withExtension: "flip"),
                      let data = try? Data(contentsOf: url),
                      let doc = try? JSONDecoder().decode(Document.self, from: data)
                else { return }

                // Two-to-one, which is what every display this runs on is, and
                // the card's own size — the drawing is never shown larger, so
                // there is nothing to gain from rendering it larger.
                let size = CGSize(width: 470 * 2, height: 540 * 2)
                let images = doc.frames.compactMap {
                    Render.raster($0, doc: doc, pixelSize: size, background: doc.background)
                }
                let order = doc.playOrder
                let rate = doc.fps
                let paper = doc.background.color
                await MainActor.run { [images, order, rate, paper] in
                    guard images.count == doc.frames.count else { return }
                    self.frames = images
                    self.order = order
                    self.fps = rate
                    self.paper = paper
                    self.image = images[order.first ?? 0]
                    self.run()
                }
            }
        }

        private func run() {
            guard frames.count > 1, !order.isEmpty else { return }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / max(fps, 1), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.frames.isEmpty else { return }
                    self.step = (self.step + 1) % self.order.count
                    self.image = self.frames[self.order[self.step]]
                }
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }
    }
}


/// One of the pair at the foot of an onboarding page.
///
/// A view rather than a method on the card, because it holds a hover state and
/// there are two of them on screen at once — a method could not tell one from
/// the other. The filled one lightens; the plain one takes the next rung of the
/// panel ramp, which is what every other control on a raised ground does.
private struct OnboardingButton: View {
    let label: String
    let filled: Bool
    let action: () -> Void

    @State private var hovering = false

    private var fill: Color {
        if filled { return hovering ? FlipTheme.accentHover : FlipTheme.accent }
        return hovering ? FlipTheme.panelHover : FlipTheme.panelRaised
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? .white : FlipTheme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
