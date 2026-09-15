# Flip

Frame-by-frame vector animation. Draw with a pen, connect the lines into shapes,
cut shapes out of each other, and export one animated SVG.

## Running it

```bash
swift run Flip
```

Or build a real double-clickable app:

```bash
./make-app.sh release
open build/Flip.app
```

## The interface

One full-width canvas with everything else floating over it, inset from the
window edge. Nothing divides the window into panes any more, so hiding a panel
gives the drawing that space back rather than resizing three columns.

- **Left** — `Layers` is the stack for *the frame you are on*. Layers belong to
  the frame, not to the document; that is what makes this a flipbook rather than
  a timeline. A boolean layer expands to show the shapes it is made of.
  **Right-click a row, or press `⌘R`, to rename it** — deliberately not a
  double-click, which would have made every selection wait out the double-click
  interval before SwiftUI could rule a second click out.
- **Centre** — the artboard, running the full width of the window underneath the
  panels. Scroll to pan, ⌘-scroll or pinch to zoom, ⌥-drag to pan with the mouse,
  `⌘0` to fit. It opens fitted, and the fit knows where the panels and the frame
  strip are, so no edge of the artboard opens hidden behind one.
- **Right** — a rail of five icons beside the panel: *Colors*, *Boolean*, *Path*,
  *Playback*, *Export*. **One at a time, and the one you pick gets the whole
  height of the panel.** The rail stays out on its own card rather than
  collapsing into the panel header, because with only one section open it is the
  only thing saying what the other four are. Its buttons are the same square as
  the tools in the bottom bar, on the same tray padding: those two are the only
  places in the app where a button chooses a *mode* rather than doing something,
  and they are built from one set of numbers so they cannot drift apart.
- **Bottom** — play, one tile per frame, the two ways to add one, delete, and
  *onion skin* and *artboard*, which raise cards. **Duplicate** carries the
  drawing forward; **blank** gives you an empty frame to draw the next drawing
  on, with the previous one showing through as an onion skin. Then a rule, and
  the tools. Undo and step-a-frame are not here: `⌘Z` and `[` `]` are how anyone
  uses them, and a button apiece was four buttons earning nothing.
- **Top** — the document name and nothing else. There is no second strip of
  controls: two of them meant the two ends of the window disagreed about where a
  control belonged, and the bottom one is beside the frames, which is where the
  work is.

**Five tool slots became three.** Brush and pen share one, rectangle and circle
share another — the slot shows whichever you used last, and a **chevron beside it
raises the pair as a named menu**, ticked at the one you are on. Holding the
button does the same thing; the chevron is what says the slot has a second tool
in it at all, and the hold is the shortcut once you know. Two bare glyphs side by
side make you guess which is which, so the menu names them. The letters still
reach all five directly.

**The chevron's box is exactly its glyph, flush against the tool's button.** Two
things follow, and both were bugs before it was: the hover highlight is concentric
with the chevron rather than the chevron sitting off to one side of its own
highlight, and nothing of the chevron lies inside the square, so it cannot end up
behind the accent that square takes when its tool is the one in hand.

That leaves it about 12pt from the tool's *drawing*, which is the floor: the button
carries 8pt of padding around its 20pt glyph, and the chevron artwork fills only
the middle half of its own box. Reaching into the padding to close that was tried
and reverted — 8pt looked right until the tool was selected, when the chevron went
behind the green and its highlight, pushed back out to clear the accent, no longer
sat around the glyph. The two boxes touching is as close as the chevron gets while
staying a control of its own.

To its right is plain tray, outside the box so it is neither target nor highlight.
It leaves the last chevron as far from the tray's edge as the first tool's glyph is
from the other one — flush to the end left 4½pt against the first one's 11½pt, and
the tray read lopsided.

**Everything on the tray hovers a step lighter than the tray itself.** The bar's
hover lifts `panelRaised` over `panel`, which has nothing left to lighten once the
ground is already raised — so on the tools tray the hover simply did not show. The
three tools and the two chevrons all take `panelHover`, the next rung of the same
ramp, which is why a tool and the chevron beside it highlight as the same kind of
thing.

The tools sit at the right-hand end, on a tray a shade lighter than the bar, in
square buttons running its full height. They are the only things in the bar that
are a *mode* rather than an action, and a bigger, squarer button on lighter
ground behind the bar's one remaining rule says so without a label. The glyph
inside is the same size as every other glyph in the app: what marks a tool out is
the button, not a bigger drawing.

