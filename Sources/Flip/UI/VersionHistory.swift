import SwiftUI

/// What the app has been, newest first.
///
/// Kept here rather than in a file on disk: it is a fixed list that ships with
/// the binary and never changes at runtime, so a bundle resource would be a
/// file to load, a parse to get wrong, and a failure case to handle, for a
/// value the compiler can hold as well.
///
/// ## What goes in it
///
/// **Features only.** A line ships if the app can now do something it could not
/// do before. One line each, nothing past about a hundred characters.
///
/// A cursor, a hotkey, a rearrangement, a rewrite or a fault fixed before
/// anyone met it is *not* a feature, however much work it was. Those go to
/// `docs/build-log.md`, which is not shipped, has no limit, and is the complete
/// record — this list is a small fraction of it.
///
/// The test, applied twice over: would someone using the app notice, and would
/// they call it a thing the app now does? Sixteen lines to say that strokes can
/// wobble is a developer's diary, and so is a build called "Drag off a copy"
/// that is really a cursor and a shortcut.
///
/// ## Builds and versions
///
/// A **version** is a day's work that produced at least one feature. A day that
/// produced none is not a version — it is in the log and nowhere else.
/// A **build** is a named cluster of versions, and there should be very few:
/// one per thing the app fundamentally is or gained.
///
/// The number is `v0.0.<build>.<version>`. Adding a version to the newest build
/// moves the last digit; starting a build moves the one before it. The first
/// two are held at zero until the app is said to have earned otherwise.
///
/// Put the new entry at the *top*, of `builds` or of a build's `versions`.
/// Nothing else needs touching: the numbers are counted off the arrays, so the
/// newest is always the highest and nothing is renumbered.
enum VersionHistory {
    /// The newest version, derived, so it cannot disagree with the list under it.
    ///
    /// `make-app.sh` writes the same value into the plist by hand — it composes
    /// the Info.plist itself and has no way to read Swift, so that is the one
    /// place this has to be repeated. Change it there too.
    static var version: String {
        guard let newest = builds.first else { return "0.0.0.0" }
        return "0.0.\(builds.count).\(newest.versions.count)"
    }

    /// A named cluster of versions.
    struct Build: Identifiable {
        let title: String
        /// Newest first.
        let versions: [Version]
        var id: String { title }
    }

    /// One day's changes.
    struct Version: Identifiable {
        let date: String
        let changes: [String]
        var id: String { date + (changes.first ?? "") }
    }

    /// Counted from the bottom, so a new entry at the top numbers itself.
    static func number(of build: Build) -> Int {
        guard let i = builds.firstIndex(where: { $0.id == build.id }) else { return 0 }
        return builds.count - i
    }

    /// The full `0.0.b.v` for one version of one build.
    static func number(of version: Version, in build: Build) -> String {
        guard let i = build.versions.firstIndex(where: { $0.id == version.id }) else { return "" }
        return "0.0.\(number(of: build)).\(build.versions.count - i)"
    }

    static let builds: [Build] = [
        .init(title: "Pencil", versions: [
            .init(date: "15 September", changes: [
                "A pencil nib under Stroke, in four grades — the line keeps its own colour and width",
                "The mark is a shape, so it exports to SVG and stays crisp at any zoom",
                "One sheet of paper under the drawing: strokes that cross meet the same grain",
            ]),
        ]),
        .init(title: "Dynamic strokes", versions: [
            .init(date: "15 September", changes: [
                "Lines can wander off the path they were drawn on, for a hand-drawn edge",
                "Boil remakes that wander on every frame, so a held drawing breathes",
                "Four dials under Stroke: Frequency, Wiggle, Smoothen and Boil",
            ]),
        ]),
        .init(title: "Bones", versions: [
            .init(date: "15 September", changes: [
                "Rig a grouped drawing, and the whole group follows its armature",
            ]),
            .init(date: "7 September", changes: [
                "A bone tool that makes no marks: it moves what is already drawn",
                "Place bones down a limb, then pose them and the drawing follows",
                "IK rearranges three bones up the chain; FK turns the one you took hold of",
                "The drawing is never written to, so a pose can always be undone or reset",
            ]),
        ]),
        .init(title: "The first build", versions: [
            .init(date: "6 September", changes: [
                "Export the frame you are on as a PNG",
            ]),
            .init(date: "5 September", changes: [
                "A first run that hands the app over rather than explaining it",
                "The panel shows what the tool in hand and the selection can actually be used on",
                "Blend modes, under opacity",
            ]),
            .init(date: "4 September", changes: [
                "A home shelf: recent projects with thumbnails, folders, rename, delete and move",
                "Autosave, with no dialog and no asking",
                "The app's own colour picker, and a palette each document can add to",
                "Group layers, and a hand tool to move the paper under them",
                "Every shortcut on one card",
            ]),
            .init(date: "2 September", changes: [
                "A pen that places points, drags out curves, and closes a path on its own start",
                "A transform box that turns with the shape",
            ]),
            .init(date: "1 September", changes: [
                "Panels float over a full-width artboard instead of dividing the window",
                "Tools moved to their own tray, a chevron raising the pair behind each slot",
            ]),
            .init(date: "23 August", changes: [
                "Pick up the same layer in every frame it appears in, so a change lands once",
            ]),
            .init(date: "21 August", changes: [
                "Export to GIF, transparency included",
            ]),
            .init(date: "19 August", changes: [
                "Draw a line whose ends meet and it closes into a filled shape",
                "Frames to add, duplicate and step through, with onion skinning either side",
                "A layers panel, live booleans, and a reference image to draw over",
                "Export to SVG",
            ]),
        ]),
    ]
}

