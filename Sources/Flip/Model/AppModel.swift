import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted when the artboard should be reframed — on opening a document, whose
    /// artboard may be a different size than the one currently on screen. Declared
    /// here rather than in the view, since the model is what posts it.
    static let flipFitToWindow = Notification.Name("FlipFitToWindow")
}

enum BoneMode: String, Hashable {
    /// Drag from empty space for a new armature, or from a tip to chain a child.
    case place
    /// Drag a handle to move what is already built.
    case pose
}

enum StripPopup: String, Hashable {
    /// The slot holding the two tools that make nothing — one picks things up,
    /// the other moves the view under them.
    case pointer
    case draw, shape
}

enum Tool: String, CaseIterable, Hashable {
    /// Listed in the order they appear in the title bar, left to right.
    case select, hand, brush, bezier, rect, ellipse, bone

    var glyph: Glyph { .icon(icon) }

    var icon: Icon {
        switch self {
        case .select:  return .cursor
        case .hand:    return .hand
        case .brush:   return .brush
        case .bezier:  return .pen
        case .rect:    return .rectangle
        case .ellipse: return .circle
        case .bone:    return .bone
        }
    }

    /// Short enough for a menu row. `help` is the sentence; this is the name.
    var label: String {
        switch self {
        case .select:  return "Cursor"
        case .hand:    return "Hand"
        case .brush:   return "Brush"
        case .bezier:  return "Pen"
        case .rect:    return "Rectangle"
        case .ellipse: return "Circle"
        case .bone:    return "Bone"
        }
    }
}

/// Address of one on-curve point, anywhere in the current frame.
struct NodeRef: Hashable {
    var layer: UUID
    var subpath: Int
    var anchor: Int
}

// MARK: - Tree walking

enum LayerTree {
    static func find(_ id: UUID, in layers: [Layer]) -> Layer? {
        for l in layers {
            if l.id == id { return l }
            if let hit = find(id, in: l.children) { return hit }
        }
        return nil
    }

    @discardableResult
    static func mutate(_ id: UUID, in layers: inout [Layer], _ body: (inout Layer) -> Void) -> Bool {
        for i in layers.indices {
            if layers[i].id == id { body(&layers[i]); return true }
            var kids = layers[i].children
            guard !kids.isEmpty else { continue }
            if mutate(id, in: &kids, body) { layers[i].children = kids; return true }
        }
        return false
    }

    /// Every group with one of `ids` somewhere inside it, at any depth.
    ///
    /// Not the ids themselves — a group that *is* selected is not a group the
    /// selection is hidden inside, and the two want different treatment in the
    /// list.
    static func containers(of ids: Set<UUID>, in layers: [Layer]) -> Set<UUID> {
        var found: Set<UUID> = []
        @discardableResult
        func walk(_ layers: [Layer]) -> Bool {
            var holds = false
            for l in layers {
                var inside = false
                if !l.children.isEmpty { inside = walk(l.children) }
                if inside { found.insert(l.id) }
                if inside || ids.contains(l.id) { holds = true }
            }
            return holds
        }
        walk(layers)
        return found
    }

    /// The stack each of `ids` sits in, named by the path of container ids that
    /// leads to it. The empty path is the frame's own stack.
    ///
    /// A set of one means every selected layer is a sibling of every other, and
    /// that is the only case where "forward" and "backward" name a single order
    /// to step along. Two means the selection straddles a group's edge, and
    /// there is no answer to which of two stacks the move should happen in.
    static func stacks(of ids: Set<UUID>, in layers: [Layer]) -> Set<[UUID]> {
        var found: Set<[UUID]> = []
        func walk(_ layers: [Layer], _ path: [UUID]) {
            for l in layers {
                if ids.contains(l.id) { found.insert(path) }
                if !l.children.isEmpty { walk(l.children, path + [l.id]) }
            }
        }
        walk(layers, [])
        return found
    }

    /// Hands the array at `path` to `body` and writes back whatever it did with
    /// it — the tree's stacks are `[Layer]` values nested in enum payloads, so
    /// reaching one to reorder it means threading the whole way back up.
    @discardableResult
    static func mutateStack(at path: [UUID], in layers: inout [Layer],
                            _ body: (inout [Layer]) -> Void) -> Bool {
        guard let next = path.first else { body(&layers); return true }
        for i in layers.indices where layers[i].id == next {
            var kids = layers[i].children
            let done = mutateStack(at: Array(path.dropFirst()), in: &kids, body)
            if done { layers[i].children = kids }
            return done
        }
        return false
    }

    /// Moves everything selected one place along its stack, together.
    ///
    /// Walked from the end the run is heading for, so a block of selected layers
    /// slides as a block rather than piling up: the member nearest the
    /// destination goes first and the rest follow into the space it leaves.
    /// `wall` is the first index nothing may move into — it starts past the end
    /// and is pulled back by every selected layer that could not move, which is
    /// what makes a selection already hard against the top stay in formation
    /// instead of concertinaing into it.
    ///
    /// The array is in paint order, bottom of the drawing first, so "up" — the
    /// front of the drawing, the top of the panel's list — is towards the end.
    @discardableResult
    static func step(_ ids: Set<UUID>, in stack: inout [Layer], up: Bool) -> Bool {
        var moved = false
        if up {
            var wall = stack.count
            for i in stride(from: stack.count - 1, through: 0, by: -1)
            where ids.contains(stack[i].id) {
                if i + 1 < wall { stack.swapAt(i, i + 1); wall = i + 1; moved = true }
                else { wall = i }
            }
        } else {
            var wall = -1
            for i in stack.indices where ids.contains(stack[i].id) {
                if i - 1 > wall { stack.swapAt(i, i - 1); wall = i - 1; moved = true }
                else { wall = i }
            }
        }
        return moved
    }

    /// Everything selected to one end of its stack, keeping the order they were
    /// already in relative to each other.
    @discardableResult
    static func moveToEnd(_ ids: Set<UUID>, in stack: inout [Layer], front: Bool) -> Bool {
        let taken = stack.filter { ids.contains($0.id) }
        let rest  = stack.filter { !ids.contains($0.id) }
        guard !taken.isEmpty, !rest.isEmpty else { return false }
        let next = front ? rest + taken : taken + rest
        guard next.map(\.id) != stack.map(\.id) else { return false }
        stack = next
        return true
    }

    /// Pulls the named layers out of the tree and returns them in stack order.
    static func extract(_ ids: Set<UUID>, from layers: inout [Layer]) -> [Layer] {
        var taken: [Layer] = []
        var kept: [Layer] = []
        for var l in layers {
            if ids.contains(l.id) { taken.append(l); continue }
            var kids = l.children
            if !kids.isEmpty {
                taken.append(contentsOf: extract(ids, from: &kids))
                l.children = kids
            }
            kept.append(l)
        }
        layers = kept
        return taken
    }

    /// The layers of the stack at `path`, bottom of the drawing first. The empty
    /// path is the frame's own stack; `nil` means the path has gone stale.
    static func stack(at path: [UUID], in layers: [Layer]) -> [Layer]? {
        guard let next = path.first else { return layers }
        for l in layers where l.id == next {
            return stack(at: Array(path.dropFirst()), in: l.children)
        }
        return nil
    }

    /// The outermost of `ids`: one whose ancestor is also named is left out,
    /// since whatever happens to the ancestor already carries it. Stack order,
    /// bottom of the drawing first.
    static func outermost(_ ids: Set<UUID>, in layers: [Layer]) -> [Layer] {
        var out: [Layer] = []
        func walk(_ layers: [Layer]) {
            for l in layers {
                if ids.contains(l.id) { out.append(l) }
                else { walk(l.children) }
            }
        }
        walk(layers)
        return out
    }

    /// Puts a layer directly in front of `id`, in whatever stack holds it — so
    /// a copy of something inside a group lands in that group, next to what it
    /// was copied from.
    @discardableResult
    static func insert(_ layer: Layer, above id: UUID, in layers: inout [Layer]) -> Bool {
        for i in layers.indices {
            if layers[i].id == id { layers.insert(layer, at: i + 1); return true }
            var kids = layers[i].children
            guard !kids.isEmpty else { continue }
            if insert(layer, above: id, in: &kids) { layers[i].children = kids; return true }
        }
        return false
    }