**Nine sections became five.** `Info` was four readouts the title bar and the
panels already gave; `Reference` folded into `Artboard`, since both describe the
paper rather than the drawing on it; and `Artboard` and `Onion skin` moved down
to the frame strip, which is where the frames they concern already are. Five is
few enough that an icon can name a section — nine was not.

Nothing in the panels explains itself in prose, and nothing narrates what you
have already done. There is no *Nothing selected*, no *Select two or more
layers*, no *Draw something* on an empty layer list. Every control that had
something worth saying carries it as a tooltip instead, so the explanation is
one hover away rather than permanently in the way — and a state the app can
*show* is shown: an empty list is empty, a disabled button is disabled, and how
far a selection reaches is on the rows and the frame tiles rather than written
out underneath them.

Each tool has its own pointer over the canvas — an arrow, a brush, a nib, a
crosshair — and the panels take the system arrow back.

The transform box is the one thing that cannot use a cursor rect, because its
regions stop being rectangles the moment the box is turned: the bounding rectangle
of a 45° bar covers the middle of the selection, and `addCursorRect` takes nothing
else. So the canvas sets the pointer itself on every mouse move, and only while it
is genuinely the view under the pointer — `mouseMoved` goes to the first responder,
which is the canvas even when the pointer is over a panel, and a resize cursor
showing through the layer list is the very thing the panels' own rects exist to
prevent. The tool's rect stays for everything else: it is what covers the pointer
arriving in the view without moving. The canvas does not know
where the panels are: it lays one cursor rect over its whole bounds, and each
floating card lays its own on top, because AppKit gives the rect to the topmost
view under the pointer. Adding a panel costs nothing; there is no list of frames
to keep in step. The artwork carries its hot spot in its filename
(`Brush - 12x21.svg`) so the two can never drift apart. The transform box's eight
pointers — four stretch arrows and a turn arrow per quadrant — are centred glyphs,
so they are all `16x16`.

The icons are drawn from vector path data rather than shipped as images.
`Icons/` holds the SVG artwork; `tools/svg-to-swift.py` turns it into
`Sources/Flip/UI/Icons.swift` as path strings, which `IconShape` parses once and
strokes at whatever size it is asked for. A SwiftPM executable has no asset
catalogue to compile an SVG into, and a PNG would neither tint with
`foregroundStyle` nor stay sharp where the tools are drawn half again as large
as everything else — so the icons behave exactly like the SF Symbols they
replaced. Re-run the script after changing the artwork.

Four colours carry the whole interface: `canvas` behind everything, `panel` for
every floating card, `panelRaised` for the controls inside one, and `border` for
both the 1px rules and the cards' own edges — there is no separate divider colour,
because a rule and an edge are the same line doing two jobs. A fifth, `edge`, is a
translucent white hairline for the places the theme does not control the colour
underneath: a swatch, a colour well, a frame thumbnail. It has to be translucent to
lift off a bright yellow and a near-black alike, and over a panel it lands within a
shade of `border`, so the two read as one edge everywhere they meet.

Everything you can press *in a panel* is the same height — the hex field set it,
and a panel whose controls disagree about their height reads as several panels.
Labelled buttons take one step up from it — they carry a glyph *and* a word, and
at field height they read as cramped in a way a bare field does not. The bottom bar
keeps its own, larger, measure again: its buttons are as tall as the bar is deep,
so a hover lands on a target rather than on a rectangle the same size as the icon
it is meant to be highlighting. Swatches are
squares of that size rather than stripes, and wrap when a row runs out.

Sliders put their label on a line of their own and give the track the full width
of the panel, with the value inside the track's right-hand end rather than in a
column beside it — a column costs the track 46pt for four characters. The covered
part of the track is filled, the handle is the right-hand end of that fill, and
the value turns dark once the fill reaches it, rather than going white on white.

**The number is always whole.** A decimal place that is permanently `.0` is noise,
and a 0–1 fraction reads better as a percentage than as `0.35`. Only the *reading*
is rounded — the value underneath stays continuous, so the handle still slides
rather than stepping between whole numbers. The app has one typeface throughout;
the readouts that change while you drag ask for tabular figures so the number does
not shuffle sideways as its digits change width. At 232pt a labelled row left a stub of a track and a
12pt knob on it, which is a small target for the fine adjustment these get used
for.

