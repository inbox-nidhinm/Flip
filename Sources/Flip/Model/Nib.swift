import CoreGraphics
import Foundation

/// What lays the ink down, when a plain even stroke is not what you want.
///
/// An addition to the stroke rather than a replacement: the colour, the width
/// and the path are all still the layer's own, and the fill is untouched. The
/// nib only changes how the *outline* is put on the paper.
enum Nib: String, Codable, CaseIterable, Identifiable {
    /// An even stroke, the way it has always been drawn.
    case pen
    case light
    case medium
    case heavy
    case soft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen:    return "Pen"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .heavy:  return "Heavy"
        case .soft:   return "Soft"
        }
    }

    var isPencil: Bool { self != .pen }

    /// The three numbers that separate one pencil from another.
    struct Pencil {
        let press: CGFloat
        let grain: CGFloat
        let bite: CGFloat
    }

    /// The three numbers that separate one pencil from another.
    ///
    /// `press` caps how much graphite the middle of the stroke gets. Below one,
    /// the paper's tooth shows through the core and not only along the edges —
    /// which is what a light hand does, and what makes a mark read as graphite
    /// rather than as a roughened outline.
    ///
    /// `grain` is the size of the tooth, and `bite` how cleanly it cuts: high
    /// is graphite or bare paper with little in between, low leaves grains half
    /// covered, which is a softer lead.
    var pencil: Pencil? {
        switch self {
        case .pen:    return nil
        case .light:  return Pencil(press: 0.62, grain: 0.90, bite: 3.5)
        case .medium: return Pencil(press: 0.78, grain: 0.90, bite: 3.5)
        case .heavy:  return Pencil(press: 0.95, grain: 0.90, bite: 3.5)
        case .soft:   return Pencil(press: 0.62, grain: 0.55, bite: 2.4)
        }
    }
}

// MARK: - The paper

/// The tooth of the sheet: a height field the graphite sits on top of.
///
/// Held in **document** coordinates, not in the stroke's. Two lines crossing
/// have to meet the same paper or they read as two pictures laid over each
/// other, and the sheet must not slide about when the artboard is panned.
///
/// Generated rather than scanned. The noise was already here for the wander, it
/// tiles exactly, and it makes the grain size a number rather than an asset —
/// `Grain.swift`'s bitmap is no use for this: it is photographic speckle
/// authored as a tint for dark panels, at the size of a panel rather than of a
/// pencil mark.
enum Paper {
    private static func lattice(_ x: Int, _ y: Int, _ seed: UInt64) -> CGFloat {
        var n = UInt64(bitPattern: Int64(x &* 73856093 ^ y &* 19349663))
        n &+= seed &* 0x9E37_79B9_7F4A_7C15
        n ^= n >> 30; n = n &* 0xBF58_476D_1CE4_E5B9
        n ^= n >> 27; n = n &* 0x94D0_49BB_1331_11EB
        n ^= n >> 31
        return CGFloat(n >> 11) / CGFloat(UInt64(1) << 53)
    }

    private static func value(_ x: CGFloat, _ y: CGFloat, _ seed: UInt64) -> CGFloat {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let tx = x - CGFloat(xi), ty = y - CGFloat(yi)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = lattice(xi, yi, seed),     b = lattice(xi + 1, yi, seed)
        let c = lattice(xi, yi + 1, seed), d = lattice(xi + 1, yi + 1, seed)
        return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy
    }

    /// The height at a point, 0…1. Three scales, the finest carrying its share —
    /// one scale alone reads as cloud rather than as grain.
    ///
    /// The odd multiplier between scales is deliberate: at a round doubling the
    /// lattices line up and leave a visible weave.
    static func tooth(_ x: CGFloat, _ y: CGFloat, grain: CGFloat, seed: UInt64) -> CGFloat {
        var v: CGFloat = 0, amp: CGFloat = 1, total: CGFloat = 0, f = grain
        for o in 0..<3 {
            v += value(x * f, y * f, seed &+ UInt64(o) &* 977) * amp
            total += amp
            amp *= 0.5
            f *= 2.7
        }
        return v / total
    }
}