    /// Replaces one layer with its children, wherever in the tree it sits, and
    /// hands back the children it let go.
    ///
    /// They land at the layer's own index, so a group released inside a group
    /// comes apart into the group that held it and nothing else moves. That is
    /// the whole promise of a plain group: taking it away changes the outline of
    /// the list and not a pixel of the drawing.
    @discardableResult
    static func unwrap(_ id: UUID, in layers: inout [Layer]) -> [Layer]? {
        for i in layers.indices {
            if layers[i].id == id {
                let kids = layers[i].children
                layers.replaceSubrange(i...i, with: kids)
                return kids
            }
            var kids = layers[i].children
            guard !kids.isEmpty else { continue }
            if let freed = unwrap(id, in: &kids) {
                layers[i].children = kids
                return freed
            }
        }
        return nil
    }
}

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {
    /// Launch Services hands files to the app delegate, which is created outside
    /// the SwiftUI scene that owns the model — so the delegate needs a way in.
    static weak var current: AppModel?
    /// A file handed over before the model existed, drained by `init`.
    static var pendingOpen: URL?

    init() {
        AppModel.current = self
        if let url = AppModel.pendingOpen {
            AppModel.pendingOpen = nil
            loadDocument(from: url)
            // Opened from the Finder: the drawing is what was asked for, so the
            // shelf would only be in the way.
            showingHome = false
        }
    }

    /// Deliberately not `@Published`. The setter decides when to notify, so a
    /// canvas drag can move geometry sixty times a second while the layers panel,
    /// the tools panel and the frame strip rebuild once — when the drag ends.
    /// Everything else assigns to `doc` as before and publishes normally.
    private var storedDoc = Document()
    var doc: Document {
        get { storedDoc }
        set {
            if !suspendsPublishing { objectWillChange.send() }
            storedDoc = newValue
            // Every route into the document comes through here — a new shape, a
            // colour, a slider, an undo — so this is the one place autosave has
            // to be hooked to catch all of them.
            unsaved = true
            scheduleAutosave()
        }
    }

    /// Raised for the length of a canvas drag. Not published itself, or setting it
    /// would cause the very refresh it exists to avoid.
    var suspendsPublishing = false
    @Published var frameIndex = 0

    @Published var tool: Tool = .brush
    @Published var selection: Set<UUID> = []
    @Published var selectedNodes: Set<NodeRef> = []
    /// The layer whose name is being edited in the layers panel. This lives on the
    /// model rather than in the panel because ⌘R arrives through the menu bar,
    /// which has no way to reach a view's `@State`.
    @Published var renamingLayer: UUID?
    /// The layer the pointer is over in the layers panel.
    ///
    /// On the model rather than in the panel because the *canvas* is what draws
    /// the answer — the panel knows which row is under the pointer, and the
    /// canvas knows where that shape is, and neither can see the other.
    @Published var hoveredLayer: UUID?
    /// The wander the next line will be drawn with, and what the panel's
    /// dials sit at when nothing is selected.
    @Published var wiggle: Wiggle = .off
    /// What the next stroke will be laid down with.
    @Published var nib: Nib = .pen

    /// What the colour card is editing, and nil when it is shut.
    ///
    /// On the model because the card cannot live where it is opened from: the
    /// panels clip their contents, and a card that has to stand *beside* the
    /// panel would be cut off at the panel's edge. It is drawn at the window's
    /// level instead, which means the window has to be told what it is for.
    @Published var picking: PaintTarget?
    /// The colour while the card is open, for the two targets that are only
    /// written when it shuts. Fill and stroke go straight to the document.
    @Published var pickerDraft: RGBA = .ink

    /// Paint that new shapes are born with, and what the swatches set.
    @Published var fillColor: RGBA = RGBA(1.0, 152/255, 94/255)   // #FF985E
    @Published var strokeColor: RGBA = .ink
    @Published var strokeWidth: CGFloat = 3
    @Published var fillEnabled = true
    @Published var strokeEnabled = true
    /// What the opacity slider is showing. Seeded from the selection when it
    /// changes, so the slider reads the layer you just picked rather than
    /// whatever it was left at.
    @Published var opacity: Double = 1

    @Published var onionEnabled = false
    @Published var onionBack = 2
    @Published var onionForward = 1
    @Published var onionOpacity: Double = 0.35

    /// GIF options. Deliberately not stored in the document: adding a
    /// non-optional field to a Codable struct makes every older `.flip` file fail
    /// to decode, and export settings are not worth that risk.
    /// Read by both exporters. It was the GIF's alone until the PNG arrived,
    /// and two switches in one section both called Transparent would have been
    /// a worse answer than one that means what it says.
    @Published var exportTransparent = false
    @Published var gifScale: Double = 0.5
    @Published var gifThreshold: Double = 0.5

    @Published var isPlaying = false

    /// What the frame strip has raised above itself, if anything. On the model
    /// rather than in `FrameStrip` so that a click on the canvas can dismiss it,
    /// the way a real popover would have.
    @Published var stripPopup: StripPopup?

    // MARK: Armature

    /// What a drag with the bone tool does. One tool has to both build the
    /// armature and move it, and the two cannot share a gesture: a tip is at
    /// once a pose handle and the place a child bone hangs from. Overloading a
    /// modifier was the alternative and there were none free — Option already
    /// stretches a bone, Control and Option both pan.
    @Published var boneMode: BoneMode = .place

    /// How dragging a bone tip behaves. IK lets a few bones up the chain
    /// rearrange themselves to reach the cursor — quicker to pose, less
    /// controllable; FK turns only the bone you grabbed and swings its children
    /// along. Both are wanted at different moments, so it is a mode rather than
    /// a choice made once.
    @Published var poseWithIK = true

    /// Whether the armature is drawn over the artwork. Hiding it is how you see
    /// the pose as a drawing rather than as a rig.
    @Published var showRig = true

    /// A pose left behind as an outline, so the change between two poses can be
    /// judged. Runtime only — it is a thing you glance at while working, not a
    /// property of the drawing, and saving it would mean deciding what a
    /// reopened document should do with someone else's half-finished comparison.
    @Published var rigGhost: [Shape2D] = []

    /// The armature a click-to-bind acts on, and the one whose ownership the
    /// canvas shows. Set by placing or posing a bone.
    @Published var activeRig: Int?

    /// Which panels are on screen. On the model rather than in `ContentView`
    /// because the panels float *over* the canvas now, so fitting the artboard
    /// means knowing how much of the canvas they are covering.
    @Published var showLayers = true
    @Published var showTools = true
    /// The shortcuts legend. Not a document setting and not remembered: it is a
    /// thing you open, read and shut, and one that came back on relaunch would be
    /// in the way of the drawing every time.
    @Published var showShortcuts = false

    /// The version history. Held here beside the other raised cards rather than
    /// as local state on the shelf, because it is opened from Settings and has
    /// to be drawn above it — and because `goHome` and the escape key already
    /// know to put this kind of thing away.
    @Published var showVersionHistory = false

    /// Whether the onboarding card is up. True on a first run and never again,
    /// unless it is asked for from the Help menu.
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: AppModel.onboardedKey)

    private static let onboardedKey = "hasSeenOnboarding"

    /// Whether anything is raised that a click elsewhere should put away: the
    /// colour card, one of the frame strip's popups, the shortcuts legend.
    ///
    /// Not the onboarding — that is a thing you finish rather than dismiss by
    /// clicking past it.
    var hasTransient: Bool { picking != nil || stripPopup != nil || showShortcuts }

    /// Puts away whatever is raised, and says whether the click that did it
    /// should be **swallowed** rather than also reaching the canvas.
    ///
    /// Only the legend swallows. A colour card or a strip popup is a thing you
    /// set and then use: pick a colour, then draw with it. Making that click
    /// only dismiss turns one intention into two clicks, and the first stroke
    /// going nowhere reads as the app having stopped responding rather than as
    /// a popover being tidy. The legend is the exception because it covers the
    /// artboard — a click on it has no place underneath to mean.
    @discardableResult
    func dismissTransients() -> Bool {
        guard hasTransient else { return false }
        let swallow = showShortcuts
        if picking != nil { endPicking() }
        if stripPopup != nil { stripPopup = nil }
        if showShortcuts { showShortcuts = false }
        return swallow
    }

    /// Whether something is laid over the canvas that the canvas should not be
    /// reacting behind.
    ///
    /// SwiftUI draws these cards *into* the hosting view rather than as views of
    /// their own, so AppKit's hit testing does not know they are there: a scroll
    /// over the shortcuts card finds the canvas underneath and pans it, and the
    /// card that was meant to catch the wheel never sees it. Nothing in SwiftUI
    /// fixes that from the card's side, so the canvas asks.
    var isCovered: Bool { showShortcuts || showOnboarding }

    /// Shuts the card and remembers that it has been seen. Called however it is
    /// left — the last page's button, or Escape from any of them: someone who
    /// pressed Escape has decided, and being shown it again on the next launch
    /// would be the app not listening.
    func endOnboarding() {
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: AppModel.onboardedKey)
    }

    /// Whether the home screen is up instead of the editor.
    ///
    /// A screen rather than a second window: the app is one window with a
    /// hidden title bar, and a separate one would need its own chrome, its own
    /// size, and its own answer to what ⌘W means.
    @Published var showingHome = true

    /// Whether the reference image is being repositioned.
    ///
    /// A mode rather than a modifier. Moving the reference is rare, deliberate
    /// and destructive to a trace in progress — exactly the shape of thing that
    /// wants entering and leaving on purpose, rather than living one stray
    /// ⌘-drag away from every other press on the canvas. It also gives the
    /// modifier back to the pen, which has more to say with it.
    @Published private(set) var repositioning = false
    /// What to put back if the reposition is abandoned.
    private var referenceSnapshot: Reference?
    /// The panels the user had open before the mode hid them.
    private var panelsBeforeReposition: (layers: Bool, tools: Bool)?

    /// Not published: panning and zooming concern the canvas alone, and every
    /// scroll-wheel tick was rebuilding all three panels and every frame tile.
    /// The canvas marks itself for display when it changes these.
    var zoom: CGFloat = 1
    var pan: CGPoint = .zero
    @Published var errorMessage: String?
    @Published var statusNote: String?
    /// Layers held for pasting. Kept as model objects rather than round-tripped
    /// through the system pasteboard, so a paste is an exact copy — geometry,
    /// handles, colours, and any boolean group with its children intact.
    @Published private(set) var clipboard: [Layer] = []

    /// How close two things must be, in document points, to snap.
    let snapDistance: CGFloat = 14

    private var undoStack: [Document] = []
    private var redoStack: [Document] = []
    private var thumbCache: [UUID: CGImage] = [:]
    /// Decoding the reference on every redraw would be absurd, so keep the last
    /// decode keyed by the bytes it came from.
    private var refCache: (Data, CGImage)?
    private var timer: Timer?
    /// +1 out, -1 back. Only a bounce ever sets it to -1.
    private var playDirection = 1
    private var fileURL: URL?

    // MARK: Autosave state

    /// Raised by every write to `doc`, cleared when the file on disk matches it.
    private var unsaved = false
    private var autosaveTimer: Timer?
    /// When this document came into being. Used **once**, to mint a filename, so
    /// the name records when the drawing was started and never moves as it is
    /// edited. Not stored in the file: by the time a document is reopened it
    /// already has a name, and there is nothing left to mint.
    private var created = Date()
    /// A name the user has typed before the first autosave has run, so there is
    /// no file to rename yet. The first write picks it up.
    private var chosenName: String?

    // MARK: Current frame

    var frame: Frame {
        get { doc.frames[min(frameIndex, doc.frames.count - 1)] }
        set { doc.frames[min(frameIndex, doc.frames.count - 1)] = newValue }
    }

    /// Top of the stack first, which is how the layers panel reads.
    var layersTopFirst: [Layer] { frame.layers.reversed() }

    /// Every selected layer, wherever in the document it lives. Selection spans
    /// frames so that paint can be applied to a whole drawing at once — the one
    /// thing per-frame layer stacks otherwise make tedious, since the same shape
    /// exists once per frame.
    var selectedLayers: [Layer] {
        doc.frames.flatMap { f in f.layers.flatMap { $0.flattened() }.filter { selection.contains($0.id) } }
    }

    /// The selection restricted to the frame on screen. The canvas and the
    /// frame-scoped operations use this, so a cross-frame selection cannot draw
    /// outlines for shapes that are not visible or enable buttons that no-op.
    var selectedLayersHere: [Layer] {
        frame.layers.flatMap { $0.flattened() }.filter { selection.contains($0.id) }
    }

    /// Whether anything selected has paint of its own to set.
    ///
    /// A plain group has none: its children each keep theirs, and the group's
    /// own fill, stroke and width are never read — it is a name and a place in
    /// the stack, not a shape. A boolean is the other way about, painting its
    /// children in its own colour, so it counts. A selection holding both a
    /// group and a shape counts too, because the shape will take the paint.
    var selectionTakesPaint: Bool {
        selectedLayersHere.contains { !$0.isGroup }
    }

    /// One layer of the frame on screen, by id, to any depth. Nil for a layer
    /// that belongs to another frame — which a hover can outlive, since the row
    /// under the pointer does not move when the frame does.
    func layerHere(_ id: UUID) -> Layer? {
        frame.layers.flatMap { $0.flattened() }.first { $0.id == id }
    }

    private var allLayerIDs: Set<UUID> {
        Set(doc.frames.flatMap { $0.layers.flatMap { $0.flattened() } }.map { $0.id })
    }

    /// How many frames a set of layers reaches. Allocation-free and early-exiting,
    /// because the layers panel asks this once per row.
    func frameSpan(of ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        func hit(_ layers: [Layer]) -> Bool {
            for l in layers {
                if ids.contains(l.id) { return true }
                if case .boolean(_, let kids) = l.content, hit(kids) { return true }
            }
            return false
        }
        return doc.frames.reduce(0) { $0 + (hit($1.layers) ? 1 : 0) }
    }

    func selectionReaches(_ frame: Frame) -> Bool {
        frame.layers.contains { $0.flattened().contains { selection.contains($0.id) } }
    }

    /// Whether the selection reaches past the frame on screen. The panel can only
    /// ever highlight rows of this frame, so a row whose twins are also selected
    /// has to say so itself.
    var selectionSpansFrames: Bool { frameSpan(of: selection) > 1 }

    func selectAllInFrame() {
        selection = Set(frame.layers.flatMap { $0.flattened() }.map { $0.id })
        selectedNodes = []
    }

    func selectAllInAllFrames() {
        selection = allLayerIDs
        selectedNodes = []
    }

    func deselectAll() {
        selection = []
        selectedNodes = []
    }

    // MARK: The same layer, in every frame

    /// Every layer in the document that is *this* layer — the same element of the
    /// drawing, once per frame.
    ///
    /// A track is exact. It is stamped on both sides when a frame is duplicated or
    /// a shape is pasted onto another frame, so it does not care what the layer is
    /// called or where in the stack it sits.
    ///
    /// Layers from a document saved before tracks existed have none, and fall back
    /// to **name plus position in the stack** — which is all two copies of a layer
    /// share when nothing recorded that they were copies. Name alone would not do:
    /// those documents were written before layers were numbered, so shapes are
    /// bare "Shape", "Line", "Rectangle" or "Ellipse" and a frame routinely holds
    /// four with the same name that matching on it would select together.
    func linked(_ id: UUID) -> Set<UUID> {
        guard let here = LayerTree.find(id, in: frame.layers) else { return [id] }

        if let track = here.track {
            var out: Set<UUID> = [id]
            for f in doc.frames {
                collect(track: track, in: f.layers, into: &out)
            }
            return out
        }

        guard let path = path(of: id, in: frame.layers) else { return [id] }
        var out: Set<UUID> = [id]
        for f in doc.frames {
            guard let twin = layer(at: path, in: f.layers),
                  twin.name == here.name, twin.isBoolean == here.isBoolean else { continue }
            out.insert(twin.id)
        }
        return out
    }

    private func collect(track: UUID, in layers: [Layer], into out: inout Set<UUID>) {
        for l in layers {
            if l.track == track { out.insert(l.id) }
            if case .boolean(_, let kids) = l.content { collect(track: track, in: kids, into: &out) }
        }
    }

    /// The index of each step down the tree to a layer — its address within a
    /// frame, which is the half of the fallback match that name cannot provide.
    private func path(of id: UUID, in layers: [Layer]) -> [Int]? {
        for (i, l) in layers.enumerated() {
            if l.id == id { return [i] }
            if let deeper = path(of: id, in: l.children) { return [i] + deeper }
        }
        return nil
    }

    private func layer(at path: [Int], in layers: [Layer]) -> Layer? {
        guard let i = path.first, layers.indices.contains(i) else { return nil }
        return path.count == 1 ? layers[i] : layer(at: Array(path.dropFirst()), in: layers[i].children)
    }

    /// Selects one layer in every frame it exists in, so paint, a move, a rename or
    /// a delete is one action rather than one per frame. ⌥-click a row, or ⌥⌘L.
    func selectLinked(_ id: UUID, additive: Bool = false) {
        let ids = linked(id)
        selection = additive ? selection.union(ids) : ids
        selectedNodes = []
        let n = frameSpan(of: ids)
        let name = LayerTree.find(id, in: frame.layers)?.name ?? "Layer"
        note(n > 1 ? "\(name) selected in \(n) frames" : "\(name) is only on this frame")
    }

    /// ⌥⌘L acts on whichever single layer of this frame is selected, so it is
    /// idempotent: running it on an already-linked selection changes nothing.
    var canSelectLinked: Bool { doc.frames.count > 1 && selectedLayersHere.count == 1 }

    func selectLinkedFromSelection() {
        guard let id = selectedLayersHere.first?.id else { return }
        selectLinked(id)
    }

    /// Gives a layer and its children a track if they have none, so copies made
    /// from it can share one. A layer only needs a track once it exists in more
    /// than one frame, which is why they are stamped here rather than at birth.
    private func tracked(_ layer: Layer) -> Layer {
        var l = layer
        if l.track == nil { l.track = UUID() }
        // Every child, not just a boolean's. A group holds layers that stand on
        // their own — they are selected, painted and linked one at a time — so
        // leaving them out meant a copied group's children were the only layers
        // in the document that could not be linked across frames.
        l.children = l.children.map(tracked)
        return l
    }

    /// Like `tracked`, but always a fresh track — for copies that form a family of
    /// their own rather than joining the one they came from.
    private func retracked(_ layer: Layer) -> Layer {
        var l = layer
        l.track = UUID()
        l.children = l.children.map(retracked)
        return l
    }

    /// Drops the track from a copy landing on a frame that already has that track.
    /// A track means "the same layer, once per frame", so a second copy on one
    /// frame is a new layer rather than another instance of the same one.
    private func untangled(_ layers: [Layer], landingOn frame: Frame) -> [Layer] {
        var present: Set<UUID> = []
        for l in frame.layers.flatMap({ $0.flattened() }) { if let t = l.track { present.insert(t) } }
        guard !present.isEmpty else { return layers }
        func strip(_ layer: Layer) -> Layer {
            var l = layer
            if let t = l.track, present.contains(t) { l.track = nil }
            l.children = l.children.map(strip)
            return l
        }
        return layers.map(strip)
    }

    /// The folder the document is filed under, or nil at the top level — and nil
    /// for one that has never been written, which has no folder yet to be in.
    var documentFolder: String? {
        guard let url = fileURL else { return nil }
        let parent = url.deletingLastPathComponent()
        guard parent.standardizedFileURL != Self.creationsFolder.standardizedFileURL
        else { return nil }
        return parent.lastPathComponent
    }

    /// The name on the title bar, and the name the next autosave will use.
    ///
    /// A document with no file yet shows the name it *will* be given rather than
    /// a placeholder, because with autosave on that name is a second away and
    /// showing `Untitled` first would make it look as though it had changed.
    var documentName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? chosenName ?? defaultName
    }

    /// `Untitled-2026-09-04, 19-34`, from the creation stamp. Sortable, so a
    /// folder of sketches lists in the order they were started, and fixed for the
    /// life of the document.
    private var defaultName: String {
        let f = DateFormatter()
        // Fixed locale: a filename should not come out differently for someone
        // whose region formats dates another way.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd', 'HH-mm"
        return "Untitled-" + f.string(from: created)
    }

    /// Every drawable shape in the frame, including the ones inside boolean
    /// groups — a live boolean is only worth having if you can still reshape
    /// either side of it in place.
    var editableShapes: [Layer] {
        func walk(_ layers: [Layer]) -> [Layer] {
            layers.filter { $0.visible }.flatMap { l -> [Layer] in
                l.hasChildren ? walk(l.children) : [l]
            }
        }
        return walk(frame.layers)
    }

    /// What the pen is working on.
    ///
    /// Everything in the frame when nothing is picked, and just the selection —
    /// with whatever is under it — when something is. Reaching for the pen with
    /// a shape selected is a statement about which shape you mean to edit, and
    /// covering the artboard with every other shape's points buries it.
    ///
    /// One list, used for what is drawn, what can be grabbed *and* what a drag
    /// can join onto. Narrowing only the drawing would leave points you can
    /// catch but cannot see, and endpoints that snap to somewhere invisible.
    var penShapes: [Layer] {
        let all = editableShapes
        guard !selection.isEmpty else { return all }
        let live = handleShapes
        let picked = all.filter { live.contains($0.id) }
        // A selection that reaches only into other frames leaves nothing here to
        // edit; the pen falls back to the whole frame rather than to nothing.
        return picked.isEmpty ? all : picked
    }

    /// Shapes whose handles should be showing: the selection, and anything under
    /// it, so selecting a boolean group exposes the points of its children.
    var handleShapes: Set<UUID> {
        var out: Set<UUID> = []
        func walk(_ layers: [Layer], inherited: Bool) {
            for l in layers {
                let active = inherited || selection.contains(l.id)
                if active { out.insert(l.id) }
                walk(l.children, inherited: active)
            }
        }
        walk(frame.layers, inherited: false)
        return out
    }

    // MARK: Repositioning the reference

    func beginReposition() {
        guard doc.reference != nil, !repositioning else { return }
        stop()
        // One undo step for the whole mode, taken before anything moves. Every
        // drag inside it writes to the same state, so a step per drag would make
        // ⌘Z walk back through a gesture nobody thinks of as several.
        commit()
        // The card this was pressed from goes too, and does not come back: the
        // mode clears the screen so the reference is the only thing on it, and
        // a panel that reappeared on the way out would undo that at the moment
        // you are looking at the result. Repositioning again is the same three
        // clicks it was the first time.
        stripPopup = nil
        referenceSnapshot = doc.reference
        panelsBeforeReposition = (showLayers, showTools)
        showLayers = false
        showTools = false
        selection = []
        selectedNodes = []
        repositioning = true
    }

    func endReposition(keep: Bool) {
        guard repositioning else { return }
        if !keep { doc.reference = referenceSnapshot }
        referenceSnapshot = nil
        // Back to whatever was open before, not to both open: the mode borrowed
        // the panels and should return them as it found them.
        if let panels = panelsBeforeReposition {
            showLayers = panels.layers
            showTools = panels.tools
        }
        panelsBeforeReposition = nil
        repositioning = false
    }

    /// Ends a suspended stretch with a single refresh.
    func resumePublishing() {
        guard suspendsPublishing else { return }
        suspendsPublishing = false
        objectWillChange.send()
    }

    /// Marks the current frame's cached thumbnail stale. Dragging a shape bypasses
    /// the model's own mutators, so it has to say so itself.
    func invalidateThumbnail() { thumbCache[frame.id] = nil }

    // MARK: Undo

    func commit() {
        undoStack.append(doc)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(doc)
        doc = previous
        clampAll()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(doc)
        doc = next
        clampAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func clampAll() {
        frameIndex = min(frameIndex, doc.frames.count - 1)
        selection = selection.intersection(allLayerIDs)
        selectedNodes = selectedNodes.filter { selection.contains($0.layer) }
        renamingLayer = nil
        thumbCache.removeAll()
    }

    private func touched() { thumbCache[frame.id] = nil }

    // MARK: Layers

    func add(_ layer: Layer, select: Bool = true) {
        commit()
        frame.layers.append(layer)
        if select { selection = [layer.id]; selectedNodes = [] }
        touched()
    }

    /// The next free number for a kind of layer, within the frame on screen.
    ///
    /// Per frame, because the layers panel only ever shows one: a list reading
    /// "Rectangle 7, Rectangle 12" with no sign of one through six looks as
    /// though something has gone missing. Nested layers count too, so releasing
    /// a boolean group cannot spill a duplicate name into the frame.
    ///
    /// It takes the highest number in use and adds one rather than filling gaps.
    /// Reusing a freed number would hand a deleted layer's name to a different
    /// one, which is worse than a gap in the sequence.
    func nextName(_ base: String) -> String {
        var highest = 0
        for layer in frame.layers.flatMap({ $0.flattened() }) {
            guard layer.name == base || layer.name.hasPrefix(base + " ") else { continue }
            // A bare "Rectangle" from a document written before numbering counts
            // as the first one, so the next is two rather than a second one.
            let tail = layer.name.dropFirst(base.count).trimmingCharacters(in: .whitespaces)
            highest = max(highest, tail.isEmpty ? 1 : (Int(tail) ?? 0))
        }
        return "\(base) \(highest + 1)"
    }

    /// A shape born from the current paint. An unclosed path gets no fill, so a
    /// construction line stays a line until it encloses something.
    ///
    /// `base` is the kind — "Rectangle", "Circle", "Line", "Shape" — and the
    /// number is appended here so no call site can create an unnumbered layer.
    func newLayer(_ shape: Shape2D, name base: String) -> Layer {
        var layer = Layer(name: nextName(base),
                          content: .shape(shape),
                          fill: (fillEnabled && shape.hasFillableArea) ? fillColor : nil,
                          stroke: strokeEnabled ? strokeColor : nil,
                          strokeWidth: strokeWidth)
        // Stamped like the paint is: the dials describe the next line as much as
        // the selected one, so what is set when you draw is what you get.
        if !wiggle.isIdle { layer.wiggle = wiggle }
        if nib.isPencil { layer.nib = nib }
        return layer
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        commit()
        for i in doc.frames.indices {
            var layers = doc.frames[i].layers
            let taken = LayerTree.extract(selection, from: &layers)
            guard !taken.isEmpty else { continue }
            doc.frames[i].layers = layers
            thumbCache[doc.frames[i].id] = nil
        }
        selection = []; selectedNodes = []
    }

    /// Leaves a copy of everything selected exactly where it is and selects the
    /// copies, so the drag that follows takes the copy and the original stays put.
    ///
    /// This is the model half of ⌥-drag. It is deliberately *in place* rather
    /// than offset: the offset is the drag, and a copy that jumped before the
    /// hand moved would make a click-with-⌥ into an edit of its own.
    ///
    /// Each copy lands directly in front of the layer it came from, in that
    /// layer's own stack — so duplicating something inside a group leaves the
    /// copy in that group, beside what it was copied from.
    ///
    /// A fresh *track*, not the original's: a duplicate is a new element of the
    /// drawing, where a track means "this same element, once per frame".
    /// Inheriting it would make ⌥-clicking either copy select both of them, in
    /// every frame, ever after.
    ///
    /// Only this frame. The selection can span frames, but a duplicate is a new
    /// thing at a place you are pointing at, and there is no such place on a
    /// frame you cannot see.
    @discardableResult
    func duplicateSelectionInPlace() -> Bool {
        // Outermost only: with a group and something inside it both selected,
        // copying both would put a copy of the child inside the copied group
        // *and* a second loose copy beside it.
        let targets = LayerTree.outermost(selection, in: frame.layers)
        guard !targets.isEmpty else { return false }
        commit()

        var layers = frame.layers
        var copies: Set<UUID> = []
        for target in targets {
            let fresh = reidentified(retracked(target))
            guard LayerTree.insert(fresh, above: target.id, in: &layers) else { continue }
            copies.insert(fresh.id)
        }
        guard !copies.isEmpty else { return false }

        frame.layers = layers
        selection = copies
        selectedNodes = []
        touched()
        return true
    }

    /// Applies a change to a set of layers wherever in the document they live, in
    /// one undo step. This is what makes a selection that spans frames worth
    /// having: the same element exists once per frame, so changing it is one edit.
    private func apply(to ids: Set<UUID>, _ change: (inout Layer) -> Void) {
        guard !ids.isEmpty else { return }
        commit()
        for i in doc.frames.indices {
            var layers = doc.frames[i].layers
            var changed = false
            for id in ids where LayerTree.mutate(id, in: &layers, change) { changed = true }
            guard changed else { continue }
            doc.frames[i].layers = layers
            thumbCache[doc.frames[i].id] = nil
        }
    }

    /// The same, but without pushing undo and without touching the thumbnails —
    /// what a slider needs *between* the start of a drag and the end of it.
    private func applyLive(to ids: Set<UUID>, _ change: (inout Layer) -> Void) {
        guard !ids.isEmpty else { return }
        for i in doc.frames.indices {
            var layers = doc.frames[i].layers
            var changed = false
            for id in ids where LayerTree.mutate(id, in: &layers, change) { changed = true }
            guard changed else { continue }
            doc.frames[i].layers = layers
        }
    }

    /// A slider drag is about to write to the document.
    ///
    /// The sliders that paint — width and opacity — apply on every step so the
    /// canvas answers under your hand rather than at the end. Undo cannot follow
    /// suit: a drag is a hundred changes and a single edit, so the snapshot is
    /// taken once, here, and the steps themselves push nothing.
    func beginSliderEdit() {
        guard !selection.isEmpty else { return }
        commit()
    }

    /// And the end of one. The frame thumbnails were left stale while it ran:
    /// re-rasterising every tile on every step is thirty renders a step for
    /// pictures nobody is watching while they watch the canvas.
    func endSliderEdit() {
        guard !selection.isEmpty else { return }
        thumbCache.removeAll()
    }

    /// Hides the layer everywhere the selection reaches, so a linked layer hides in
    /// every frame at once. An unselected row toggles only itself — clicking one
    /// row's eye should not act on a selection you were not pointing at.
    func setVisible(_ id: UUID, _ on: Bool) {
        apply(to: selection.contains(id) ? selection : [id]) { $0.visible = on }
    }

    /// ⌘R has something to act on when this frame's share of the selection is a
    /// single layer — which is also true of a linked selection, one layer per frame.
    var canRename: Bool { selectedLayersHere.count == 1 }

    /// Opens the rename field on one named layer — what the row's context menu does,
    /// which is why it takes an id rather than reading the selection.
    func beginRename(_ id: UUID) { renamingLayer = id }

    /// Opens it on the selection, which is what ⌘R means. Reads this frame's
    /// member, since a linked selection holds one layer per frame and only the row
    /// on screen has a field to open.
    func beginRenameSelection() {
        guard let id = selectedLayersHere.first?.id, selectedLayersHere.count == 1 else { return }
        renamingLayer = id
    }

    /// Renames every layer the selection reaches when the row being renamed is part
    /// of it, so naming a linked layer names it in every frame. Not doing so was
    /// what made a name useless as a way of finding the same layer again: the name
    /// would be right on the frame you typed it on and stale on all the others.
    func rename(_ id: UUID, _ name: String) {
        let final = name.isEmpty ? nextName("Shape") : name
        apply(to: selection.contains(id) ? selection : [id]) { $0.name = final }
    }

    /// One stack, however many layers of it are selected.
    ///
    /// Depth is no longer the test — a shape inside a group reorders inside that
    /// group, which is the only place "forward" could mean anything for it.
    /// What is still required is that the whole selection sits in *one* stack: a
    /// selection straddling a group's edge has two orders to step along and no
    /// way to choose between them. A linked selection qualifies, being one set
    /// of siblings per frame.
    var canReorder: Bool {
        !selection.isEmpty && LayerTree.stacks(of: selection, in: frame.layers).count == 1
    }

    /// The stack a layer belongs to, top of the panel's list first. What the
    /// panel needs to know while a row is being dragged: these are the rows the
    /// drag can land between.
    func siblings(of id: UUID) -> [Layer] {
        let paths = LayerTree.stacks(of: [id], in: frame.layers)
        guard let path = paths.first else { return [] }
        var out: [Layer] = []
        var layers = frame.layers
        LayerTree.mutateStack(at: path, in: &layers) { out = $0.reversed() }
        return out
    }

    /// Moves the selection one place along its stack, in every frame it reaches,
    /// so a linked layer keeps the same depth throughout. A frame whose members
    /// are already at the end of their stack simply stays put.
    func reorderSelection(up: Bool) {
        guard canReorder else { return }
        commit()
        restack { LayerTree.step(selection, in: &$0, up: up) }
    }

    /// The same, but the whole way — and to the ends of the layer's *own* stack,
    /// which for a shape inside a group is the front and back of the group
    /// rather than of the frame.
    func moveSelectionToEnd(front: Bool) {
        guard canReorder else { return }
        commit()
        restack { LayerTree.moveToEnd(selection, in: &$0, front: front) }
    }

    /// Moves the selection into a named stack — the frame's own, or any group's,
    /// at any depth — landing it at a place counted from the top of the panel's
    /// list.
    ///
    /// This is the drag's move, and unlike the menu's it is not a *reorder*: the
    /// layers are pulled out of wherever they were and put down together
    /// somewhere else, so it works for a selection spread across several stacks
    /// and for a destination that is not the one they came from. Which is what
    /// makes dragging a layer into a group, or out of one, the same gesture as
    /// dragging it up two rows.
    ///
    /// No `commit` of its own: the panel commits once, at the drop.
    func moveSelection(into path: [UUID], fromTop ordinal: Int) {
        guard !selection.isEmpty else { return }
        for fi in doc.frames.indices {
            var layers = doc.frames[fi].layers
            let taken = LayerTree.extract(selection, from: &layers)
            guard !taken.isEmpty else { continue }
            // Written back only if the destination was found. A group can be
            // missing from a frame the selection does not reach the same way,
            // and a frame that lost its layers with nowhere to put them would be
            // a frame the drag had quietly emptied.
            var landed = false
            LayerTree.mutateStack(at: path, in: &layers) { stack in
                stack.insert(contentsOf: taken,
                             at: min(max(0, stack.count - ordinal), stack.count))
                landed = true
            }
            guard landed else { continue }
            doc.frames[fi].layers = layers
            thumbCache[doc.frames[fi].id] = nil
        }
    }

    /// Runs a reorder on the one stack the selection occupies, in every frame
    /// the selection reaches.
    ///
    /// The stack is found per frame rather than once: a linked layer is the same
    /// element of the drawing in each frame, but nothing guarantees it is at the
    /// same index — or that every frame has it at all.
    private func restack(_ change: (inout [Layer]) -> Bool) {
        for fi in doc.frames.indices {
            var layers = doc.frames[fi].layers
            let paths = LayerTree.stacks(of: selection, in: layers)
            guard paths.count == 1, let path = paths.first else { continue }
            var moved = false
            LayerTree.mutateStack(at: path, in: &layers) { moved = change(&$0) }
            guard moved else { continue }
            doc.frames[fi].layers = layers
            thumbCache[doc.frames[fi].id] = nil
        }
    }

    /// Moves every selected layer, in every frame it reaches.
    ///
    /// Geometry was the last thing that stayed local to the frame on screen. A
    /// linked layer is the same element in each frame, so nudging it on one frame
    /// only would pull apart the very thing that made it linked — and repositioning
    /// a held-still element across a dozen frames by hand is the tedium this
    /// removes. Selecting within one frame is still how you move one frame's shape.
    func translateSelection(by d: CGPoint) {
        guard !selection.isEmpty else { return }
        for i in doc.frames.indices {
            var layers = doc.frames[i].layers
            var changed = false
            for id in selection where LayerTree.mutate(id, in: &layers, { $0 = $0.translated(by: d) }) {
                changed = true
            }
            guard changed else { continue }
            doc.frames[i].layers = layers
            thumbCache[doc.frames[i].id] = nil
        }
    }

    /// Transforms every selected layer, in every frame it reaches.
    ///
    /// One method for stretching and turning alike, because in the end both are
    /// an affine map of the anchors. Same reach rule as `translateSelection`, and
    /// for the same reason: a linked layer is the same element in each frame, so
    /// resizing or turning it on one frame only would pull apart the very thing
    /// that made it linked. Select within a single frame and it is local again.
    ///
    /// `turningBy` is all a turn needs on top — the angle is added to each layer's
    /// recorded orientation, so the box knows which way up the shape is the next
    /// time it is drawn.
    ///
    /// Works from `originals` rather than the live geometry, so the transform is
    /// **absolute** rather than compounding over a drag. That is what lets a grip
    /// be dragged back through its anchor and out the other side — the shape
    /// mirrors, and coming back restores it, where a running multiplication would
    /// have lost it for good at the instant it passed through zero. A turn needs
    /// it too, or going round the circle would accumulate rounding the whole way.
    func transformSelection(_ originals: [UUID: Layer],
                            by m: CGAffineTransform,
                            turningBy delta: CGFloat = 0) {
        guard !selection.isEmpty else { return }
        for i in doc.frames.indices {
            var layers = doc.frames[i].layers
            var changed = false
            for id in selection {
                guard let original = originals[id] else { continue }
                if LayerTree.mutate(id, in: &layers, {
                    $0 = original.transformed(by: m).reoriented(by: delta)
                }) { changed = true }
            }
            guard changed else { continue }
            doc.frames[i].layers = layers
            thumbCache[doc.frames[i].id] = nil
        }
    }

    /// Every selected layer as it stands, keyed by id, across the whole document.
    /// Ids are unique per layer even between frames — linked layers share a
    /// `track`, never an id — so one flat dictionary addresses all of them.
    func selectionSnapshot() -> [UUID: Layer] {
        var out: [UUID: Layer] = [:]
        for f in doc.frames {
            for l in f.layers.flatMap({ $0.flattened() }) where selection.contains(l.id) {
                out[l.id] = l
            }
        }
        return out
    }

    /// The box the transform grips sit on: everything the selection reaches *in
    /// the frame on screen*, since that is the only geometry the canvas can show.
    ///
    /// Turned to match the shapes when they agree about which way up they are, so
    /// the box follows a rotated shape rather than standing upright around it. The
    /// extent is measured in that turned frame, which is what keeps it snug
    /// instead of being the upright bounds of a diagonal shape.
    var selectionBox: OrientedBox? {
        let here = selectedLayersHere
        guard !here.isEmpty else { return nil }
        let aabb = here.reduce(CGRect.null) { $0.union(Render.bounds($1)) }
        guard !aabb.isNull else { return nil }
        let pivot = CGPoint(x: aabb.midX, y: aabb.midY)

        // Only when every selected layer agrees. A selection of shapes turned
        // different ways has no shared axis to stretch along, so it gets the
        // upright box — the honest answer, rather than picking one shape's angle
        // and shearing the rest of the selection along it.
        guard let angle = commonAxisAngle(here) else {
            return OrientedBox(local: aabb, pivot: pivot, angle: 0)
        }
        let back = CGAffineTransform.about(pivot, .rotation(-angle))
        let local = here.reduce(CGRect.null) { $0.union(Render.bounds($1.transformed(by: back))) }
        return OrientedBox(local: local.isNull ? aabb : local, pivot: pivot, angle: angle)
    }

    /// The one angle a set of layers is turned by, or `nil` when they disagree —
    /// and `nil` too when every one of them is upright, which is the same thing
    /// as having no turn to honour.
    private func commonAxisAngle(_ layers: [Layer]) -> CGFloat? {
        guard let first = layers.first?.axisAngle, abs(first) > 1e-9 else { return nil }
        return layers.allSatisfy { abs($0.axisAngle - first) < 1e-9 } ? first : nil
    }


    // MARK: Paint

    /// Colour is never baked into geometry, so this works on a plain shape and on
    /// a boolean result alike — a boolean paints in its own colour, and its
    /// children keep theirs for when the operation is released.
    func applyPaint(_ change: (inout Layer) -> Void) { apply(to: selection, change) }

    func setFill(_ c: RGBA?) {
        fillColor = c ?? fillColor
        fillEnabled = c != nil
        applyPaint { $0.fill = c }
    }

    /// What the swatch grid shows: the built-in nine, then whatever this file
    /// has added. Built-ins are never removed, so a document cannot end up with
    /// an empty palette and no way back to one.
    var palette: [RGBA] { RGBA.swatches + (doc.swatches ?? []) }

    /// Adds a colour to this file's palette.
    ///
    /// Alpha is kept. The picker has an opacity slider, so a swatch can be less
    /// than solid on purpose — flattening it here would quietly discard half of
    /// what the plus tile just asked the user to choose.
    func addSwatch(_ c: RGBA) {
        guard !palette.contains(c) else { return }
        commit()
        doc.swatches = (doc.swatches ?? []) + [c]
    }

    /// Repoints one of this file's own swatches at a new colour. Built-ins do
    /// not reach here — they are the app's constants and the grid offers no way
    /// to edit them.
    /// Seeds the card and opens it.
    func beginPicking(_ target: PaintTarget, from colour: RGBA) {
        pickerDraft = colour
        picking = target
    }

    /// Shuts the card, writing whatever it was holding.
    ///
    /// Fill and stroke were applied on every step, the way the system panel
    /// used to — you want to see the drawing change under your hand. A swatch
    /// is written once, here, because it is a thing you end up with and an
    /// undo step per mouse move would bury the stack.
    func endPicking() {
        switch picking {
        case .swatch(let old): editSwatch(old, to: pickerDraft)
        case .newSwatch:       addSwatch(pickerDraft)
        case .fill, .stroke, .background, nil: break
        }
        picking = nil
    }

    func editSwatch(_ old: RGBA, to new: RGBA) {
        guard var list = doc.swatches, let i = list.firstIndex(of: old),
              new != old, !palette.contains(new) else { return }
        commit()
        list[i] = new
        doc.swatches = list
    }

    func removeSwatch(_ c: RGBA) {
        guard var list = doc.swatches, let i = list.firstIndex(of: c) else { return }
        commit()
        list.remove(at: i)
        // Back to nil rather than an empty array, so a file that has had its
        // additions removed encodes exactly like one that never had any.
        doc.swatches = list.isEmpty ? nil : list
    }

    func setStroke(_ c: RGBA?) {
        strokeColor = c ?? strokeColor
        strokeEnabled = c != nil
        applyPaint { $0.stroke = c }
    }

    /// Opacity reaches wherever the selection does, and a group takes it as a
    /// unit — the group's children keep their own, and the two multiply, which is
    /// what makes fading a whole group out one edit rather than one per child.
    /// Live: applied on every step of the drag, with undo pushed once by
    /// `beginSliderEdit` and the thumbnails caught up by `endSliderEdit`.
    func setOpacity(_ a: Double) {
        opacity = a
        applyLive(to: selection) { $0.alpha = a }
    }

    // MARK: Wiggle

    /// How far the line wanders, how tightly, and how much of that wander is
    /// made afresh on every frame.
    ///
    /// Live rather than committed per step, exactly as opacity is: the drag
    /// pushes one undo at its start and the drawing answers the whole way.
    func setWiggle(_ w: Wiggle) {
        wiggle = w
        applyLive(to: selection) { $0.wiggle = w.isIdle ? nil : w }
    }

    /// What the dials should read. The selection's, where there is one — the
    /// wander belongs to a line that already exists as much as to the next one —
    /// and otherwise whatever was last set.
    var selectionWiggle: Wiggle {
        selectedLayersHere.first(where: { $0.wiggle != nil })?.wiggle ?? wiggle
    }

    /// Live, as the paint and the wander are: the drawing answers under the hand.
    func setNib(_ n: Nib) {
        nib = n
        applyLive(to: selection) { $0.nib = n == .pen ? nil : n }
    }

    /// What the picker should read: the selection's, where there is one.
    var selectionNib: Nib {
        selectedLayersHere.first(where: { $0.nib != nil })?.nib ?? nib
    }

    /// The opacity to show. A single value when the selection agrees, and the
    /// first layer's otherwise — a slider cannot show two numbers, and blanking it
    /// would be a control that says nothing rather than one that says *this is
    /// where the drag starts from*.
    var selectionOpacity: Double { selectedLayersHere.first?.alpha ?? 1 }

    /// The blend mode reaches wherever the selection does, and a group takes it
    /// as a unit for the same reason opacity does — a multiplied group meets the
    /// backdrop once, rather than its children multiplying with each other on
    /// the way down.
    ///
    /// Not live, unlike opacity and stroke width: this is picked from a menu
    /// rather than dragged, so there is one value and one edit.
    func setBlend(_ b: Blend) {
        apply(to: selection) { $0.blending = b }
    }

    /// The mode to show. The selection's when it agrees, and the first layer's
    /// otherwise — the same rule the opacity slider follows, and for the same
    /// reason: a control that says nothing says less than one that says where
    /// the next edit starts from.
    var selectionBlend: Blend { selectedLayersHere.first?.blending ?? .normal }

    /// Live, for the same reason `setOpacity` is.
    func setStrokeWidth(_ w: CGFloat) {
        strokeWidth = w
        applyLive(to: selection) { $0.strokeWidth = w }
    }

    // MARK: Grouping

    /// The stack a wrapper would be built in, when the selection names one and
    /// that stack will take a wrapper.
    ///
    /// Depth is not the test. A group is built *where the selection already
    /// lives*, so a run of shapes inside a group becomes a group inside that
    /// group, however many groups deep that is. Two things are still required.
    ///
    /// The members must be siblings — a selection straddling a group's edge
    /// names two stacks and no way to choose between them, the same objection
    /// `canReorder` makes to stepping one.
    ///
    /// And the stack must not be a boolean's. A boolean's children are its
    /// *inputs*, not a free stack, and a plain group has no region of its own —
    /// so a group standing where an input should be would drop silently out of
    /// the operation and change the result. Grouping inside a boolean is
    /// therefore refused rather than allowed to half-work.
    private var wrappableStack: [UUID]? {
        guard !selection.isEmpty else { return nil }
        let stacks = LayerTree.stacks(of: selection, in: frame.layers)
        guard stacks.count == 1, let path = stacks.first else { return nil }
        if let owner = path.last, LayerTree.find(owner, in: frame.layers)?.isBoolean == true {
            return nil
        }
        return path
    }

    /// One or more siblings of the frame on screen, at any depth. Grouping a
    /// single layer is allowed and useful — it is how you start a group you mean
    /// to fill.
    var canGroup: Bool { wrappableStack != nil }

    /// Wraps the selected sibling layers in a plain group, inside whatever stack
    /// they were already in.
    ///
    /// Unlike a boolean, the group does nothing to what is inside it: the
    /// children keep their own paint and their own order, and the group is a name
    /// and a place in the stack. It lands where the topmost member was, so the
    /// stack does not reshuffle around it.
    func groupSelection() {
        guard let path = wrappableStack else { return }
        commit()

        // No fill and no stroke: a group paints nothing of its own, and giving it
        // colours would put two swatches in the panel for one thing and leave the
        // group's looking like a lie.
        var group = Layer(name: nextName("Group"), content: .group([]), fill: nil, stroke: nil)
        var layers = frame.layers
        var made = false
        LayerTree.mutateStack(at: path, in: &layers) { stack in
            let members = stack.filter { selection.contains($0.id) }
            guard !members.isEmpty, let insertAt = stack.lastIndex(where: {
                selection.contains($0.id)
            }) else { return }
            let index = max(0, insertAt - (members.count - 1))
            stack.removeAll { selection.contains($0.id) }
            group.content = .group(members)
            stack.insert(group, at: min(index, stack.count))
            made = true
        }
        guard made else { return }
        frame.layers = layers
        selection = [group.id]
        selectedNodes = []
        touched()
    }

    var canUngroup: Bool { selectedLayersHere.contains { $0.isGroup } }

    /// Unwraps a group, leaving its children where it was — at whatever depth it
    /// was, so a group released inside a group comes apart into the group that
    /// held it. The children come back selected, which is what you want next: it
    /// is the same set you grouped.
    func ungroupSelection() {
        let targets = selectedLayersHere.filter { $0.isGroup }
        guard !targets.isEmpty else { return }
        commit()
        var layers = frame.layers
        var freed: Set<UUID> = []
        for target in targets {
            guard let kids = LayerTree.unwrap(target.id, in: &layers) else { continue }
            freed.formUnion(kids.map { $0.id })
        }
        frame.layers = layers
        // Minus the groups themselves: releasing a group *and* a group inside it
        // frees the inner one into this set on the way past, and it is gone by
        // the end. A selection naming a layer that no longer exists leaves the
        // panel with a highlight on nothing.
        selection = freed.subtracting(targets.map { $0.id })
        selectedNodes = []
        touched()
    }

    // MARK: Booleans

    var canBoolean: Bool {
        guard let path = wrappableStack,
              let stack = LayerTree.stack(at: path, in: frame.layers) else { return false }
        return stack.filter { selection.contains($0.id) }.count >= 2
    }

    /// Wraps the selected sibling layers in a live boolean, inside whatever stack
    /// they were already in. The lowest one is the base and everything above it
    /// operates on it, so stacking a shape on top of another and hitting Subtract
    /// removes the overlap — nothing is flattened.
    func makeBoolean(_ op: BoolOp) {
        guard let path = wrappableStack else { return }
        commit()

        var layers = frame.layers
        let name = nextName(op.label)
        var made: UUID?
        LayerTree.mutateStack(at: path, in: &layers) { stack in
            let members = stack.filter { selection.contains($0.id) }
            guard members.count >= 2, let base = members.first,
                  let insertAt = stack.lastIndex(where: { selection.contains($0.id) })
            else { return }
            let index = max(0, insertAt - (members.count - 1))
            stack.removeAll { selection.contains($0.id) }
            let group = Layer(name: name,
                              content: .boolean(op, members),
                              fill: base.fill ?? (fillEnabled ? fillColor : nil),
                              stroke: base.stroke,
                              strokeWidth: base.strokeWidth)
            stack.insert(group, at: min(index, stack.count))
            made = group.id
        }
        guard let made else { return }
        frame.layers = layers
        selection = [made]
        selectedNodes = []
        touched()
    }

    func changeOp(_ id: UUID, to op: BoolOp) {
        commit()
        var layers = frame.layers
        LayerTree.mutate(id, in: &layers) { l in
            if case .boolean(_, let kids) = l.content { l.content = .boolean(op, kids); l.name = op.label }
        }
        frame.layers = layers
        touched()
    }

    var canRelease: Bool { selectedLayersHere.contains { $0.isBoolean } }

    /// Every layer between two of them in the panel's own order, inclusive.
    ///
    /// The order has to come from the panel: what lies "between" two rows depends
    /// on which groups are open, and only the panel knows that. So it hands the
    /// rows it is actually showing, top first, and this walks the span.
    func selectRange(in rows: [UUID], from anchor: UUID, to target: UUID) {
        guard let a = rows.firstIndex(of: anchor), let b = rows.firstIndex(of: target) else {
            selection = [target]
            selectedNodes = []
            return
        }
        selection = Set(rows[min(a, b)...max(a, b)])
        selectedNodes = []
    }

    /// Undoes the grouping, not the geometry — both sides come back editable, in
    /// the stack the boolean stood in.
    func releaseBoolean() {
        let targets = selectedLayersHere.filter { $0.isBoolean }
        guard !targets.isEmpty else { return }
        commit()
        var layers = frame.layers
        var freed: Set<UUID> = []
        for target in targets {
            guard let kids = LayerTree.unwrap(target.id, in: &layers) else { continue }
            freed.formUnion(kids.map { $0.id })
        }
        frame.layers = layers
        selection = freed.subtracting(targets.map { $0.id })
        touched()
    }

    // MARK: Nodes

    func node(_ ref: NodeRef) -> Anchor? {
        guard let l = LayerTree.find(ref.layer, in: frame.layers), let s = l.shape,
              s.subpaths.indices.contains(ref.subpath),
              s.subpaths[ref.subpath].anchors.indices.contains(ref.anchor) else { return nil }
        return s.subpaths[ref.subpath].anchors[ref.anchor]
    }

    /// Drop one layer, wherever it sits in the tree. The pen needs it to clear
    /// away a path abandoned after a single click, which is not a path.
    func deleteLayer(_ id: UUID) {
        var layers = frame.layers
        _ = LayerTree.extract([id], from: &layers)
        frame.layers = layers
        selection.remove(id)
        selectedNodes = selectedNodes.filter { $0.layer != id }
        touched()
    }

    /// Close a path the pen has just drawn: the last point joins back to the
    /// first, and both stay where they are.
    ///
    /// Deliberately *not* `closeSubpath`, which welds the two ends into a single
    /// anchor at their midpoint. That is right when you have dragged one endpoint
    /// onto the other and want no seam, and badly wrong here — the pen closes a
    /// path whose ends are nowhere near each other, so welding a triangle's first
    /// and last points collapses it into a line.
    ///
    /// Closing is also the moment the path first encloses an area. It was born
    /// without a fill, because filling an open path would have meant implicitly
    /// closing it on screen, so it takes the paint now that it really is closed.
    func closeDrawnPath(_ ref: NodeRef) {
        commit()
        var layers = frame.layers
        LayerTree.mutate(ref.layer, in: &layers) { l in
            guard var s = l.shape, s.subpaths.indices.contains(ref.subpath) else { return }
            var sp = s.subpaths[ref.subpath]
            guard sp.anchors.count >= 3, !sp.closed else { return }
            sp.closed = true
            sp.normalizeWinding()
            s.subpaths[ref.subpath] = sp
            l.content = .shape(s)
            if l.fill == nil, s.hasFillableArea, self.fillEnabled { l.fill = self.fillColor }
        }
        frame.layers = layers
        touched()
    }

    func editShape(_ id: UUID, _ body: (inout Shape2D) -> Void) {
        var layers = frame.layers
        LayerTree.mutate(id, in: &layers) { l in
            if var s = l.shape { body(&s); l.content = .shape(s) }
        }
        frame.layers = layers
        touched()
    }

    /// Endpoints of open subpaths, which are the only things that can be joined.
    func openEndpoints(excluding skip: NodeRef? = nil) -> [(NodeRef, CGPoint)] {
        var out: [(NodeRef, CGPoint)] = []
        for l in penShapes {
            guard let s = l.shape else { continue }
            for (si, sp) in s.subpaths.enumerated() where !sp.closed && sp.anchors.count >= 2 {
                for ai in [0, sp.anchors.count - 1] {
                    let ref = NodeRef(layer: l.id, subpath: si, anchor: ai)
                    if let skip, skip == ref { continue }
                    out.append((ref, sp.anchors[ai].p))
                }
            }
        }
        return out
    }

    /// Joins two open endpoints. If both belong to the same subpath the path
    /// closes instead — and a path that encloses an area gets filled, which is
    /// the moment a drawing stops being lines and becomes a shape.
    func join(_ a: NodeRef, _ b: NodeRef) {
        commit()

        if a.layer == b.layer && a.subpath == b.subpath {
            closeSubpath(a)
            touched()
            return
        }

        guard let layerA = LayerTree.find(a.layer, in: frame.layers), var shapeA = layerA.shape,
              let layerB = LayerTree.find(b.layer, in: frame.layers), let shapeB = layerB.shape,
              shapeA.subpaths.indices.contains(a.subpath),
              shapeB.subpaths.indices.contains(b.subpath) else { return }

        var spA = shapeA.subpaths[a.subpath]
        var spB = shapeB.subpaths[b.subpath]

        // Orient both so the meeting ends face each other: A's tail to B's head.
        if a.anchor == 0 { spA.reverse() }
        if b.anchor != 0 { spB.reverse() }

        // Weld the two endpoints into one anchor at their midpoint, keeping the
        // outgoing curvature from B so the seam does not kink.
        let mid = (spA.anchors[spA.anchors.count - 1].p + spB.anchors[0].p) * 0.5
        spA.anchors[spA.anchors.count - 1].p = mid
        spA.anchors[spA.anchors.count - 1].outH = spB.anchors[0].outH
        spA.anchors.append(contentsOf: spB.anchors.dropFirst())

        shapeA.subpaths[a.subpath] = spA
        var layers = frame.layers
        LayerTree.mutate(a.layer, in: &layers) { $0.content = .shape(shapeA) }

        // B's subpath moved; drop it, and drop the layer if that emptied it.
        if a.layer != b.layer {
            var shapeBRest = shapeB
            shapeBRest.subpaths.remove(at: b.subpath)
            if shapeBRest.subpaths.isEmpty {
                _ = LayerTree.extract([b.layer], from: &layers)
            } else {
                LayerTree.mutate(b.layer, in: &layers) { $0.content = .shape(shapeBRest) }
            }
        }
        frame.layers = layers

        selection = [a.layer]
        selectedNodes = []

        // Joining may have brought the far ends together too.
        let ref = NodeRef(layer: a.layer, subpath: a.subpath, anchor: 0)
        if let l = LayerTree.find(a.layer, in: frame.layers), let s = l.shape,
           s.subpaths.indices.contains(a.subpath) {
            let sp = s.subpaths[a.subpath]
            if sp.anchors.count >= 3,
               sp.anchors[0].p.dist(sp.anchors[sp.anchors.count - 1].p) < snapDistance {
                closeSubpath(ref)
            }
        }
        touched()
    }

    /// Closes a subpath and, if it now encloses an area and had no fill, paints
    /// it — the "connect it and it fills" behaviour.
    func closeSubpath(_ ref: NodeRef, pushUndo: Bool = false) {
        if pushUndo { commit() }
        var layers = frame.layers
        LayerTree.mutate(ref.layer, in: &layers) { l in
            guard var s = l.shape, s.subpaths.indices.contains(ref.subpath) else { return }
            var sp = s.subpaths[ref.subpath]
            guard sp.anchors.count >= 3, !sp.closed else { return }
            // Weld the two ends together before closing so there is no gap.
            let mid = (sp.anchors[0].p + sp.anchors[sp.anchors.count - 1].p) * 0.5
            sp.anchors[0].p = mid
            sp.anchors.removeLast()
            sp.closed = true
            sp.normalizeWinding()
            s.subpaths[ref.subpath] = sp
            l.content = .shape(s)
            if l.fill == nil, s.hasFillableArea, self.fillEnabled { l.fill = self.fillColor }
        }
        frame.layers = layers
        touched()
    }

    /// Adds a point part way along a segment, without changing the shape.
    ///
    /// The segment is split at `t` and both halves keep their own handles, so
    /// the curve through the new point is the curve that was already there. The
    /// two anchors either side have their facing handles rewritten, which is
    /// what makes that true — leaving them alone and only adding a point in the
    /// middle is the version that dents the drawing.
    @discardableResult
    func insertAnchor(layer: UUID, subpath: Int, segment: Int, at t: CGFloat) -> NodeRef? {
        guard let l = LayerTree.find(layer, in: frame.layers), let shape = l.shape,
              shape.subpaths.indices.contains(subpath),
              let cubic = shape.subpaths[subpath].segment(segment) else { return nil }
        let (left, right) = Curve.split(cubic, at: t)
        let end = shape.subpaths[subpath].segmentEnd(segment)

        commit()
        editShape(layer) { s in
            guard s.subpaths.indices.contains(subpath) else { return }
            var sp = s.subpaths[subpath]
            guard sp.anchors.indices.contains(segment), sp.anchors.indices.contains(end) else { return }
            sp.anchors[segment].outH = left.1 - left.0
            sp.anchors[end].inH = right.2 - right.3
            sp.anchors.insert(Anchor(left.3, inH: left.2 - left.3, outH: right.1 - right.0),
                              at: segment + 1)
            s.subpaths[subpath] = sp
        }
        return NodeRef(layer: layer, subpath: subpath, anchor: segment + 1)
    }

    /// Corner ↔ smooth. A corner has no handles; a smooth point takes them from
    /// the line between its neighbours, which is the same rule the freehand
    /// fitter uses, so a point converted by hand matches one that was drawn.
    func toggleSmooth(_ ref: NodeRef) {
        guard let l = LayerTree.find(ref.layer, in: frame.layers), let shape = l.shape,
              shape.subpaths.indices.contains(ref.subpath) else { return }
        let sp = shape.subpaths[ref.subpath]
        guard sp.anchors.indices.contains(ref.anchor) else { return }
        let a = sp.anchors[ref.anchor]
        let wasSmooth = a.inH.length > 0.5 || a.outH.length > 0.5

        commit()
        editShape(ref.layer) { s in
            var sp = s.subpaths[ref.subpath]
            let n = sp.anchors.count
            if wasSmooth {
                sp.anchors[ref.anchor].inH = .zero
                sp.anchors[ref.anchor].outH = .zero
            } else {
                let i = ref.anchor
                let prev = i == 0 ? (sp.closed ? sp.anchors[n - 1] : sp.anchors[i]) : sp.anchors[i - 1]
                let next = i == n - 1 ? (sp.closed ? sp.anchors[0] : sp.anchors[i]) : sp.anchors[i + 1]
                let tangent = (next.p - prev.p) * (1.0 / 6.0)
                sp.anchors[i].inH = -tangent
                sp.anchors[i].outH = tangent
            }
            s.subpaths[ref.subpath] = sp
        }
    }

    /// Turns an open subpath around when it is about to be drawn onward from its
    /// *first* point.
    ///
    /// Drawing always appends, so continuing from the start means reversing
    /// first. `Subpath.reverse` swaps each anchor's handles as it goes, so the
    /// curve is untouched and only its direction changes — which is why this is
    /// two lines rather than a second code path through the placement code.
    @discardableResult
    func turnForDrawing(_ ref: NodeRef) -> Bool {
        guard let l = LayerTree.find(ref.layer, in: frame.layers), let shape = l.shape,
              shape.subpaths.indices.contains(ref.subpath) else { return false }
        let sp = shape.subpaths[ref.subpath]
        guard !sp.closed, sp.anchors.count >= 1 else { return false }
        if ref.anchor == sp.anchors.count - 1 { return true }
        guard ref.anchor == 0 else { return false }
        commit()
        editShape(ref.layer) { s in s.subpaths[ref.subpath].reverse() }
        return true
    }

    func deleteSelectedNodes() {
        guard !selectedNodes.isEmpty else { return }
        commit()
        // Highest index first, so earlier removals do not shift later ones.
        for ref in selectedNodes.sorted(by: { $0.anchor > $1.anchor }) {
            editShape(ref.layer) { s in
                guard s.subpaths.indices.contains(ref.subpath) else { return }
                guard s.subpaths[ref.subpath].anchors.count > 2 else { return }
                guard s.subpaths[ref.subpath].anchors.indices.contains(ref.anchor) else { return }
                s.subpaths[ref.subpath].anchors.remove(at: ref.anchor)
            }
        }
        selectedNodes = []
        touched()
    }

    // MARK: Frames

    /// New frames copy the one you are on. Per-frame layer stacks mean nothing
    /// carries over on its own, and redrawing a whole scene each frame is no way
    /// to animate — hold ⌥ for a blank frame instead.
    func addFrame(duplicate: Bool = true) {
        commit()
        // Stamp the source before copying it: a track shared by both sides is what
        // makes "the same layer" resolvable across the two frames afterwards, and
        // duplicating is the moment one layer starts existing in more than one.
        if duplicate { frame.layers = frame.layers.map(tracked) }
        var copy = duplicate ? frame : Frame()
        copy.id = UUID()
        if duplicate { copy.layers = copy.layers.map(reidentified) }
        doc.frames.insert(copy, at: frameIndex + 1)
        frameIndex += 1
        selection = []; selectedNodes = []
    }

    /// A fresh identity, but the **same track** — the copy is a new layer and the
    /// same element of the drawing, which is exactly the distinction a track draws.
    /// The same layer with a new identity, all the way down.
    ///
    /// Descending matters more here than anywhere else: this only skipped a
    /// group's children before, so copying a group produced children that still
    /// carried the originals' ids. Two layers in one frame answering to the same
    /// id is not a cosmetic problem — every lookup in here finds whichever comes
    /// first, so a move, a colour or a delete aimed at one hits the other.
    private func reidentified(_ layer: Layer) -> Layer {
        var l = layer
        l.id = UUID()
        l.children = l.children.map(reidentified)
        return l
    }

    func deleteFrame() { deleteFrame(at: frameIndex) }

    /// Deletes a named frame rather than the one you are on.
    ///
    /// The frames list can right-click a frame it is not showing, and going to
    /// that frame first would mean a mis-aimed click deleted the frame you were
    /// drawing on. Nothing here moves the playhead unless it has to: deleting a
    /// frame *above* the current one keeps you on the same drawing, and deleting
    /// the one you are on leaves you at the same position in a shorter list —
    /// which is the next frame, or the last one if there is no next.
    func deleteFrame(at index: Int) {
        guard doc.frames.count > 1, doc.frames.indices.contains(index) else { return }
        commit()
        thumbCache[doc.frames[index].id] = nil
        doc.frames.remove(at: index)
        if frameIndex > index { frameIndex -= 1 }
        frameIndex = min(frameIndex, doc.frames.count - 1)
        selection = []; selectedNodes = []
    }

    func moveFrame(by delta: Int) {
        let j = frameIndex + delta
        guard doc.frames.indices.contains(j) else { return }
        commit()
        doc.frames.swapAt(frameIndex, j)
        frameIndex = j
    }

    func go(to index: Int) {
        guard doc.frames.indices.contains(index) else { return }
        frameIndex = index
        selection = []; selectedNodes = []
        renamingLayer = nil
    }

    func step(_ delta: Int) {
        let n = doc.frames.count
        go(to: ((frameIndex + delta) % n + n) % n)
    }

    func thumbnail(_ frame: Frame, height: CGFloat = 40) -> CGImage? {
        if let cached = thumbCache[frame.id] { return cached }
        let image = Render.image(of: frame, doc: doc, height: height * 2)
        thumbCache[frame.id] = image
        return image
    }

    // MARK: Playback

    func togglePlay() { isPlaying ? stop() : play() }

    func play() {
        guard doc.frames.count > 1 else { return }
        // Only a fresh start faces forward. `retimeIfPlaying` comes through here
        // too, and a bounce that was on its way back should not about-face
        // because the rate slider moved.
        if !isPlaying { playDirection = 1 }
        isPlaying = true
        selection = []; selectedNodes = []
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / max(doc.fps, 1), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.step()
            }
        }
    }

    /// One tick. Which frame comes next is the whole of what the playback mode
    /// decides — the timer and the drawing know nothing about it.
    private func step() {
        let last = doc.frames.count - 1
        switch doc.mode {
        case .once:
            if frameIndex >= last { stop(); return }
            frameIndex += 1
        case .loop:
            frameIndex = (frameIndex + 1) % doc.frames.count
        case .bounce:
            // Two frames have no interior to come back through, so the turn
            // would land on the frame just left and the pair would read as a
            // stutter rather than a bounce. It is a loop.
            guard last >= 2 else { frameIndex = (frameIndex + 1) % doc.frames.count; return }
            if frameIndex + playDirection > last || frameIndex + playDirection < 0 {
                playDirection = -playDirection
            }
            frameIndex += playDirection
        }
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func retimeIfPlaying() { if isPlaying { play() } }

    // MARK: Onion skin

    /// Frames to ghost behind the current one, nearest first, with the tint and
    /// opacity each should be drawn at.
    var onionLayers: [(frame: Frame, tint: RGBA, alpha: Double)] {
        guard onionEnabled, !isPlaying else { return [] }
        var out: [(Frame, RGBA, Double)] = []
        let back = RGBA(0.93, 0.35, 0.30), forward = RGBA(0.25, 0.55, 0.95)
        for d in stride(from: onionBack, through: 1, by: -1) {
            let i = frameIndex - d
            guard doc.frames.indices.contains(i) else { continue }
            out.append((doc.frames[i], back, onionOpacity * pow(0.6, Double(d - 1))))
        }
        for d in 1...max(onionForward, 1) where onionForward > 0 {
            let i = frameIndex + d
            guard doc.frames.indices.contains(i) else { continue }
            out.append((doc.frames[i], forward, onionOpacity * pow(0.6, Double(d - 1))))
        }
        return out
    }
}