Colours are a 48pt square of the colour itself and six hex digits you can type
into — no `#`, since it is a character you would have to keep alive while
retyping and would delete by accident. The square opens the system colour panel.
`ColorPicker` draws a capsule that cannot be restyled, and a capsule reads as a
button rather than as the colour it is showing. An eye closes the row, square and
exactly as tall as the field beside it so the two read as one control — and it
means *no paint at all* rather than a transparent colour, which is what keeps an
unclosed line a line. A rule separates one property from the next.

The frame strip's two popups are not popovers. `NSPopover` draws an arrow and a
light vibrant backing that cannot be turned off, which made them the only things
in the app that did not look like the panels; they are the same floating card at
the same width, riding 12pt above the bar. A click on the canvas dismisses one,
and is swallowed doing it — that click is handled in the canvas rather than by a
transparent layer over it, because the canvas is an `NSView` and AppKit hit-tests
it before any SwiftUI gesture drawn on top of it sees the event.

## Drawing, and how a line becomes a shape

Draw freehand with the pen (`P`). The raw pointer samples are thinned with
Ramer–Douglas–Peucker and then given Catmull-Rom tangents, so a sixty-sample
scribble lands as a dozen anchors with real Bézier handles rather than a
polyline. **End the stroke near where you began and it closes and fills** — that
is the fast path.

### Placing points

The pen (`P`) also builds paths a point at a time, the way every other vector
editor does.

- **Click** for a corner.
- **Click and drag** for a smooth point — the handles come out symmetrically, so
  the curve runs through cleanly. Hold `⌥` while dragging to move only the
  outgoing handle, which is how you put a corner behind you and a curve ahead.
- A **rubber band** previews the segment you are about to commit, curving out of
  the last point's handle so what you see is what you will get.
- **Click the first point to close.** A ring appears over it once there are
  enough points to enclose something, and the path takes a fill the moment it
  does — it was drawn without one, because filling an open path would have meant
  closing it on screen before you asked.
- `Esc` or `Return` ends the path open. So does picking up another tool.

Every point is committed as it lands, so `⌘Z` walks back through them one at a
time and quitting half way leaves a real path rather than losing the work.

The same tool edits what is already there. It shows every anchor, and the
handles of the selected layer. Open ends of a path are drawn as rings, because
those are the only things that can be joined:

- **Drag one ring onto another** and the two paths weld into one. A green circle
  appears while you are in range.
- Weld the last gap and the path **closes and gets filled**, which is the moment
  a set of construction lines stops being lines and becomes a shape.
- `Path ▸ Join points` does the same for two points selected with shift-click,
  and `Close path` joins the two ends of one path.

Two ends welded together become a single averaged anchor, and the curvature
carries across the seam, so a joined path does not kink where it was joined.

## Resizing and turning

Select something with the cursor (`V`) and its bounding box gets four square
grips on the corners. **The edges between them are four more controls** — the
box's own line is the bar you drag, so there is nothing extra drawn along it to
find.

- **Drag a bar** and the selection stretches along that one axis. The top and
  bottom bars move it vertically, the sides horizontally, and the opposite edge
  holds still. Movement across the bar is ignored, so a drag that wanders off the
  axis does not quietly change the other dimension.
- **Drag a corner** and it stretches both axes at once, with the opposite corner
  holding still.
- **Drag from just outside a corner** and the selection turns about the centre of
  its box. The turn begins 6pt clear of the box and runs out to 22pt; nearer than
  that is the corner's own grip, and further out is plain canvas again, where a
  drag starts a marquee as it always did.
- **Hold shift to lock it.** A bar then drives *both* axes from the one it runs
  across, about the centre of the axis it does not — so a locked pull on the top
  bar grows the shape symmetrically sideways instead of dragging its left edge
  along too. A corner takes its single factor from whichever axis the pointer
  pushed furthest, so the shape keeps its proportions. A turn locks to 15° steps,
  which is a fifth of a right angle and a twenty-fourth of the circle, so the
  cardinals and the diagonals are all on it.

**Nothing is drawn in the turn zone**, and that is deliberate: a grip drawn 6pt
off the corner would crowd the very corner it is meant to be distinct from. The
pointer is what announces it, which is why the corners get their own four
drawings — a turn arrow for each quadrant — beside the four stretch arrows.

**Stroke width never changes**, whatever you drag. A stroke is a property of the
layer rather than a dimension of the shape, and a line that thinned out because
the drawing was made smaller is a line you would have to set back by hand every
time.

### The box turns with the shape

A turned selection gets a **turned box**: it hugs the shape at its own angle
rather than standing upright around it, and its extent is measured in that turned
frame, so it stays snug instead of being the upright bounds of a diagonal shape.

