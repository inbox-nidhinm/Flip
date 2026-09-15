#!/usr/bin/env python3
"""Turn the SVGs in Icons/Cursors/ into Sources/Flip/UI/Cursors.swift.

Cursors need their own pipeline rather than sharing the icons' one. An icon is a
single stroked outline the app tints; a cursor is several paths with their own
fills, strokes and widths — typically a fat white outline pass under a black
body, so the pointer reads on both the light artboard and the dark surround. And
a cursor has something an icon does not: a hot spot.

The hot spot comes from the filename, which the artist writes as

    Brush - 12x21.svg      ->  brush, hot spot (12, 21)

in the artwork's own 32×32 grid, measured from the top-left. That is also how
`NSCursor` reads a hot spot, so it carries over untouched.

Run from the Flip directory:  python3 tools/svg-to-cursors.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SVG = ROOT / "Icons/Cursors"
OUT = ROOT / "Sources/Flip/UI/Cursors.swift"
GRID = 32

NAME = re.compile(r"^(?P<name>.+?)\s*-\s*(?P<x>\d+)x(?P<y>\d+)$")
VIEWBOX = re.compile(r'viewBox="([^"]*)"')
MASK = re.compile(r"<mask\b.*?</mask>", re.S)
ELEMENT = re.compile(r"<(path|circle)\b(.*?)/?>", re.S)
ATTR = re.compile(r'([a-zA-Z-]+)="([^"]*)"')
ALLOWED = set("MLHVCZmlhvcz")

# A circle's four quarter-arcs as cubics. The usual constant: the handle length
# that puts a Bezier within a thousandth of a true quarter circle.
KAPPA = 0.5522847498307936


def circle_d(attrs):
    """A `<circle>` as path data.

    Figma writes the dot that marks a cursor's hot spot as a circle, and the
    Swift parser knows only M L H V C Z — so it is spelled out here rather than
    taught downstream, where every icon would pay for it.
    """
    cx = float(attrs.get("cx", 0))
    cy = float(attrs.get("cy", 0))
    r = float(attrs.get("r", 0))
    k = KAPPA * r
    n = lambda v: f"{round(v, 4):g}"
    return (
        f"M{n(cx + r)} {n(cy)}"
        f"C{n(cx + r)} {n(cy + k)} {n(cx + k)} {n(cy + r)} {n(cx)} {n(cy + r)}"
        f"C{n(cx - k)} {n(cy + r)} {n(cx - r)} {n(cy + k)} {n(cx - r)} {n(cy)}"
        f"C{n(cx - r)} {n(cy - k)} {n(cx - k)} {n(cy - r)} {n(cx)} {n(cy - r)}"
        f"C{n(cx + k)} {n(cy - r)} {n(cx + r)} {n(cy - k)} {n(cx + r)} {n(cy)}Z"
    )


def camel(text):
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", text) if p]
    head, *rest = parts
    return head[0].lower() + head[1:] + "".join(p[:1].upper() + p[1:] for p in rest)


def swift_optional(value):
    return f'"{value}"' if value else "nil"


def read(path):
    text = path.read_text()

    box = VIEWBOX.search(text)
    if not box or box.group(1).split() != ["0", "0", str(GRID), str(GRID)]:
        sys.exit(f"{path.name}: expected a 0 0 {GRID} {GRID} viewBox, "
                 f"got {box and box.group(1)!r}")

    # A <mask> holds a copy of the path it clips. It paints nothing itself, and
    # leaving it in would put that copy in the drawing list twice.
    text = MASK.sub("", text)

    strokes = []
    for kind, raw in ELEMENT.findall(text):
        attrs = dict(ATTR.findall(raw))
        d = circle_d(attrs) if kind == "circle" else attrs.get("d")
        if not d:
            continue
        for ch in d:
            if ch.isalpha() and ch not in ALLOWED:
                sys.exit(f"{path.name}: path command {ch!r} is not supported — "
                         "the Swift parser knows M L H V C Z")
        fill = attrs.get("fill")
        stroke = attrs.get("stroke")
        if fill in (None, "none") and stroke in (None, "none"):
            continue                      # invisible; nothing to draw
        strokes.append({
            "d": d,
            "fill": None if fill in (None, "none") else fill,
            "stroke": None if stroke in (None, "none") else stroke,
            "width": attrs.get("stroke-width", "1"),
            "join": attrs.get("stroke-linejoin"),
            "cap": attrs.get("stroke-linecap"),
            "masked": "mask" in attrs,
        })

    if not strokes:
        sys.exit(f"{path.name}: no painted paths")
    return halo_first(strokes)


def halo_first(strokes):
    """Move a masked outside-stroke under the shape it outlines.

    Figma exports a stroke aligned to the *outside* as the filled path followed
    by the same path stroked at double width through a mask that clips the inner
    half away. Core Graphics has no mask here, so that order would paint white
    over the glyph's own edges and eat it from the outside in.

    Laying the stroke down first and filling on top gives the identical picture:
    the fill covers the inner half of a centred stroke exactly as the mask cut
    it away. Which is also how the hand-drawn cursors in here were already
    built, so this leaves one convention rather than two.
    """
    out = []
    for s in strokes:
        masked = s.pop("masked")
        twin = next((i for i, t in enumerate(out)
                     if t["d"] == s["d"] and t["fill"]), None)
        if masked and s["fill"] is None and s["stroke"] and twin is not None:
            out.insert(twin, s)
        else:
            out.append(s)
    return out


def main():
    if not SVG.is_dir():
        sys.exit(f"{SVG}: not a directory")

    art = []
    for f in sorted(SVG.glob("*.svg")):
        m = NAME.match(f.stem)
        if not m:
            sys.exit(f"{f.name}: name it '<Name> - <x>x<y>.svg' so the hot spot "
                     "travels with the artwork")
        art.append((camel(m.group("name")), int(m.group("x")), int(m.group("y")),
                    read(f), f.name))

    if not art:
        sys.exit(f"no SVGs in {SVG}")

    lines = [
        "// Generated by tools/svg-to-cursors.py — do not edit by hand.",
        "// Source artwork lives in Icons/Cursors/. Re-run the script after changing it.",
        "",
        "import CoreGraphics",
        "",
        "/// One painted subpath of a cursor. Drawn in document order, so an outline",
        "/// pass laid down first shows through as a halo behind the body.",
        "struct CursorStroke {",
        "    let d: String",
        "    let fill: String?",
        "    let stroke: String?",
        "    let width: CGFloat",
        "    let join: String?",
        "    let cap: String?",
        "}",
        "",
        f"/// Cursor artwork on a {GRID}×{GRID} grid.",
        "enum CursorArt: String, CaseIterable {",
    ]
    lines += [f"    case {name}" for name, *_ in art]

    lines += [
        "",
        "    /// From the top-left of the grid, which is the corner `NSCursor`",
        "    /// measures a hot spot from too.",
        "    var hotSpot: CGPoint {",
        "        switch self {",
    ]
    for name, x, y, _, src in art:
        lines.append(f"        case .{name}: return CGPoint(x: {x}, y: {y})   // {src}")
    lines += ["        }", "    }", ""]

    lines += ["    var strokes: [CursorStroke] {", "        switch self {"]
    for name, _, _, strokes, src in art:
        lines.append(f"        case .{name}: return [   // {src}")
        for s in strokes:
            lines.append(
                f'            CursorStroke(d: "{s["d"]}", '
                f'fill: {swift_optional(s["fill"])}, '
                f'stroke: {swift_optional(s["stroke"])}, '
                f'width: {s["width"]}, '
                f'join: {swift_optional(s["join"])}, '
                f'cap: {swift_optional(s["cap"])}),'
            )
        lines.append("        ]")
    lines += ["        }", "    }", "}", ""]

    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT.relative_to(ROOT)} — {len(art)} cursors: "
          + ", ".join(f"{n} @ {x},{y}" for n, x, y, _, _ in art))


if __name__ == "__main__":
    main()