// MARK: - Files

extension AppModel {
    private static var flipType: UTType { UTType(filenameExtension: "flip") ?? .data }

    /// Back to the shelf. Flushes first, because leaving the editor is exactly
    /// the moment the last second of work must already be on disk — the home
    /// screen reads the folder, and it should read what you just drew.
    func goHome() {
        stop()
        flushAutosave()
        showingHome = true
    }

    func newDocument() {
        stop()
        commit()
        doc = Document()
        frameIndex = 0
        selection = []; selectedNodes = []
        thumbCache.removeAll()
        fileURL = nil
        // A new document is a new drawing: it gets its own creation stamp, and
        // no name until it earns one.
        created = Date()
        chosenName = nil
        markClean()
    }

    func presentOpen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.flipType]
        panel.allowsMultipleSelection = false
        panel.message = "Open a Flip document."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDocument(from: url)
    }

    /// The one place a document is read. Both the Open panel and a file handed
    /// over by Finder come through here — when they did not, opening a document
    /// from the Finder silently produced an empty one.
    func loadDocument(from url: URL) {
        do {
            let loaded = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            stop()
            doc = loaded
            frameIndex = 0
            selection = []; selectedNodes = []
            undoStack.removeAll(); redoStack.removeAll()
            thumbCache.removeAll(); refCache = nil
            fileURL = url
            chosenName = nil
            // What was just loaded *is* the file, so the write that loading looks
            // like must not be sent straight back to disk. Autosave picks up from
            // the first real change — and it writes here, to where the document
            // came from, rather than copying it into `Flip Creations`.
            markClean()
            // The document may carry a different artboard size than the one on
            // screen, so the old zoom and pan no longer mean anything.
            NotificationCenter.default.post(name: .flipFitToWindow, object: nil)
            note("Opened \(url.lastPathComponent)")
        } catch {
            errorMessage = "That file could not be read as a Flip document.\n\(error.localizedDescription)"
        }
    }

    // MARK: Autosave

    /// `~/Documents/Flip Creations`, where a document with no home of its own
    /// goes. Made on demand rather than at launch, so an app that is opened and
    /// closed without drawing anything leaves nothing behind.
    ///
    /// This build was re-Flip until it replaced the original Flip, and kept its
    /// own folder while the two ran side by side. They now share one.
    /// `nonisolated`: it computes a path and touches nothing on the model, and
    /// the library needs it from a plain struct.
    nonisolated static var creationsFolder: URL {
        if let path = UserDefaults.standard.string(forKey: creationsFolderKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultCreationsFolder
    }

    nonisolated static var defaultCreationsFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documents.appendingPathComponent("Flip Creations", isDirectory: true)
    }

    nonisolated static let creationsFolderKey = "creationsFolder"

    /// Where new drawings are filed and where the shelf reads from.
    ///
    /// Stored as a plain path rather than a security-scoped bookmark: this is
    /// not a sandboxed app, so a path is the whole of what has to be remembered
    /// — and a path is legible in `defaults` when something goes wrong, which a
    /// bookmark is not. Existing drawings stay where they are; this says where
    /// the *next* one goes.
    nonisolated static func setCreationsFolder(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.standardizedFileURL.path, forKey: creationsFolderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: creationsFolderKey)
        }
    }

    /// Asks for one, and reports whether the answer changed anything. Returns on
    /// the main actor because everything that reacts to it lives there.
    @discardableResult
    func chooseCreationsFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Where should Flip keep your animations?"
        panel.directoryURL = Self.creationsFolder.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        Self.setCreationsFolder(url)
        // The folder has to exist before anything is filed into it, and the one
        // that was picked may have been created by the panel a moment ago.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return true
    }

    /// Changes are coalesced into at most one write every `autosaveDelay`.
    ///
    /// Not restarted on each change: the timer is armed by the *first* change of
    /// a burst and left to run, so a drag that lasts a minute is written a dozen
    /// times rather than not at all — where a timer pushed back by every change
    /// would wait for the drag to stop. And a single change still lands about a
    /// second later.
    private var autosaveDelay: TimeInterval { 1.2 }

    private func scheduleAutosave() {
        guard autosaveTimer == nil else { return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: autosaveDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.autosaveTimer = nil
                self?.autosave()
            }
        }
    }

    /// Writes now if there is anything to write. Called on the timer, and on the
    /// way out — quitting inside the coalescing window must not lose the last
    /// second of work.
    func flushAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        autosave()
    }

    private func autosave() {
        guard unsaved else { return }
        guard let url = fileURL ?? mintedURL() else { return }
        do {
            try write(to: url)
            // Only now is it the document's own file — if the write failed it
            // would be a file the app believes in and the disk does not.
            fileURL = url
            unsaved = false
        } catch {
            // Not an alert: this runs every second or so, and a modal that
            // reappears as fast as it is dismissed is worse than the failure.
            // The title bar carries it instead, and ⌘S still reports properly.
            note("Could not autosave")
        }
    }

    /// A fresh file in `Flip Creations`, named for the user's choice or for when
    /// the document was started, and numbered if something is already there.
    private func mintedURL() -> URL? {
        let dir = Self.creationsFolder
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            note("Could not make the Flip Creations folder")
            return nil
        }
        let base = chosenName ?? defaultName
        var url = dir.appendingPathComponent(base).appendingPathExtension("flip")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension("flip")
            n += 1
        }
        return url
    }

    private func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        // Atomic, because autosave writes over the only copy of the drawing: a
        // crash half way through a plain write leaves a truncated file where the
        // work used to be.
        try encoder.encode(doc).write(to: url, options: .atomic)
    }

    /// Whatever the app has just loaded or created *is* the saved state, so the
    /// change that opening it looks like should not write anything back.
    private func markClean() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        unsaved = false
    }

    // MARK: Renaming the document

    /// Renames the document, and the file with it.
    ///
    /// A rename before the first autosave has nothing to move, so the name is
    /// kept and the first write uses it — which is why the title bar can be typed
    /// into the moment a document is made.
    func renameDocument(_ raw: String) {
        // `/` is the path separator and `:` is what the Finder shows in its
        // place; neither can be in a filename, and a name typed with one in it
        // is a name, not a mistake to refuse.
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty, name != documentName else { return }

        guard let old = fileURL else {
            chosenName = name
            objectWillChange.send()
            return
        }
        var target = old.deletingLastPathComponent()
            .appendingPathComponent(name).appendingPathExtension("flip")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path), target != old {
            target = old.deletingLastPathComponent()
                .appendingPathComponent("\(name) \(n)").appendingPathExtension("flip")
            n += 1
        }
        guard target != old else { return }
        do {
            try FileManager.default.moveItem(at: old, to: target)
            chosenName = name
            fileURL = target
            objectWillChange.send()
            note("Renamed to \(target.lastPathComponent)")
        } catch {
            errorMessage = "Could not rename the document.\n\(error.localizedDescription)"
        }
    }

    func save(as saveAs: Bool = false) {
        var target = fileURL
        if target == nil || saveAs {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [Self.flipType]
            panel.nameFieldStringValue = "\(documentName).flip"
            panel.directoryURL = Self.creationsFolder
            guard panel.runModal() == .OK, let url = panel.url else { return }
            target = url
        }
        guard let target else { return }
        do {
            try write(to: target)
            fileURL = target
            chosenName = target.deletingPathExtension().lastPathComponent
            markClean()
            note("Saved \(target.lastPathComponent)")
        } catch {
            errorMessage = "Could not save.\n\(error.localizedDescription)"
        }
    }

    func exportSVG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "\(documentName).svg"
        panel.message = doc.frames.count > 1
            ? "One animated SVG — \(doc.frames.count) frames at \(Int(doc.fps)) fps."
            : "A single still frame."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SVGExport(doc: doc).svg().write(to: url, atomically: true, encoding: .utf8)
            note("Exported \(url.lastPathComponent)")
        } catch {
            errorMessage = "Could not write the SVG.\n\(error.localizedDescription)"
        }
    }

    var gifPlan: GIFExport {
        GIFExport(doc: doc, transparent: exportTransparent,
                  scale: CGFloat(gifScale), alphaThreshold: gifThreshold)
    }

    func exportGIF() {
        let plan = gifPlan
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "\(documentName).gif"
        let size = plan.pixelSize
        panel.message = "\(doc.frames.count) frame\(doc.frames.count == 1 ? "" : "s") at "
            + "\(Int(size.width))×\(Int(size.height))"
            + (exportTransparent ? ", transparent background." : ".")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try plan.write(to: url)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            let size = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            note("Exported \(url.lastPathComponent)" + (size.map { " · \($0)" } ?? ""))
        } catch {
            errorMessage = "Could not write the GIF.\n\(error.localizedDescription)"
        }
    }

    func exportPNG() {
        let plan = PNGExport(doc: doc, frame: frame, transparent: exportTransparent)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        // The frame number is in the name because pulling several stills out of
        // one document is the ordinary case, and without it the second one
        // arrives asking to replace the first.
        panel.nameFieldStringValue = "\(documentName) frame \(frameIndex + 1).png"
        let size = plan.pixelSize
        panel.message = "Frame \(frameIndex + 1) of \(doc.frames.count) at "
            + "\(Int(size.width))×\(Int(size.height))"
            + (exportTransparent ? ", transparent background." : ".")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try plan.write(to: url)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            let size = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            note("Exported \(url.lastPathComponent)" + (size.map { " · \($0)" } ?? ""))
        } catch {
            errorMessage = "Could not write the PNG.\n\(error.localizedDescription)"
        }
    }

    func note(_ text: String) {
        statusNote = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if statusNote == text { statusNote = nil }
        }
    }
}