Which means a bar on a turned selection stretches it along **its own** axis, not
the artboard's. The whole drag is worked out in the box's frame and carried back
into the document's, which is one composition of three transforms rather than a
special case.

The pointer follows it round. The four stretch drawings cover eight directions at
45° apart and the four turn drawings cover the quadrants, so each grip asks for
whichever is nearest to the way it *actually faces on screen* — the top bar of a
shape lying on its side gets the sideways arrows.

### Which way up a shape is, is recorded; the geometry stays absolute

There is no transform stored on a layer waiting to be applied. A turn rewrites the
anchors and their handles, exactly as a move rewrites the points — every
coordinate in this document is absolute, and that is what lets paste land in
place, a boolean clip exactly, and the export carry no transforms at all.

What a layer *does* carry is `orientation`: one angle saying how far its own axes
are turned from the document's. Nothing in rendering, hit testing or either export
reads it. Its only job is the box — so that the box can turn, and a stretch made
through it can work along the shape's axes. It is optional and left out entirely
for a layer that is square to the document, which is both how older `.flip` files
keep loading and why the zero case is not written into every layer of every saved
document.

A selection whose layers disagree about which way up they are gets the upright
box. That is the honest answer: there is no shared axis to stretch along, and
picking one shape's angle would shear the rest of the selection along it.

### It works from a snapshot, not from the last frame

A drag records the selection's geometry as it was when the grip was taken hold of,
and every update transforms *that*. So the transform is absolute rather than
compounding, which is what lets a bar be dragged **back through its anchor and out
the far side**: the shape mirrors, and pulling back restores it. A running
multiplication would have lost it for good at the instant it passed through zero,
and a turn would have accumulated rounding all the way round the circle. A
mirrored closed path is re-wound the document's way as it goes, because every
closed subpath here has to agree about its winding or a union stops being a plain
non-zero fill of the combined path.

The grip also remembers where in itself it was grabbed, so the box tracks the
pointer from that spot rather than jumping under it on the first move.

### Both reach every frame the selection reaches

Same rule as moving, and for the same reason: a linked layer (⌥-click a row, or
`⌥⌘L`) is the same element in each frame, so resizing or turning it on one frame
only would pull apart the very thing that made it linked. Select within a single
frame and it is local again.

## Groups

`⌘G` wraps the selected layers in a group; `⇧⌘G` takes it apart again. A group
**does nothing to what is inside it** — that is the whole point, and the whole
difference from a boolean. The children keep their own paint and their own
order; the group is a name and a place in the stack, so thirty shapes can be
read as four things.

It nests, so a group can hold a group, and the panel opens to any depth. A
boolean can hold one too: a group has no single path to clip with, so the
renderer falls back to compositing the children in a transparency layer, which
is the same path a boolean nested inside a boolean already took.

Grouping a **single** layer is allowed. It is how you start a group you mean to
fill, and refusing it would be a rule with nothing behind it.

The group takes no fill and no stroke of its own. Giving it colours would put two
swatches in the panel for one thing and leave the group's looking like a lie.

## Selecting in the panel

- **Click** a row for that layer.
- **⇧-click** for everything from the last plain click to here — a *run*, which
  is what shift means in every list on this platform. With thirty shapes in a
  frame it is what you reach for far more often than a scattering.
- **⌘-click** for one layer more, or one fewer. Picking layers out one at a time
  moved here from shift, which is also where the rest of the system keeps it.
- **⌥-click** for the same layer in every frame — see *One layer, in every frame*.

What lies "between" two rows depends on which groups are open, so the range runs
along the rows the panel is actually **showing**, not along the stack. The panel
hands the model that order rather than the model working it out, because only the
panel knows what is expanded.

**The disclosure chevron and the eye are gestures, not buttons.** The row carries
a tap of its own for selection, and in SwiftUI an ancestor's tap beats a
descendant's button — so both controls were drawn, were hit, and did nothing,
every tap selecting the row instead. A `highPriorityGesture` is the one ordering
that reverses it. They also take the row's full height now: 9×13 was a small
target for the control you have to hit to navigate a deep stack.

## Opacity

`Colors ▸ Opacity` fades the selection. It is a property of the **layer**, not of
its colours: the alpha inside a fill or a stroke makes one of them translucent,
where this makes the whole layer translucent at once.

