import SwiftUI
import CoreGraphics

// MARK: - Colour

/// Stored rather than SwiftUI's `Color` so a document round-trips through JSON
/// and an exact hex reaches the SVG.
struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent),
                  Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var opaque: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func cg(alpha: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a * alpha) }

    var hex: String { "#" + hex6 }

    /// Six digits, no `#`. The field this feeds is editable, and a punctuation
    /// mark the user has to keep alive while retyping a colour is one they will
    /// delete by accident.
    var hex6: String {
        String(format: "%02X%02X%02X",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// `RGB` or `RRGGBB`, with or without a leading `#`. Alpha is carried over
    /// from the receiver rather than parsed, since the field only edits colour.
    init?(hex: String, alpha: Double = 1) {
        var digits = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let v = Int(digits, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255,
                  Double((v >> 8) & 0xFF) / 255,
                  Double(v & 0xFF) / 255,
                  alpha)
    }

    static let ink   = RGBA(0.11, 0.11, 0.12)
    static let paper = RGBA(0.98, 0.97, 0.95)
    static let swatches: [RGBA] = [
        RGBA(0.11, 0.11, 0.12), RGBA(0.98, 0.97, 0.95), RGBA(0.90, 0.29, 0.24),
        RGBA(0.96, 0.65, 0.14), RGBA(0.95, 0.85, 0.35), RGBA(0.35, 0.72, 0.45),
        RGBA(0.20, 0.55, 0.85), RGBA(0.45, 0.35, 0.75), RGBA(0.88, 0.48, 0.65),
    ]
}

// MARK: - Layers

enum BoolOp: String, Codable, CaseIterable, Hashable {
    case unite, subtract, intersect, exclude

    var label: String {
        switch self {
        case .unite:     return "Unite"
        case .subtract:  return "Subtract"
        case .intersect: return "Intersect"
        case .exclude:   return "Exclude"
        }
    }

    var icon: Icon {
        switch self {
        case .unite:     return .boolUnite
        case .subtract:  return .boolSubtract
        case .intersect: return .boolIntersect
        case .exclude:   return .boolExclude
        }
    }
}

/// A layer is a drawn shape, a **live** boolean of other layers, or a plain
/// group of them.
///
/// The boolean keeps its children intact — nothing is flattened — so an
/// operation can be released again and either side stays editable. A group keeps
/// them intact for a different reason: it does nothing to them at all. It is a
/// name and a place in the stack, so that thirty shapes can be read as four
/// things; the children keep their own paint and are drawn in their own order,
/// where a boolean's children are drawn in the boolean's colour.
///
/// Adding a case is safe for older `.flip` files, which only ever hold the two
/// that were here before.
/// How a layer composites onto what is already painted under it.
///
/// The sixteen that Core Graphics and CSS both name, and they name them the
/// same way — which is the whole reason the list is this list. The canvas draws
/// through `CGBlendMode` and the SVG export writes `mix-blend-mode`, and a mode
/// that only one of them had would be a mode the export could not keep.
enum Blend: String, Codable, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, hardLight, softLight
    case difference, exclusion
    case hue, saturation, color, luminosity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal:     return "Normal"
        case .multiply:   return "Multiply"
        case .screen:     return "Screen"
        case .overlay:    return "Overlay"
        case .darken:     return "Darken"
        case .lighten:    return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn:  return "Color Burn"
        case .hardLight:  return "Hard Light"
        case .softLight:  return "Soft Light"
        case .difference: return "Difference"
        case .exclusion:  return "Exclusion"
        case .hue:        return "Hue"
        case .saturation: return "Saturation"
        case .color:      return "Color"
        case .luminosity: return "Luminosity"
        }
    }

    var cg: CGBlendMode {
        switch self {
        case .normal:     return .normal
        case .multiply:   return .multiply
        case .screen:     return .screen
        case .overlay:    return .overlay
        case .darken:     return .darken
        case .lighten:    return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn:  return .colorBurn
        case .hardLight:  return .hardLight
        case .softLight:  return .softLight
        case .difference: return .difference
        case .exclusion:  return .exclusion
        case .hue:        return .hue
        case .saturation: return .saturation
        case .color:      return .color
        case .luminosity: return .luminosity
        }
    }

    /// The CSS keyword, which is the rawValue with the camel humps knocked into
    /// hyphens — spelled out rather than derived, so a mode whose two names ever
    /// disagree has somewhere to say so.
    var css: String {
        switch self {
        case .colorDodge: return "color-dodge"
        case .colorBurn:  return "color-burn"
        case .hardLight:  return "hard-light"
        case .softLight:  return "soft-light"
        default:          return rawValue
        }
    }

    /// The four groups the modes fall into, for a menu that would otherwise be
    /// sixteen unbroken lines: darkening, lightening, contrast, and the ones
    /// that take a component of the colour rather than mixing the whole thing.
    static let groups: [[Blend]] = [
        [.normal],
        [.multiply, .darken, .colorBurn],
        [.screen, .lighten, .colorDodge],
        [.overlay, .hardLight, .softLight],
        [.difference, .exclusion],
        [.hue, .saturation, .color, .luminosity],
    ]
}

