import SwiftUI

/// Draws an `Icon` as a stroked vector path.
///
/// The artwork is stroke-based on a 24×24 grid, so the stroke has to scale with
/// the box or a 36pt tool would be drawn with the same hairline as a 16pt one.
/// `strokedPath` converts the stroke to an outline, which means the result is a
/// plain fillable `Shape` — and a `Shape` used as a view fills itself with the
/// current `foregroundStyle`, so these tint exactly the way SF Symbols did.
struct IconShape: Shape {
    let icon: Icon
    /// On the 24-unit grid the artwork is drawn on, matching the source SVGs.
    var lineWidth: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / IconPath.grid
        let centred = CGAffineTransform(
            translationX: (rect.width - IconPath.grid * scale) / 2,
            y: (rect.height - IconPath.grid * scale) / 2
        ).scaledBy(x: scale, y: scale)

        return IconPath.path(for: icon)
            .applying(centred)
            .strokedPath(StrokeStyle(lineWidth: lineWidth * scale,
                                     lineCap: .round,
                                     lineJoin: .round))
    }
}

/// An icon at a given box size. The size is the 24-unit grid's edge, not a font
/// size — an SF Symbol at `size:` 12 drew a glyph rather smaller than its box,
/// so call sites that used to pass a font size pass a slightly smaller number
/// here to land in the same place.
struct IconView: View {
    let icon: Icon
    var size: CGFloat
    var lineWidth: CGFloat = 1.5

    var body: some View {
        IconShape(icon: icon, lineWidth: lineWidth)
            .frame(width: size, height: size)
    }
}

// MARK: - Path data

enum IconPath {
    static let grid: CGFloat = 24

    /// Built once per icon and kept. Parsing is cheap, but the panels rebuild
    /// on every selection change and there is no reason to do it again.
    private static var cache: [Icon: Path] = [:]

    /// One SVG path string, on whatever grid it was drawn. Shared with the
    /// cursor artwork, which uses a 32-unit grid and paints each subpath itself.
    static func parse(_ d: String) -> Path {
        var path = Path()
        append(d, to: &path)
        return path
    }

    static func path(for icon: Icon) -> Path {
        if let hit = cache[icon] { return hit }
        var path = Path()
        for d in icon.data { append(d, to: &path) }
        cache[icon] = path
        return path
    }

    /// A parser for the subset the artwork actually uses: `M L H V C Z`, in
    /// either case, with implicit repeats. `tools/svg-to-swift.py` refuses to
    /// emit anything else, so an unsupported command cannot reach this.
    private static func append(_ d: String, to path: inout Path) {
        var numbers: [CGFloat] = []
        var command: Character = " "
        var start = CGPoint.zero
        var pen = CGPoint.zero

        func flush() {
            var i = 0
            func next() -> CGFloat { defer { i += 1 }; return i < numbers.count ? numbers[i] : 0 }
            let relative = command.isLowercase

            switch Character(command.uppercased()) {
            case "M":
                // A second pair after an M is an implicit lineTo, per the spec.
                var first = true
                while i < numbers.count {
                    let p = point(next(), next(), relative: relative, from: pen)
                    if first { path.move(to: p); start = p; first = false }
                    else { path.addLine(to: p) }
                    pen = p
                }
            case "L":
                while i < numbers.count {
                    let p = point(next(), next(), relative: relative, from: pen)
                    path.addLine(to: p); pen = p
                }
            case "H":
                while i < numbers.count {
                    let x = next()
                    pen = CGPoint(x: relative ? pen.x + x : x, y: pen.y)
                    path.addLine(to: pen)
                }
            case "V":
                while i < numbers.count {
                    let y = next()
                    pen = CGPoint(x: pen.x, y: relative ? pen.y + y : y)
                    path.addLine(to: pen)
                }
            case "C":
                while i + 5 < numbers.count {
                    let c1 = point(next(), next(), relative: relative, from: pen)
                    let c2 = point(next(), next(), relative: relative, from: pen)
                    let to = point(next(), next(), relative: relative, from: pen)
                    path.addCurve(to: to, control1: c1, control2: c2)
                    pen = to
                }
            case "Z":
                path.closeSubpath()
                pen = start
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var number = ""
        func takeNumber() {
            if !number.isEmpty, let v = Double(number) { numbers.append(CGFloat(v)) }
            number = ""
        }

        for ch in d {
            if ch.isLetter {
                takeNumber()
                if command != " " { flush() }
                command = ch
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
                takeNumber()
            } else if ch == "-" && !number.isEmpty && !number.hasSuffix("e") && !number.hasSuffix("E") {
                // A minus with digits already banked starts the next number.
                takeNumber()
                number = "-"
            } else if ch == "." && number.contains(".") {
                // "1.5.5" is two numbers — legal SVG shorthand.
                takeNumber()
                number = "."
            } else {
                number.append(ch)
            }
        }
        takeNumber()
        if command != " " { flush() }
    }

    private static func point(_ x: CGFloat, _ y: CGFloat,
                              relative: Bool, from pen: CGPoint) -> CGPoint {
        relative ? CGPoint(x: pen.x + x, y: pen.y + y) : CGPoint(x: x, y: y)
    }
}