Which is why it is *composited* rather than multiplied into the paint. A shape at
50% would otherwise show its own stroke through its own fill, and a group at 50%
would show its children through each other. The canvas draws the layer into a
transparency layer and fades that; the export writes `opacity` on a group, which
is the same rule — so the two agree by construction, exactly as the booleans do.

A group takes it as one thing, and its children keep their own, so the two
multiply. Fading a whole group out is one edit rather than one per child.

The slider reads the selection rather than holding its last value, unlike fill
and stroke — those are as much the *next* thing you will draw as the thing you
have selected, where an opacity is only ever the selection's.

**Width and opacity apply on every step of the drag**, so the canvas answers
under your hand instead of at the moment you let go. The onion and reference
sliders always did, by writing straight to the document; these two were the only
ones that waited for the mouse to come up.

Undo cannot follow suit — a drag is a hundred changes and a single edit — so the
snapshot is taken **once**, as the drag begins, and the steps push nothing. The
frame thumbnails are left stale until it ends, because re-rasterising every tile
on every step is thirty renders a step for pictures nobody is watching while they
watch the canvas.

## Booleans, which are never destructive

Select two or more layers and pick an operation. **The lowest layer is the base
and everything above it operates on it** — stack a shape on top of another and
`Subtract` removes the overlap.

The children stay intact. Nothing is flattened, ever. A boolean layer is a
*group with an operation*, so:

- `Release` gives you back both shapes, still editable.
- Either side can be moved or reshaped and the result recomputes.
- The result recolours like any other layer, because colour was never baked into
  the geometry.

That last point is why this app has no boolean geometry library, and does not
need one. CoreGraphics has no boolean path operator, and rather than flatten
curves to polylines and run a clipper, every operation is expressed as
**clipping**:

```
unite      combined path, non-zero fill
exclude    combined path, even-odd fill
intersect  clip to every child in turn
subtract   clip to the first child, then to the outside of each other one
           (a huge rectangle plus that child, filled even-odd)
```

This is exact — the curves are never approximated — and it maps one-to-one onto
SVG's `mask`, so the canvas and the export agree by construction rather than by
being separately correct. When a child is *itself* a subtract or intersect there
is no single path to clip with, and the renderer falls back to compositing the
children in a transparency layer with `destinationOut`; nesting works to any
depth either way.

Two operations need care with their outline. A union's combined path still
contains the seams where its children overlap, and those are not edges of the
result, so the outline is stroked at double width and the union's interior
punched out of it — which erases the seams and leaves one continuous contour.
`Subtract` and `intersect` do the reverse, stroking at double width *inside* the
clip. `Exclude` needs neither: there the overlap genuinely is a boundary.

## Icon

`Icon/icon.png` is the artwork (`Icon/source.png` also works). `make-app.sh`
recomposes `Resources/AppIcon.icns` whenever the source is newer, or run it
directly:

```bash
swift Tools/make-icon.swift Icon/icon.png Resources/AppIcon.icns
```

The artwork is written **full-bleed** — no rounding, inset or shadow of its own.
Current macOS masks app icons into the system shape and draws the background and
shadow itself, so pre-rounded, pre-inset artwork gets shaped twice and ends up a
small picture floating inside a large empty tile.

The current source is 256×256. It upscales acceptably, but 1024×1024 would be
sharper in the Dock and in Finder's large icon view, and the motif is fine white
line work that thins out badly in the small slots.

## Reference image

`Artboard ▸ Reference ▸ Choose image…`, from the artboard card in the frame
strip. It sits under every frame — under the onion ghosts
too — at whatever opacity you set.

It is **document-level, not per-frame**, on purpose. With per-frame layer stacks
nothing else in this app persists between frames, so this is the one thing that
can hold still while the drawing changes over it. (A different reference per
frame — rotoscoping — is a separate feature and is not this one.)

A fresh reference is aspect-fit and centred on the artboard. `Scale` resizes it
about its own centre and `Recentre` puts it back. It arrives **locked**, because
a reference you are drawing over should not shift when a drag goes slightly
wrong; unlock it and ⌘-drag on the canvas moves it, in any tool.

The image's original bytes are stored in the `.flip` file verbatim, so a document
stays self-contained and does not break when the picture is moved or renamed. It
is a guide, not artwork: it never reaches the exported SVG and never appears in a
frame thumbnail.

## Moving shapes between frames

`⌘C` / `⌘X` / `⌘V`. Paste is always **paste in place**: the shape lands at exactly
the coordinates it was copied from, on whatever frame you are on.