enum LayerContent: Codable, Equatable {
    case shape(Shape2D)
    case boolean(BoolOp, [Layer])
    case group([Layer])
}

struct Layer: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Ties this layer to its counterparts in other frames — the same element of
    /// the drawing, once per frame. Stamped when a frame is duplicated or a shape
    /// is pasted onto another frame, which are the only ways one layer comes to
    /// exist in several, so it is exact and survives both renaming and reordering.
    ///
    /// `nil` in documents saved before this existed; those fall back to matching on
    /// name and position. Optional for exactly that reason — a non-optional field
    /// added to a `Codable` struct makes every older `.flip` file fail to decode.
    var track: UUID?
    var name: String
    var content: LayerContent
    /// `nil` means no paint at all, which is how an open construction line is
    /// kept visible without pretending to enclose an area.
    var fill: RGBA?
    var stroke: RGBA?
    var strokeWidth: CGFloat = 2
    var visible: Bool = true
    /// How much of the layer comes through, 0…1.
    ///
    /// A property of the *layer*, not of its colours: the alpha inside `fill` and
    /// `stroke` makes one of them translucent, where this makes the whole layer
    /// translucent as a unit — which is why it is composited rather than
    /// multiplied into the paint, or a half-opacity shape would show its own
    /// stroke through its own fill.
    ///
    /// Optional and left out when fully opaque, for the same two reasons
    /// `orientation` is: a non-optional field added to a `Codable` struct makes
    /// every older `.flip` file fail to decode, and the default is not worth
    /// writing into every layer of every saved document.
    var opacity: Double?
    /// How far this layer's own axes are turned from the document's.
    ///
    /// Geometry here stays absolute and fully baked — a turn rewrites the anchors
    /// exactly as a move does — so this is **not** a transform waiting to be
    /// applied, and nothing in rendering, hit testing or either export reads it.
    /// It is a record of which way up the shape is, and its only job is to let the
    /// selection box, and a resize made through that box, work along the shape's
    /// own axes instead of the artboard's.
    ///
    /// Optional, and left `nil` rather than `0` for a layer square to the
    /// document: a non-optional field added to a `Codable` struct makes every
    /// older `.flip` file fail to decode, and the zero case is not worth writing
    /// into every layer of every saved document.
    var orientation: CGFloat?

    /// How the layer composites onto what is under it.
    ///
    /// Optional and left out when normal, for the same two reasons `opacity` is:
    /// a non-optional field added to a `Codable` struct makes every older
    /// `.flip` file fail to decode, and the default is not worth writing into
    /// every layer of every saved document.
    var blend: Blend?

    /// Which of the frame's armatures drives this layer, by index into
    /// `Frame.armatures`.
    ///
    /// Ownership is explicit and stored, never inferred: proximity cannot tell a
    /// sleeve from the arm inside it from the torso behind it, and reading it off
    /// the stacking order would silently re-bind a rig every time layers were
    /// reordered. A layer no rig owns cannot be posed at all, however close a
    /// bone happens to be.
    ///
    /// Optional for the usual reason — a non-optional field added to a `Codable`
    /// struct makes every older `.flip` file fail to decode.
    var rig: Int?

    /// How much this layer's lines wander off the path they were drawn on.
    ///
    /// Carries down to what is inside a group, the way a rig does, so a whole
    /// character can be given one hand rather than one stroke at a time.
    ///
    /// Optional for the usual reason — a non-optional field added to a `Codable`
    /// struct makes every older `.flip` file fail to decode — and absent means
    /// a line that goes exactly where it was drawn.
    var wiggle: Wiggle?

    /// `blend` with its absent case spelled out.
    var blending: Blend {
        get { blend ?? .normal }
        set { blend = newValue == .normal ? nil : newValue }
    }

    /// `orientation` with its absent case spelled out, wrapped to a half turn
    /// either way so repeated turns cannot wind the number up without limit.
    var axisAngle: CGFloat {
        get { orientation ?? 0 }
        set {
            var a = newValue.truncatingRemainder(dividingBy: 2 * .pi)
            if a > .pi { a -= 2 * .pi }
            if a < -.pi { a += 2 * .pi }
            orientation = abs(a) < 1e-9 ? nil : a
        }
    }

    /// `opacity` with its absent case spelled out, and clamped — a document
    /// edited by hand should not be able to make a layer more than opaque.
    var alpha: Double {
        get { min(max(opacity ?? 1, 0), 1) }
        set { opacity = newValue >= 0.999 ? nil : min(max(newValue, 0), 1) }
    }

    var isBoolean: Bool { if case .boolean = content { return true }; return false }
    var isGroup: Bool { if case .group = content { return true }; return false }
    /// Whether the row can be opened to show what is inside it.
    var hasChildren: Bool { isBoolean || isGroup }

    var shape: Shape2D? {
        get { if case .shape(let s) = content { return s }; return nil }
        set { if let newValue { content = .shape(newValue) } }
    }

    var children: [Layer] {
        get {
            switch content {
            case .shape:                return []
            case .boolean(_, let kids): return kids
            case .group(let kids):      return kids
            }
        }
        set {
            switch content {
            case .shape:                break
            case .boolean(let op, _):   content = .boolean(op, newValue)
            case .group:                content = .group(newValue)
            }
        }
    }

    var op: BoolOp? { if case .boolean(let op, _) = content { return op }; return nil }

    /// Depth-first walk including self, used for selection lookups.
    func flattened() -> [Layer] { [self] + children.flatMap { $0.flattened() } }
}

