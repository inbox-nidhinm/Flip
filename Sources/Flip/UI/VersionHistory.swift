import SwiftUI

/// What the app has been, newest first.
///
/// Kept here rather than in a file on disk: it is a fixed list that ships with
/// the binary and never changes at runtime, so a bundle resource would be a
/// file to load, a parse to get wrong, and a failure case to handle, for a
/// value the compiler can hold as well.
///
/// The dates and the entries are taken from the build sessions themselves —
/// the project has no version control and the plist carries whatever the build
/// script was last told, so the sessions are the only record there is. A day is
/// the unit because that is how the work actually fell.
///
/// ## Adding a build
///
/// **Every change to the app gets an entry here, and this file is kept current
/// as part of the work rather than caught up with later.** Put the new build at
/// the *top* of `builds`. Nothing else needs touching: the numbers are counted
/// off the array, so the newest is always `builds.count`, and `version` is that
/// number — which is what the header badge, the Settings line and
/// `CFBundleShortVersionString` in `make-app.sh` all read.
enum VersionHistory {
    /// The app's version *is* the newest build number. One number, derived, so
    /// it cannot disagree with the list underneath it.
    ///
    /// `make-app.sh` writes the same value into the plist by hand — it composes
    /// the Info.plist itself and has no way to read Swift, so that is the one
    /// place this has to be repeated. Change it there too.
    static var version: String { "\(builds.count)" }

    struct Build: Identifiable {
        let date: String
        let title: String
        let changes: [String]
        var id: String { date + title }
    }

    /// Newest first. The build number is the position from the bottom, so a new
    /// entry at the top numbers itself and renumbers nothing.
    static func number(of build: Build) -> Int {
        guard let i = builds.firstIndex(where: { $0.id == build.id }) else { return 0 }
        return builds.count - i
    }