Geometry is stored in absolute document points, so *not* translating is what makes
this work — there is deliberately no paste offset. When consecutive frames are
drawings of the same scene, "where it already was" is the only useful answer, and
a nudge of a few points would be something to undo every single time.

`⌥⌘V` pastes into **every** frame at once, which is how you give an animation an
element that holds still — per-frame layer stacks mean anything static has to
exist once per frame. The pasted copies come out **linked**, so ⌥-clicking one of
them afterwards selects all of them and the element can be recoloured or
repositioned as one thing.

Copying reads from the frame on screen only, even when the selection spans several,
since a paste lands in one frame. Pasted shapes get fresh identities, so they
never collide with the originals when a selection spans the document. Colours,
stroke width, and any boolean group with its children all come across intact.

## Onion skinning

`⇧O`, or the eye in the onion card, which the frame strip's onion button raises
along with the range and opacity. Earlier frames ghost in warm red, later ones in
cool blue, both fading off with distance, and the counts are set separately —
you usually want more history than future. Ghosts are hidden during playback,
where they would only smear.

A tint recolours what a layer already paints and never adds paint it does not
have, so an outline ghosts as an outline rather than filling in.

**Duplicating a frame leaves nothing for the onion skin to show.** The copy is
geometrically identical to the frame behind it, so the ghost sits exactly under
its own duplicate and is completely hidden — onion skinning looks broken when it
is working perfectly, because there is no difference to draw. Move or reshape
anything and the ghost appears. To draw the next drawing *against* the previous
one, add a **blank** frame instead.

## Export

`⌘E` writes one SVG.

Frames are hard cuts, not tweens, so each frame is a group that is invisible by
default and switched on for its slice of the cycle by a CSS animation with a
per-frame delay. No interpolation is involved, which is why the file plays
identically in every browser. Two keyframe stops sit at the same value before the
drop, so there is nothing for the renderer to interpolate across and the cut
stays hard. Turning *Loop* off holds the last frame instead of starting over, in
the app and in the file.

**The export uses masks, not flattened outlines.** It plays correctly anywhere,
but opening it in Illustrator shows a masked group rather than one merged path.
This is also why the format is SVG and not Lottie: Lottie has no `clipPath`,
only matte layers, which would multiply per frame.

### GIF

`⇧⌘E` writes an animated GIF, with the options in `Export`. It is a bitmap, so
prefer the SVG unless something downstream insists on GIF.

Two things about the format are worth knowing, because they are visible in the
result rather than hidden in the file:

**Timing is quantised to hundredths of a second.** 12 fps wants 8.333 cs per
frame and has to land on 8 or 9. Rounding every frame the same way drifts — thirty
frames at 8 cs run 7% fast — so the remainder is carried from one frame to the
next: individual frames differ by a hundredth and the total duration comes out
exact. Delays are also floored at 2 cs, because shorter ones are widely
re-interpreted as 10, which means anything above 50 fps plays slower than it
should.

**Alpha is one bit.** `Transparent` drops the paper colour, but a pixel is either
fully present or fully gone — there is no partial coverage — so antialiased edges
have to be thresholded. `Edge cutoff` sets how much coverage a pixel needs to
survive: lower keeps more of the soft edge and looks chunkier, higher trims it and
thins strokes. The pixels that survive are un-premultiplied, so they keep their
own colour instead of fading toward the black they were composited against —
skipping that step is what gives carelessly made transparent GIFs their grubby
dark outline.

`GIF size` is a fraction of the artboard. GIF barely compresses, so this is the
main lever on file size.

## Autosave

**Every change is written to disk.** A new shape, a colour, a slider, a reorder, a
group, an undo — they all reach the document through one setter, which is where
autosave is hooked, so there is no list of edits to keep in step with.

Changes are coalesced into at most one write every 1.2 seconds. The timer is
armed by the *first* change of a burst and then left alone rather than pushed
back by each one, so a drag that lasts a minute is written a dozen times over
instead of not at all — and a single change still lands about a second later.
Writes are atomic: autosave writes over the only copy of the drawing, and a crash
half way through a plain write would leave a truncated file where the work was.

Quitting inside that window flushes first. It is the one second of work the
feature could otherwise lose.

### Where it goes, and what it is called

A document with no home of its own lands in **`~/Documents/Flip Creations`**,
made on demand — an app opened and closed without drawing anything leaves nothing
behind. The name is

    Untitled-2026-09-04, 19-34.flip

from the moment the document was **started**, not last touched, so a folder of
sketches lists in the order they were begun and a name never moves under you. The
locale is fixed, so the filename does not come out differently for someone whose
region writes dates another way. A collision gets a number.