// MARK: - Frames

struct Frame: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Bottom of the stack first, matching CoreGraphics paint order. The layers
    /// panel shows this reversed so the top layer sits at the top of the list.
    var layers: [Layer] = []

    /// Posing armatures for this frame.
    ///
    /// Per-frame rather than per-document, because that is what the tool is for:
    /// each frame is posed on its own, and duplicating a frame carries the rig
    /// and its pose forward so the next drawing starts from the last one.
    ///
    /// Optional and left out entirely when there is no rig: a non-optional field
    /// added to a `Codable` struct makes every older `.flip` file fail to decode.
    var rigs: [Skeleton]?

    /// `rigs` with its absent case spelled out. Append-only in practice, so the
    /// indices layers hold in `Layer.rig` stay valid.
    var armatures: [Skeleton] {
        get { rigs ?? [] }
        set { rigs = newValue.isEmpty ? nil : newValue }
    }
}

// MARK: - Reference

/// A tracing reference that sits under every frame.
///
/// Document-level rather than per-frame, deliberately: with per-frame layer
/// stacks nothing else in this app persists between frames, so this is the one
/// thing that can stay put while you draw over it. It is a guide, not artwork —
/// it is never exported and never appears in a frame thumbnail.
///
/// The original file's bytes are kept verbatim, so the document stays
/// self-contained and does not break when the image is moved or renamed.
struct Reference: Codable, Equatable {
    var data: Data
    var pixelSize: CGSize
    var name: String
    var opacity: Double = 0.45
    var visible: Bool = true
    var scale: CGFloat = 1
    var offset: CGPoint = .zero

    /// Aspect-fit inside the artboard, which is where a fresh reference lands.
    func baseRect(in size: CGSize) -> CGRect {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let s = min(size.width / pixelSize.width, size.height / pixelSize.height)
        let w = pixelSize.width * s, h = pixelSize.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    func rect(in size: CGSize) -> CGRect {
        let base = baseRect(in: size)
        let w = base.width * scale, h = base.height * scale
        return CGRect(x: base.midX - w / 2 + offset.x,
                      y: base.midY - h / 2 + offset.y,
                      width: w, height: h)
    }
}

/// What happens when the last frame is reached.
///
/// `once` and `loop` are the two states the old `loops` flag had; `bounce` is
/// the third, and it is a property of the *cycle* rather than of the frames —
/// nothing is duplicated in the document, it is only played out and back.
enum PlaybackMode: String, Codable, CaseIterable, Identifiable {
    case once, loop, bounce

    var id: String { rawValue }