// MARK: - Reference image

extension AppModel {
    /// The decoded reference, or nil if there is none or it could not be read.
    var referenceImage: CGImage? {
        guard let ref = doc.reference else { return nil }
        if let cached = refCache, cached.0 == ref.data { return cached.1 }
        guard let source = CGImageSourceCreateWithData(ref.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        refCache = (ref.data, image)
        return image
    }

    var hasReference: Bool { doc.reference != nil }

    func presentReferencePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a reference to draw over. It sits under every frame and is never exported."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadReference(from: url)
    }

    func loadReference(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                errorMessage = "That file could not be read as an image."
                return
            }
            commit()
            doc.reference = Reference(data: data,
                                      pixelSize: CGSize(width: image.width, height: image.height),
                                      name: url.lastPathComponent)
            refCache = (data, image)
            note("Reference: \(url.lastPathComponent)")
        } catch {
            errorMessage = "Could not read that file.\n\(error.localizedDescription)"
        }
    }

    func clearReference() {
        guard doc.reference != nil else { return }
        commit()
        doc.reference = nil
        refCache = nil
    }

    /// Back to aspect-fit, centred on the artboard.
    func recentreReference() {
        guard doc.reference != nil else { return }
        commit()
        doc.reference?.scale = 1
        doc.reference?.offset = .zero
    }

    /// Nudges the reference by a canvas drag. Undo is pushed once, when the mode
    /// is entered — see `beginReposition` — so the whole placement is one step.
    func moveReference(by delta: CGPoint) {
        guard repositioning, var ref = doc.reference else { return }
        ref.offset = ref.offset + delta
        doc.reference = ref
    }
}