    static let builds: [Build] = [
        .init(date: "15 September", title: "A group is one thing", changes: [
            "A group rigs as a single object. Binding it binds everything inside it, and the armature carries down to each shape at draw time — so a grouped character is rigged by pointing at the character, not by getting a bone far enough inside one particular shape of it.",
            "Select something and the bone takes that, whole. A selection is an answer already given, so nothing is measured and nothing is unpredictable: the same gesture over the same drawing binds the same layers every time. With nothing selected, enclosure still decides, but each layer is now weighed as one object — a group by the shapes inside it, taken whole rather than picked apart.",
            "The gap between a group's shapes is still outside it, since the area is the real subpaths rather than a bounding box. A bone drawn through the hole in a doughnut binds nothing, which is the same answer it gives for a single shape.",
            "Clicking and hovering follow: a click binds or releases a grouped drawing whole, and the highlight outlines every shape in it, because that is what the click will take.",
            "Binding the whole of a character was previously refused on the grounds that one bone would then drag all of it. That was wrong. A layer follows the whole armature, weighted per point — the arm bones move the arm and the torso bone holds the torso — so the bone that claims a layer has no special hold over it. The fear was of proximity claiming *unrelated* drawings, which explicit ownership already prevents.",
            "A shape inside a bound group can still be bound to a different armature of its own, which overrides what it inherits.",
        ]),
        .init(date: "15 September", title: "A quieter layer list", changes: [
            "A layer an armature drives says so, with a small bone before the visibility toggle. A group says it for whatever is inside it — armatures own shapes, never the group holding them, so a grouped character had nothing anywhere telling you it was rigged until you opened every group in the list to find out.",
            "The eye only appears while the pointer is on the row. A column of them down a long list is a row of controls nobody asked for, and each one competes with the drawing's own swatch for the eye.",
            "A layer that is switched *off* keeps its crossed eye whatever the pointer is doing. That is the layer saying something about itself rather than the panel offering a control, and a hidden layer with nothing on its row would be a layer you could only find by hunting.",
            "The eye is faded rather than removed, so its slot is always there and the bone beside it cannot shift sideways when the pointer arrives.",
            "Deleting a rig now clears it at every depth. It only ever cleared the top of the stack, so a grouped shape was left pointing at an armature that no longer existed — harmless to draw, since posing checks the index, but the layer still called itself rigged and the next armature would have silently inherited it.",
        ]),
        .init(date: "15 September", title: "Rigging a grouped drawing", changes: [
            "The bone tool works on grouped artwork. Claiming, click-to-bind, the hover highlight and the ownership outline all walked the top of the layer stack and asked each layer for its shape — and a group has none, so a grouped character was invisible to every one of them. A bone drawn into it claimed nothing and the drawing simply never moved.",
            "A rig owns shapes, never the group holding them, and reaches through any depth of grouping to find them. Grouping is organisation — thirty shapes read as four things — and it must not change what a bone lies inside, or tidying the layer list would silently re-rig the character.",
            "Owning the group itself would be worse than merely inconsistent. A group's area is the union of its children's, so a bone in a forearm lies inside the whole-body group as surely as it lies inside the forearm — one bone would take the entire character, which is the runaway that enclosure was chosen over proximity to avoid.",
            "A boolean goes the same way, its children being its inputs: the shapes deform and the operation re-evaluates from them, which is what makes a rigged boolean behave rather than snap.",
        ]),
        .init(date: "15 September", title: "A pointer that says copy", changes: [
            "Holding ⌥ over something the cursor could take hold of shows the doubled arrow, so the duplicate is visible before it is made rather than discovered afterwards.",
            "It answers the key rather than the next mouse move. Pressing ⌥ with the hand still is the whole case worth having — you are already over the thing you meant to copy.",
            "Over bare paper it stays an ordinary arrow, because an ⌥-drag there is a marquee and a copy-shaped pointer would be promising a duplicate of nothing. Over a transform grip it stays the resize arrow, for the same reason: ⌥ on a corner still resizes.",
            "The pointer was being placed from the event that asked for it, and a key press carries no mouse position — so the pen's pointer had the same hole, and only ever looked right because a mouse move followed closely enough to cover it. Both now read where the mouse actually is and which modifiers are actually down.",
        ]),
        .init(date: "15 September", title: "Drag off a copy", changes: [
            "⌥-drag with the cursor leaves a copy behind: the original stays where it was and the copy comes away under the hand. It is the gesture every vector editor has, and without it duplicating something meant copy, paste, and then drag it off the thing it landed on.",
            "The copy is made in place and the drag provides the offset, so ⌥-clicking without moving changes nothing. It lands directly in front of what it came from, in that layer's own stack — a copy made inside a group stays in the group, beside the original.",
            "Both halves are one undo. An ⌥-drag is one action to the hand that did it, and needing two presses of ⌘Z to get back would be counting the implementation out loud.",
            "⌥ no longer pans while the cursor is in hand — it cannot both pan and duplicate, and the pointer is a promise about what the next press does. ⌃ pans with every tool, and the hand tool is still there; ⌥ still pans with the brush and the shapes, which have no use of their own for it. The pen already worked this way.",
            "A duplicate gets a new identity all the way down, which is the half that was missing. Copying only ever renamed a boolean's children, so a copied *group* handed back children still carrying the originals' ids — and two layers in one frame answering to the same id is not cosmetic: every lookup finds whichever comes first, so a move, a colour or a delete aimed at one hits the other. Paste had the same hole and is fixed with it.",
            "It also gets a new track, where a track means \"this same element, once per frame\". Inheriting the original's would make ⌥-clicking either copy select both of them, in every frame, ever after.",
            "Selecting a group and something inside it and duplicating gives one copy rather than two — the outermost of what is selected is copied, since the copy of the group already contains the child.",
        ]),
        .init(date: "15 September", title: "Bone cursors", changes: [
            "The bone tool has two pointers of its own, one per mode: the four-way pointer while placing, with its hot spot dead centre where the bone's origin will land, and the pointing hand while posing, whose hot spot is the fingertip — the precise end you want when the thing to grab is a handle five pixels across. One tool doing two jobs needs the pointer to say which, since nothing else on the canvas does.",
            "The pointer now changes on the key press rather than on the next mouse move. Invalidating the cursor rect only schedules a rebuild, and AppKit applies it at the next cursor update — so pressing A with the hand still gave you the old pointer until you twitched the mouse.",
            "The first bone of a frame is visible while it is being drawn. The whole rig overlay — the drag preview included — was drawn only once an armature existed, and the first bone is placed when it does not: so the first drag in a frame showed nothing at all until the mouse came up, and every drag after it was live. A tool that answers the second use and not the first reads as broken rather than as empty.",
            "The bone being dragged carries a tip handle as well as its origin, in the same amber a tip being posed wears. It was a dashed line with one dot, which read as a line rather than as a bone about to exist.",
            "The cursor pipeline understands two things Figma writes that it did not. A stroke aligned to the outside is exported as a masked second copy of the path; laid down in that order it painted white over the glyph's own edges, so it is now drawn underneath, where the fill covers its inner half exactly as the mask cut it away. And a `<circle>` — which is how the dot marking a hot spot is written — is spelled out as four cubics instead of being silently dropped.",
        ]),
        .init(date: "11 September", title: "Groups inside groups", changes: [
            "A group can hold a group. Grouping now happens in whatever stack the selection is already in, so a run of shapes inside a group becomes a group inside that group, to any depth — where before ⌘G only ever saw the frame's own top level and did nothing at all to a selection buried one level down.",
            "Ungrouping matches it: a group released inside a group comes apart into the group that held it, its children landing at its own index. Nothing on the canvas moves, which is the whole promise of a plain group — it is a name and a place in the stack, so taking it away should change the outline of the list and not a pixel of the drawing.",
            "Booleans were capped the same way, and Release was worse than capped: the button read the selection at any depth but the operation only searched the top level, so releasing a boolean that sat inside a group was an enabled button that did nothing. Both now work wherever the layer is.",
            "A selection straddling a group's edge is still refused. It names two stacks and no way to choose which one the group belongs in — the same objection reordering already makes to stepping such a selection along.",
            "Grouping inside a boolean is refused too. A boolean's children are its *inputs*, not a free stack, and a plain group has no region of its own; one standing where an input should be would drop silently out of the operation and quietly change the result.",
        ]),
        .init(date: "7 September", title: "Bones", changes: [
            "A bone tool, in the strip beside the other three. It makes no marks: it moves what is already drawn, so a limb can be carried from one frame to the next by turning it rather than by drawing it again. There are no in-betweens and no timeline — the frames are still yours, and the armature is scaffolding for posing them.",
            "Bones are drawn only with the bone tool in hand, and only for the armature driving the selected layer. Everywhere else they are lines across someone else's drawing, and a frame carrying three rigs put all of them over the artwork at once. With nothing selected the last rig placed or posed shows, so building one from scratch is not done blind.",
            "The layer under the pointer says what a click would do to it: solid amber to take it into the armature, dashed in the rig's own colour to let it go. It runs the same enclosure query the click does, so the highlight cannot promise something the click will not deliver, and it only appears while placing — in Pose a click binds nothing, and offering it there would be a lie.",
            "The layer highlight and click-to-bind follow the same scope. Keyed to the last rig *touched*, a layer could wear a rig's colour while its bones were hidden — and a click could bind a layer to an armature that was not on screen, which is an edit with no visible result and no obvious way back.",
            "Its operations sit in a bar of their own, above the frame strip and up only while the tool is in hand. They were a popup hanging off a chevron first, and that was wrong: a rig has two modes and five operations and you reach for all of them repeatedly while posing, so a card you have to reopen between every one is a card in the way. The bar costs the room only when the tool is out.",
            "One tool has to both build a rig and move it, and a tip is at once a pose handle and the place a child bone hangs from, so Place and Pose are a pair of modes rather than a modifier. Nothing was free to overload: Option already stretches a bone, and Control and Option both pan.",
            "Two ways a drag behaves. IK lets three bones up the chain rearrange themselves to meet the cursor, which is quicker and less exact; FK moves only the bone you took hold of and swings its children along, and with Option stretches it as well. Letters rather than glyphs, because two arrows side by side would be a guess where these are what riggers already call them.",
            "An armature owns the layers it drives, and only those. Proximity was tried first and is a liar in a real drawing — it cannot tell a sleeve from the arm inside it from the torso behind it, and one bone with nothing else in the frame claimed every layer on the artboard. Ownership is stored on the layer instead, so reordering the stack never re-binds a rig.",
            "What a bone claims is what it lies *inside*, judged by half its own length rather than by one end. Testing the origin alone meant a chain started at a shoulder — just outside the limb it drives — claimed nothing, and no later bone could recover it. Enclosure is exact here because the fill has a real inside: `CGPath` answers it on the curves themselves rather than on a polygon standing in for them.",
            "A bone claims every layer enclosing it, not the topmost, since binding a sleeve and leaving the arm behind is the more common mistake. It never takes a layer another rig already holds; clicking a layer with the bone tool in hand adds or removes it by hand, which is the way to re-home one.",
            "Deforming blends each bone's *frame* and applies it whole, rather than blending the places each bone would put a point — which is what pinches a joint. Handles are offsets from their anchors here, so they take the turn without the move, and a bent limb keeps its curvature instead of kinking at every anchor.",
            "Selection boxes and hit testing read the posed geometry rather than the stored rest pose. Measuring a rigged layer from what is on disk put its box out over empty paper and made a click miss the artwork it was plainly over.",
            "The drawing is never written to. Stored geometry stays the rest pose and the pose is applied at draw time, in the one place that paints a frame — so the canvas, the ghosts either side of it, the strip's thumbnails and the raster exports all agree, and undoing a pose is undoing a rig edit rather than hoping the artwork went back.",
            "Its own creations folder, and its own bundle identifier so it cannot inherit Flip's. This build shares the document format and the Library can trash and move files; pointing a new engine at drawings that already exist is one bug away from losing them.",
        ]),
        .init(date: "7 September", title: "The paper moved into the panel", changes: [
            "Onion skin and the artboard left the frame strip for the tools panel, as two folding groups of their own. Both describe the paper rather than the mark in hand — the ghosts either side of this frame, the size of the sheet, the ground under it — and in the panel they are labelled rows in a column instead of a card raised over the canvas.",
            "They come up only with the cursor or the hand. Those are the two tools that make nothing, so they are the two where the paper is what you are actually touching; with a brush down, the rows you want are fill, stroke and width, and these would only have pushed them along.",
            "The frame strip is the frames and the tools now, and nothing else — two buttons shorter, and every button left in it acts on a frame or picks a tool.",
            "Onion's on/off became a `Show` row rather than the eye the popup carried in its header, which is the same question the reference below it already asks the same way.",
        ]),
        .init(date: "6 September", title: "Stills, and a pass on the shelf", changes: [
            "Picking a feature on the last onboarding page turns its plate like a leaf, lifting from the top-right corner — the page bends around a cylinder rather than pivoting flat, and a shadow travels with the fold onto the plate underneath. The reverse of the leaf is the plate's own ground colour lifted toward the light, read off its corners, because a page's back is the same stock as its face.",
            "The frame you are on, written out as a PNG. Full size, and no scale to set: a GIF is thirty frames and gets large quickly, but a still is one image, and an export you have to remember to put back to 100% is a trap rather than an option.",
            "Transparent belongs to both exporters now rather than to the GIF alone. PNG carries eight bits of alpha, so an antialiased edge survives as one — none of the thresholding and un-premultiplying a transparent GIF needs applies to it, and Cutoff stays the GIF's own.",
            "A shelf card's caption sits 12 off the bottom instead of 5. That number was there to inset the thumbnail from the card's edge; under the date there is no picture to inset.",
            "The folding section headings lost the hover they were given yesterday. A band behind a heading read as a selected row rather than as a control answering the pointer.",
        ]),
        .init(date: "5 September", title: "Onboarding, and the panel that went away", changes: [
            "A first run that hands the app over rather than explaining it.",
            "The side tool bar is gone. What shows in the panel now is what the tool in hand and the selection can actually be done to.",
            "Playback and export fold away, and come up shut.",
            "Blend modes, under opacity, where the other thing that acts on a layer as a unit already was.",
            "The switch became the slider's own parts — same track, same pill, moved to one end.",
            "A click anywhere outside a popup puts it away.",
            "Selecting a layer off-screen scrolls the panel to it.",
            "Grain on the canvas and the shelf, so nothing reads as a different material.",
            "This list, on its own card at the foot of Settings — and the version became the newest build number rather than a figure of its own.",
            "Everything you can click now answers the pointer: the onboarding buttons, the stepper, the colour well, the swatches, the toggle, the document name, and a layer row's chevron and eye, which take their own click and so needed their own hover.",
        ]),
        .init(date: "4 September", title: "Grain, colour, and the shelf", changes: [
            "Grain under every panel, tiled rather than stretched, at half the scale it started at.",
            "The app's own colour picker in place of the system panel, and a palette each document can add to on top of the nine built in.",
            "Autosave to Flip Creations, with no dialog and no asking.",
            "A home shelf: recent projects with thumbnails, folders, rename, delete, move.",
            "Groups, shift-click for a run of layers, ⌘-click to reach a shape inside one.",
            "Arrow keys nudge a point; shift makes it eight.",
            "The hand tool, and holding control to pan without leaving the tool you are on.",
            "Every shortcut on one card — a legend, not a settings sheet.",
        ]),
        .init(date: "2 September", title: "Cursors, curves and the transform box", changes: [
            "#1B8F51 became the one thing selection reads as, everywhere.",
            "A pointer per tool, drawn rather than borrowed, at 1.2× with the hot spots scaled to match — and the system arrow handed back over the panels.",
            "The pen tool learned to place a point, drag out a curve, and close a path onto its own first point.",
            "A transform box with corner grips that turns with the shape, and a cursor per direction.",
            "The current frame's tile stands 1.1× proud, and the strip fades at whichever end can still scroll.",
            "Shapes number themselves — Shape 1, Rectangle 2 — instead of arriving nameless.",
        ]),
        .init(date: "1 September", title: "The interface, rebuilt", changes: [
            "The panels stopped dividing the window and started floating over a full-width artboard.",
            "One section open at a time, taking the whole height of the panel.",
            "Every explanatory line taken out — no Nothing selected, no Draw something. A state the app can show is shown.",
            "The app's own icon set, drawn on one 24-unit grid.",
            "The tools moved to their own tray, at full bar height, with a chevron raising the pair behind each slot.",
            "Undo, redo and step-a-frame left the bar; the keys already did them.",
        ]),
        .init(date: "23 August", title: "One layer, in every frame", changes: [
            "A selection that reaches past the frame on screen and picks up the same layer everywhere it appears, so a change lands once instead of once per frame.",
        ]),
        .init(date: "21 August", title: "Export, and getting out of the way", changes: [
            "GIF export, transparency included.",
            "Renaming a layer moved off the double-click and onto a right-click, with ⌘R beside it — a double-click would have made every selection wait out the interval first.",
            "A pass on how long the panel took to answer a click.",
        ]),
        .init(date: "19 August", title: "The first build", changes: [
            "Draw a line, and have its ends meet: a closed shape, filled and coloured.",
            "A layers panel where the layers belong to the frame you are on, not to the document.",
            "Booleans on the selection — the beginning of subtracting one shape out of another.",
            "A reference image that sits under the artboard to draw over.",
            "Onion skinning, and frames that could be added, duplicated and stepped through.",
            "Export to SVG.",
            "A shape copied from one frame lands in exactly the same place in the next.",
            "Letters for the tools — B, R, O, V, P — and brackets to step a frame.",
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
            Text("Build \(VersionHistory.version)")
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

    /// One build: its number and name in the title face, the day it landed, and
    /// what came with it — one line per change, on the legend's row.
    private func entry(_ build: VersionHistory.Build, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Build \(VersionHistory.number(of: build)): \(build.title)")
                    .flipTitle(20)
                    .foregroundStyle(FlipTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(build.date)
                    .font(.system(size: 11))
                    .foregroundStyle(FlipTheme.textTertiary)
                    .lineLimit(1)
            }
            // Nothing above the first one; the header's rule is already there.
            .padding(.top, first ? 0 : headingAbove)
            .padding(.bottom, headingBelow)

            // The build's own top rule. Every line below carries one underneath
            // it, so without this the first point is the only one in the card
            // with an open edge, and the block does not read as closed.
            Rectangle().fill(FlipTheme.border.opacity(0.6)).frame(height: 1)

            ForEach(build.changes, id: \.self) { change in
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