**A document opened from somewhere else is written back to where it came from.**
Opening a `.flip` from the Desktop and editing it should not quietly leave a
second copy in `Flip Creations` that then disagrees with the original.

### Renaming

**Click the document's name in the title bar and type.** On return — or on
clicking away, the way the layer rows commit theirs — the file is *renamed*, not
copied. Escape abandons it.

A rename before the first autosave has no file to move yet, so the name is kept
and the first write uses it. Which is also why the title bar shows the name a new
document *will* be given rather than `Untitled`: with autosave on, that name is a
second away, and showing a placeholder first would make it look as though
something had changed.

`⌘S` and `⇧⌘S` still work. `⌘S` writes now; Save As is for putting a copy
somewhere else, and autosave follows the document to its new home.

Autosave failures are not an alert. This runs every second or so, and a modal
that reappears as fast as it is dismissed is worse than the failure — the title
bar carries the message instead, and `⌘S` still reports properly.

`⌘S` saves the editable document as `.flip`, which is plain JSON. `⌘O` opens one,
and so does double-clicking it in the Finder — the app declares the document type,
so Launch Services hands the file over, and there is a delegate to receive it.
Both routes go through the same loader.

## Recolouring a whole animation

Selection spans frames. Per-frame layer stacks mean the same shape exists once
per frame, so recolouring a six-frame drawing would otherwise be six identical
edits.

- `⌘A` selects every layer in the frame you are on.
- `⇧⌘A` selects every layer in **every** frame. One colour change then repaints
  the whole animation.
- `⌘D` deselects. `Colors` carries both buttons. How far a selection reaches is
  never written out — it is on the `Layers` header, on the rows themselves, and
  on the frame tiles, which is the next section.

Paint, stroke, width and delete apply everywhere the selection reaches, and undo
restores all of it in one step. Booleans, `Release`, and the canvas's own
selection outlines and point handles stay local to the frame on screen, since
they would otherwise act on shapes that are not visible.

## One layer, in every frame

`⇧⌘A` is all-or-nothing. Most of the time what you want is *one* element of the
drawing — the head, the background, a logo — in every frame at once, so that
recolouring it, moving it, renaming it or hiding it is one action instead of
thirty.

**⌥-click a row in `Layers`**, or `⌥⌘L`, or `Select in All Frames` from the row's
right-click menu, which counts them first and tells you how many it found.
⇧⌥-click adds a second linked layer to what is already selected.

Once selected, **paint, stroke, width, move, rename, show/hide, reorder and
delete all reach every frame**, in one undo step. Moving is the notable one:
geometry used to be the last thing that stayed local to the frame on screen, and
it cannot be, because a linked layer nudged on one frame only would pull apart
the very thing that made it linked. Select within a single frame — a plain click,
or the canvas — and a move is local again, exactly as before.

Because the panel can only ever show the frame you are on, the reach is stated
three times over rather than left to be discovered: the header reads `🔗 25`, the
selected rows carry the same glyph, and the frame strip puts a dot on every tile
the selection touches.

### What counts as the same layer

Not the name, which would not survive contact with this app: shapes are born
`Shape`, `Line`, `Rectangle` or `Ellipse`, so one frame routinely holds four
layers called `Shape` and matching on the name would select all four. Worse,
renaming was per-frame, so naming a layer `Head` on one frame would have broken
the match on the other twenty-nine — the act of making a name meaningful would
have destroyed its only use.

Instead each layer carries a **track**, stamped on both sides at the moment one
layer starts existing in two frames:

```
Duplicate frame   ⌘D    the copy shares the original's tracks
Paste in place    ⌘V    the paste joins the track it was copied from
Paste everywhere  ⌥⌘V   the whole pasted set becomes one new track
```

A track is exact, and it is *not* the layer's identity — the copy is a new layer
with a new `id` and the same track. So it survives renaming and reordering, which
is the whole point, and `Release`ing a boolean or reshaping either side of it
changes nothing about which frames the layer is in. A second paste onto a frame
that already holds that track drops it, because "the same layer, once per frame"
is what a track means and two copies on one frame are two layers.

Renaming a linked layer renames it in every frame, which is what makes naming
worth doing: `Head` now means the same thing on all thirty frames.