    var label: String {
        switch self {
        case .once:   return "Once"
        case .loop:   return "Loop"
        case .bounce: return "Bounce"
        }
    }
}

struct Document: Codable, Equatable {
    var size: CGSize = CGSize(width: 1080, height: 1080)
    var background: RGBA = .paper
    var fps: Double = 12
    /// What `loops` became. Optional for the same reason `swatches` is — the
    /// synthesised decoder does not fall back to a property's default, so a
    /// plain `PlaybackMode` here would throw `keyNotFound` on every file saved
    /// before there was a choice. Nil is such a file, and `loops` answers for it.
    var playback: PlaybackMode?
    /// The old flag, still written on every save so a file made here plays right
    /// in a build that predates `playback`. A bounce does repeat, so this is
    /// true for anything but `once`. Read through `mode`, never directly.
    var loops: Bool = true
    var reference: Reference?
    /// Colours this file has added to the palette, after the nine built in.
    ///
    /// Optional rather than a defaulted `[RGBA]`, and that is not a style
    /// choice: the synthesised decoder does not use a property's default value,
    /// so a non-optional array here would throw `keyNotFound` on every document
    /// saved before this existed. `reference` is optional for a reason of its
    /// own and happens to have protected the format the same way.
    var swatches: [RGBA]?
    var frames: [Frame] = [Frame()]

    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    /// The one way in and out. Reading falls back to the legacy flag; writing
    /// sets both, so the two can never disagree.
    var mode: PlaybackMode {
        get { playback ?? (loops ? .loop : .once) }
        set { playback = newValue; loops = newValue != .once }
    }

    /// The frames as played, by index — what the app steps through and what an
    /// export writes out.
    ///
    /// A bounce turns *on* its end frames rather than repeating them: 0,1,2,1
    /// and round again, not 0,1,2,2,1,0. Held twice, each end would stall for
    /// two frames' worth of time and the turn would read as a hitch. Under three
    /// frames there is no interior to come back through, so a bounce is a loop.
    var playOrder: [Int] {
        let n = frames.count
        guard mode == .bounce, n > 2 else { return Array(0..<n) }
        return Array(0..<n) + Array((1..<(n - 1)).reversed())
    }

    /// One cycle, which for a bounce is the whole way out and back.
    var duration: Double { Double(playOrder.count) / max(fps, 1) }
}

// MARK: - Moving and transforming

extension Layer {
    func translated(by d: CGPoint) -> Layer {
        var copy = self
        switch content {
        case .shape(var s):
            s.translate(by: d)
            copy.content = .shape(s)
        case .boolean(let op, let kids):
            copy.content = .boolean(op, kids.map { $0.translated(by: d) })
        case .group(let kids):
            copy.content = .group(kids.map { $0.translated(by: d) })
        }
        return copy
    }

    /// Transformed. The one primitive; `scaled` and `rotated` are the two ways
    /// the app asks for it.
    ///
    /// **Geometry only.** `strokeWidth` is deliberately left alone — a stroke is a
    /// property of the layer rather than a dimension of the shape, and a line that
    /// thinned out because the drawing was made smaller is a line you would have
    /// to set back by hand every time. `orientation` is left alone too: what a
    /// transform does to the shape's idea of upright is the caller's business, and
    /// only a turn changes it.
    func transformed(by m: CGAffineTransform) -> Layer {
        var copy = self
        switch content {
        case .shape(var s):
            s.transform(by: m)
            copy.content = .shape(s)
        case .boolean(let op, let kids):
            copy.content = .boolean(op, kids.map { $0.transformed(by: m) })
        case .group(let kids):
            copy.content = .group(kids.map { $0.transformed(by: m) })
        }
        return copy
    }

    func scaled(about c: CGPoint, x sx: CGFloat, y sy: CGFloat) -> Layer {
        transformed(by: .about(c, CGAffineTransform(scaleX: sx, y: sy)))
    }

    func rotated(about c: CGPoint, by radians: CGFloat) -> Layer {
        transformed(by: .about(c, .rotation(radians))).reoriented(by: radians)
    }

    /// Adds `delta` to the recorded orientation, and to the children's — a boolean
    /// turns by turning the shapes inside it, so they have been turned too, and
    /// releasing one should hand back shapes that know which way up they are.
    func reoriented(by delta: CGFloat) -> Layer {
        guard delta != 0 else { return self }
        var copy = self
        copy.axisAngle = axisAngle + delta
        switch content {
        case .shape: break
        case .boolean(let op, let kids):
            copy.content = .boolean(op, kids.map { $0.reoriented(by: delta) })
        case .group(let kids):
            copy.content = .group(kids.map { $0.reoriented(by: delta) })
        }
        return copy
    }
}