/// The list, on the same floating card as everything else.
///
/// Raised from Settings rather than from the menu bar, because it is a thing
/// you go and look at once rather than a thing you reach for while drawing —
/// which is also why it is not in the shortcuts legend.
struct VersionHistoryCard: View {
    let dismiss: () -> Void

    /// How tall the list came out. The card is as tall as its contents until
    /// they outgrow the window, and then it stops and the list scrolls — the
    /// same rule the shortcuts card follows.
    @State private var contentHeight: CGFloat = 0

    /// One column rather than the legend's two, but the titles are set at 20
    /// and a 540pt column put them on two lines. Still short of the legend's
    /// 700: this is prose, and a line you lose your place in is worse than a
    /// narrow card.
    private let cardWidth: CGFloat = 600
    /// The legend's measurements, so the two cards read as the same object:
    /// its inset, its row, its header, and the 20/4 it puts around a heading.
    private let pad: CGFloat = 18
    private let rowHeight: CGFloat = 38
    private let headerHeight: CGFloat = 34
    /// Between one build and the next. Far wider than the legend's 20: its
    /// groups are three or four short lines under an 11pt heading, and these
    /// are eight long ones under a 20pt one. At 20 the next title read as part
    /// of the list above it; at 36 it still did. This is a gap you scroll past,
    /// and it is the only thing saying one build has ended and another begun.
    private let headingAbove: CGFloat = 56
    /// Between a title and the rule under it.
    private let headingBelow: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let room = max(240, proxy.size.height - 96)
            VStack(spacing: 0) {
                header
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(VersionHistory.builds) { build in
                            entry(build, first: build.id == VersionHistory.builds.first?.id)
                        }
                    }
                    .padding(pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private var header: some View {
        HStack(spacing: 8) {
            Text("Version history")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlipTheme.textPrimary)
            Spacer(minLength: 0)
            // The build the binary is stamped with, so the card answers "which
            // one am I running" as well as "what changed".
            Text("v\(VersionHistory.version)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(FlipTheme.textTertiary)
            BarButton(glyph: .icon(.close)) { dismiss() }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: headerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(FlipTheme.border).frame(height: 1) }
    }

    /// One build: its number and name in the title face, the days it spans, and
    /// the versions under it — each a small heading of its own, then one line
    /// per change on the legend's row.
    private func entry(_ build: VersionHistory.Build, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // No date on a build: it is a cluster of versions and can span weeks,
            // so the only date it could carry is a range — and a range reads as
            // a claim about how long something took rather than as when a thing
            // landed. Each version below says its own day, which is the answer
            // to the question anyone is actually asking.
            Text("Build \(VersionHistory.number(of: build)): \(build.title)")
                .flipTitle(20)
                .foregroundStyle(FlipTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Nothing above the first one; the header's rule is already there.
            .padding(.top, first ? 0 : headingAbove)
            .padding(.bottom, headingBelow)

            ForEach(build.versions) { version in
                versionBlock(version, in: build)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One version inside a build: its number, and the lines that landed with it.
    private func versionBlock(_ version: VersionHistory.Version,
                              in build: VersionHistory.Build) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Small, and in the tertiary colour: these are an address and a date
            // rather than a title, and set any louder they compete with the
            // build's own name for the eye running down the card.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("v" + VersionHistory.number(of: version, in: build))
                    .monospacedDigit()
                Spacer(minLength: 12)
                Text(version.date)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(FlipTheme.textTertiary)
            .padding(.bottom, 6)

            // The version's own top rule. Every line below carries one
            // underneath it, so without this the first point is the only one in
            // the card with an open edge, and the block does not read as closed.
            Rectangle().fill(FlipTheme.border.opacity(0.6)).frame(height: 1)

            ForEach(version.changes, id: \.self) { change in
                Text(change)
                    .font(.system(size: 12))
                    // 145%. These are the only lines in the app that wrap —
                    // everything else is a label on one line — and set solid
                    // they read as a block rather than as separate points.
                    .lineSpacing(FlipFont.bodyLeading(12, 1.45))
                    .foregroundStyle(FlipTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The legend's row, as a floor rather than a fixed height:
                    // its rows hold one line each and these wrap, and a line
                    // clipped to 38 would lose its second half.
                    .padding(.vertical, 8)
                    .frame(minHeight: rowHeight, alignment: .leading)
                    // A rule under every line, the last one included: it closes
                    // the build off rather than leaving its final entry hanging
                    // into the space before the next heading.
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(FlipTheme.border.opacity(0.6)).frame(height: 1)
                    }
            }
        }
        // Between one version and the next, inside a build. Less than the gap
        // before a build's own name, which is what keeps them reading as a
        // group rather than as several.
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