**Documents saved before tracks existed have none**, and fall back to matching on
**name plus position in the stack** — all that two copies of a layer share when
nothing recorded that they were copies. It is good rather than perfect, and it
says so: on a thirty-frame drawing whose second layer is a `Shape` on twenty-five
frames and a `Subtract` on five, ⌥-click reports *25 frames* rather than thirty,
because the five are genuinely a different layer in that slot. Reordering one
frame on its own, or renaming one frame's copy, also drops it out of a fallback
match. Duplicate a frame once and everything it touches is on exact tracks from
then on.

## Keys

**`⌘/` puts this list on screen**, from `View ▸ Shortcuts`. It is a legend and
nothing on it is editable: a key that can be rebound has to be stored, migrated
and shown differently everywhere it is named — and every control in this app
already names its own key in its tooltip, so a rebound key would have to reach
into all of those too. Three costs for a tool whose keys are nearly all a single
letter.

Each key is set on its own square cap, because a shortcut is several keys and the
caps are what say where one ends and the next begins — `⇧⌘D` as plain text is one
word until you already know it is three. A word like `shift` or `drag` gets the
same cap, just wider: the same thing is being named either way. Two chords on one
row are a pair or a choice — `[` and `]`, ⌥↑ and ⌥↓ — and sit further apart than
the keys within one chord.

The card is the only thing in the app that lists what it cannot read: the menus
declare most of these, the canvas's `keyDown` the bare letters, and the modifier
drags are the canvas's own, so a shortcut added in one of those three places has
to be added to `ShortcutsCard` as well. Its `×` closes it, and so do `esc` and a
click on the canvas — that click is swallowed, so putting the card away cannot
also start a shape on the artboard behind it.

| | |
|---|---|
| `V` `B` `P` `R` `O` | cursor, brush, bezier, rectangle, circle |
| space | play / pause |
| `<` `>` | previous / next frame |
| `N` | new blank frame |
| `⇧O` | onion skin |
| `⌫` | delete selection, or the selected points in the point tool |
| `⌥`-drag | pan |
| `⌘`-drag | move the reference image, when it is unlocked |
| `⌥` while dragging a handle | break the handle's symmetry |
| shift while drawing a rect or ellipse | constrain to a square or circle |
| shift while dragging a transform grip | lock it — proportional on a bar or corner, 15° steps on a turn |
| `⌘E` / `⇧⌘E` | export animated SVG / animated GIF |
| `⌘C` / `⌘X` / `⌘V` | copy / cut / paste in place |
| `⌥⌘V` | paste into every frame |
| `⌘A` / `⇧⌘A` | select every layer in this frame / in every frame |
| `⌥⌘L`, or ⌥-click a row | select the *same* layer in every frame |
| `⌘R` | rename the selected layer — in every frame it is selected in |
| `⌘G` / `⌘⌫` | group / ungroup |
| `⌘D` | deselect |
| `⌘D` | duplicate frame |
| `⇧⌘<` / `⇧⌘>` | move this frame left / right |
| `]` / `[` | bring the layer to the front / send it to the back |
| `⌘]` / `⌘[` | bring it forward / send it backward |
| `⌘0` | fit to window |
| `⌘/` | the shortcuts legend |
| click the title | rename the document, and its file |
| `⌘1` / `⌘2` | show or hide the layers panel / the tools panel |
| hold a tool slot | the other tool in that slot |

Single-letter shortcuts are handled by the canvas rather than the menu, so they
cannot fire while a rename field has the keyboard. `O` is the circle tool, so
onion skinning sits on its shifted twin; `⌘D` duplicates a frame, so deselecting
is `esc`.

**`<` and `>` step the frames; the brackets order the layers.** They were the
other way round, and the brackets are where this platform keeps layer order.
Both spellings of each frame key work — `charactersIgnoringModifiers` keeps shift
applied, so the same physical key arrives as `,` or as `<` depending on whether
you reached for the character printed on it, and the canvas takes either.

**`⇧⌘<` and `⇧⌘>` are read by the canvas too, not declared on their menu items.**
SwiftUI drops a comma key equivalent: the item came out with the modifier set and
*no key at all*, so `Move Frame Left` could never have fired. Reading the
character directly is exact, and it keeps the pair on one mechanism.

**New blank frame is `N` alone.** It had `⇧⌘D` as well — the only action in the
app with two keys, and one of them redundant.

The legend does not list undo, redo, cut, copy or paste in place. They are the
same on every Mac, and a legend earns its space by carrying what is particular to
this app.

## What it does not do

No tweening — this is frame-by-frame by design, and onion skinning is the tool
that replaces interpolation. Undo is a document snapshot stack, which is coarse
but never inconsistent.