// MARK: - Copy and paste

extension AppModel {
    var canCopy: Bool { !selectedLayersHere.isEmpty }
    var canPaste: Bool { !clipboard.isEmpty }

    /// Copies from the frame on screen only. A paste lands in one frame, so a
    /// selection spanning several has no sensible reading here.
    func copySelection() {
        if forwardToTextEditor(#selector(NSText.copy(_:))) { return }
        guard !selectedLayersHere.isEmpty else { return }
        // Stamping the source is what lets the paste land on another frame as the
        // *same* layer rather than an unrelated one that happens to look alike.
        let taken = trackedSelectionHere()
        clipboard = taken
        note("Copied \(taken.count) layer\(taken.count == 1 ? "" : "s")")
    }

    /// Ensures this frame's selected layers have tracks, and hands them back.
    /// Deliberately no `commit()`: a track is invisible metadata, and copying is
    /// not an edit anyone expects to be able to undo.
    private func trackedSelectionHere() -> [Layer] {
        var layers = frame.layers
        for id in selection { LayerTree.mutate(id, in: &layers) { $0 = self.tracked($0) } }
        frame.layers = layers
        return layers.flatMap { $0.flattened() }.filter { selection.contains($0.id) }
    }

    func cutSelection() {
        if forwardToTextEditor(#selector(NSText.cut(_:))) { return }
        let taken = selectedLayersHere
        guard !taken.isEmpty else { return }
        clipboard = taken
        deleteSelection()
        note("Cut \(taken.count) layer\(taken.count == 1 ? "" : "s")")
    }

    /// Pastes at the coordinates the shapes were copied from.
    ///
    /// Geometry is stored in absolute document points, so *not* translating is
    /// precisely what puts a shape in the same spot on another frame. There is
    /// deliberately no paste offset: when consecutive frames are drawings of the
    /// same scene, "where it already was" is the only useful answer.
    func paste() {
        if forwardToTextEditor(#selector(NSText.paste(_:))) { return }
        guard !clipboard.isEmpty else { return }
        commit()
        // Keeps the track, so pasting onto another frame gives you the same layer
        // there — unless this frame already has it, in which case a second copy is
        // a new layer rather than another instance of the same one.
        let fresh = untangled(clipboard, landingOn: frame).map(reidentified)
        frame.layers.append(contentsOf: fresh)
        selection = Set(fresh.map { $0.id })
        selectedNodes = []
        touched()
        note("Pasted in place on frame \(frameIndex + 1)")
    }

    /// The same shapes, at the same position, on every frame. Per-frame layer
    /// stacks mean anything that should sit still has to exist once per frame, and
    /// doing that by hand is the tedium this removes.
    func pasteIntoAllFrames() {
        guard !clipboard.isEmpty else { return }
        commit()
        // One track per pasted layer, shared by every frame's copy and fresh rather
        // than inherited: this is the clearest case there is of one element that
        // exists once per frame, and ⌥-clicking it afterwards selects all of it.
        let family = clipboard.map(retracked)
        var ids: Set<UUID> = []
        for i in doc.frames.indices {
            let fresh = family.map(reidentified)
            doc.frames[i].layers.append(contentsOf: fresh)
            ids.formUnion(fresh.map { $0.id })
            thumbCache[doc.frames[i].id] = nil
        }
        selection = ids
        selectedNodes = []
        note("Pasted into \(doc.frames.count) frames")
    }

    /// Menu shortcuts are matched before the responder chain, so ⌘C while renaming
    /// a layer would copy shapes instead of text. Hand those back to the field.
    private func forwardToTextEditor(_ selector: Selector) -> Bool {
        guard let responder = NSApplication.shared.keyWindow?.firstResponder,
              responder is NSTextView else { return false }
        return NSApplication.shared.sendAction(selector, to: responder, from: nil)
    }
}
