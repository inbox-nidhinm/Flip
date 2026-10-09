# Build log

The whole record, oldest first.

`Sources/Flip/UI/VersionHistory.swift` ships in the app and carries **features
only** — the things it can do that it could not before, one line each. That is a
small fraction of what is here. Cursors, shortcuts, rearrangements, performance
work, rewrites and every fault fixed before anyone met it are recorded in this
file and nowhere else.

A day that produced a feature became a **version** and is headed with its
number. A day that did not still has its section — it happened — and is marked
*no version*. Numbering is `v0.0.<build>.<version>`.

---

## v0.0.1.1 — 19 August

**The first build** · *The first build*

- Draw a line, and have its ends meet: a closed shape, filled and coloured.

- A layers panel where the layers belong to the frame you are on, not to the document.

- Booleans on the selection — the beginning of subtracting one shape out of another.

- A reference image that sits under the artboard to draw over.

- Onion skinning, and frames that could be added, duplicated and stepped through.

- Export to SVG.

- A shape copied from one frame lands in exactly the same place in the next.

- Letters for the tools — B, R, O, V, P — and brackets to step a frame.

---

## v0.0.1.2 — 21 August

**The first build** · *Export, and getting out of the way*

- GIF export, transparency included.

- Renaming a layer moved off the double-click and onto a right-click, with ⌘R beside it — a double-click would have made every selection wait out the interval first.

- A pass on how long the panel took to answer a click.

---

## v0.0.1.3 — 23 August

**The first build** · *One layer, in every frame*

- A selection that reaches past the frame on screen and picks up the same layer everywhere it appears, so a change lands once instead of once per frame.

---

## v0.0.1.4 — 1 September

**The first build** · *The interface, rebuilt*

- The panels stopped dividing the window and started floating over a full-width artboard.

- One section open at a time, taking the whole height of the panel.

- Every explanatory line taken out — no Nothing selected, no Draw something. A state the app can show is shown.

- The app's own icon set, drawn on one 24-unit grid.

- The tools moved to their own tray, at full bar height, with a chevron raising the pair behind each slot.

- Undo, redo and step-a-frame left the bar; the keys already did them.

---

## v0.0.1.5 — 2 September

**The first build** · *Cursors, curves and the transform box*

- #1B8F51 became the one thing selection reads as, everywhere.

- A pointer per tool, drawn rather than borrowed, at 1.2× with the hot spots scaled to match — and the system arrow handed back over the panels.

- The pen tool learned to place a point, drag out a curve, and close a path onto its own first point.

- A transform box with corner grips that turns with the shape, and a cursor per direction.

- The current frame's tile stands 1.1× proud, and the strip fades at whichever end can still scroll.

- Shapes number themselves — Shape 1, Rectangle 2 — instead of arriving nameless.

---

## v0.0.1.6 — 4 September

**The first build** · *Grain, colour, and the shelf*

- Grain under every panel, tiled rather than stretched, at half the scale it started at.

- The app's own colour picker in place of the system panel, and a palette each document can add to on top of the nine built in.

- Autosave to Flip Creations, with no dialog and no asking.

- A home shelf: recent projects with thumbnails, folders, rename, delete, move.

- Groups, shift-click for a run of layers, ⌘-click to reach a shape inside one.

- Arrow keys nudge a point; shift makes it eight.

- The hand tool, and holding control to pan without leaving the tool you are on.

- Every shortcut on one card — a legend, not a settings sheet.

---

## v0.0.1.7 — 5 September

**The first build** · *Onboarding, and the panel that went away*

- A first run that hands the app over rather than explaining it.

- The side tool bar is gone. What shows in the panel now is what the tool in hand and the selection can actually be done to.

- Playback and export fold away, and come up shut.

- Blend modes, under opacity, where the other thing that acts on a layer as a unit already was.

- The switch became the slider's own parts — same track, same pill, moved to one end.

- A click anywhere outside a popup puts it away.

- Selecting a layer off-screen scrolls the panel to it.

- Grain on the canvas and the shelf, so nothing reads as a different material.

- This list, on its own card at the foot of Settings — and the version became the newest build number rather than a figure of its own.

- Everything you can click now answers the pointer: the onboarding buttons, the stepper, the colour well, the swatches, the toggle, the document name, and a layer row's chevron and eye, which take their own click and so needed their own hover.

---

## v0.0.1.8 — 6 September

**The first build** · *Stills, and a pass on the shelf*

- Picking a feature on the last onboarding page turns its plate like a leaf, lifting from the top-right corner — the page bends around a cylinder rather than pivoting flat, and a shadow travels with the fold onto the plate underneath. The reverse of the leaf is the plate's own ground colour lifted toward the light, read off its corners, because a page's back is the same stock as its face.

- The frame you are on, written out as a PNG. Full size, and no scale to set: a GIF is thirty frames and gets large quickly, but a still is one image, and an export you have to remember to put back to 100% is a trap rather than an option.

- Transparent belongs to both exporters now rather than to the GIF alone. PNG carries eight bits of alpha, so an antialiased edge survives as one — none of the thresholding and un-premultiplying a transparent GIF needs applies to it, and Cutoff stays the GIF's own.

- A shelf card's caption sits 12 off the bottom instead of 5. That number was there to inset the thumbnail from the card's edge; under the date there is no picture to inset.

- The folding section headings lost the hover they were given yesterday. A band behind a heading read as a selected row rather than as a control answering the pointer.

---

## 7 September — no version

*Onion skin and the artboard moved into the tools panel*

Real work, but nothing a user would call a feature — so it is here and
not in the app's own list.

- Onion skin and the artboard left the frame strip for the tools panel, as two folding groups of their own. Both describe the paper rather than the mark in hand — the ghosts either side of this frame, the size of the sheet, the ground under it — and in the panel they are labelled rows in a column instead of a card raised over the canvas.

- They come up only with the cursor or the hand. Those are the two tools that make nothing, so they are the two where the paper is what you are actually touching; with a brush down, the rows you want are fill, stroke and width, and these would only have pushed them along.

- The frame strip is the frames and the tools now, and nothing else — two buttons shorter, and every button left in it acts on a frame or picks a tool.

- Onion's on/off became a `Show` row rather than the eye the popup carried in its header, which is the same question the reference below it already asks the same way.

---

## v0.0.2.1 — 7 September

**Bones** · *Bones*

- A bone tool, in the strip beside the other three. It makes no marks: it moves what is already drawn, so a limb can be carried from one frame to the next by turning it rather than by drawing it again. There are no in-betweens and no timeline — the frames are still yours, and the armature is scaffolding for posing them.

- Bones are drawn only with the bone tool in hand, and only for the armature driving the selected layer. Everywhere else they are lines across someone else's drawing, and a frame carrying three rigs put all of them over the artwork at once. With nothing selected the last rig placed or posed shows, so building one from scratch is not done blind.

- The layer under the pointer says what a click would do to it: solid amber to take it into the armature, dashed in the rig's own colour to let it go. It runs the same enclosure query the click does, so the highlight cannot promise something the click will not deliver, and it only appears while placing — in Pose a click binds nothing, and offering it there would be a lie.

- The layer highlight and click-to-bind follow the same scope. Keyed to the last rig *touched*, a layer could wear a rig's colour while its bones were hidden — and a click could bind a layer to an armature that was not on screen, which is an edit with no visible result and no obvious way back.

- Its operations sit in a bar of their own, above the frame strip and up only while the tool is in hand. They were a popup hanging off a chevron first, and that was wrong: a rig has two modes and five operations and you reach for all of them repeatedly while posing, so a card you have to reopen between every one is a card in the way. The bar costs the room only when the tool is out.

- One tool has to both build a rig and move it, and a tip is at once a pose handle and the place a child bone hangs from, so Place and Pose are a pair of modes rather than a modifier. Nothing was free to overload: Option already stretches a bone, and Control and Option both pan.

- Two ways a drag behaves. IK lets three bones up the chain rearrange themselves to meet the cursor, which is quicker and less exact; FK moves only the bone you took hold of and swings its children along, and with Option stretches it as well. Letters rather than glyphs, because two arrows side by side would be a guess where these are what riggers already call them.

- An armature owns the layers it drives, and only those. Proximity was tried first and is a liar in a real drawing — it cannot tell a sleeve from the arm inside it from the torso behind it, and one bone with nothing else in the frame claimed every layer on the artboard. Ownership is stored on the layer instead, so reordering the stack never re-binds a rig.

- What a bone claims is what it lies *inside*, judged by half its own length rather than by one end. Testing the origin alone meant a chain started at a shoulder — just outside the limb it drives — claimed nothing, and no later bone could recover it. Enclosure is exact here because the fill has a real inside: `CGPath` answers it on the curves themselves rather than on a polygon standing in for them.

- A bone claims every layer enclosing it, not the topmost, since binding a sleeve and leaving the arm behind is the more common mistake. It never takes a layer another rig already holds; clicking a layer with the bone tool in hand adds or removes it by hand, which is the way to re-home one.

- Deforming blends each bone's *frame* and applies it whole, rather than blending the places each bone would put a point — which is what pinches a joint. Handles are offsets from their anchors here, so they take the turn without the move, and a bent limb keeps its curvature instead of kinking at every anchor.

- Selection boxes and hit testing read the posed geometry rather than the stored rest pose. Measuring a rigged layer from what is on disk put its box out over empty paper and made a click miss the artwork it was plainly over.

- The drawing is never written to. Stored geometry stays the rest pose and the pose is applied at draw time, in the one place that paints a frame — so the canvas, the ghosts either side of it, the strip's thumbnails and the raster exports all agree, and undoing a pose is undoing a rig edit rather than hoping the artwork went back.

- Its own creations folder, and its own bundle identifier so it cannot inherit Flip's. This build shares the document format and the Library can trash and move files; pointing a new engine at drawings that already exist is one bug away from losing them.

---

## 11 September — no version

*Groups learned to nest*

Real work, but nothing a user would call a feature — so it is here and
not in the app's own list.

- A group can hold a group. Grouping now happens in whatever stack the selection is already in, so a run of shapes inside a group becomes a group inside that group, to any depth — where before ⌘G only ever saw the frame's own top level and did nothing at all to a selection buried one level down.

- Ungrouping matches it: a group released inside a group comes apart into the group that held it, its children landing at its own index. Nothing on the canvas moves, which is the whole promise of a plain group — it is a name and a place in the stack, so taking it away should change the outline of the list and not a pixel of the drawing.

- Booleans were capped the same way, and Release was worse than capped: the button read the selection at any depth but the operation only searched the top level, so releasing a boolean that sat inside a group was an enabled button that did nothing. Both now work wherever the layer is.

- A selection straddling a group's edge is still refused. It names two stacks and no way to choose which one the group belongs in — the same objection reordering already makes to stepping such a selection along.

- Grouping inside a boolean is refused too. A boolean's children are its *inputs*, not a free stack, and a plain group has no region of its own; one standing where an input should be would drop silently out of the operation and quietly change the result.

---

## 15 September — no version

*Cursors and feedback for the bone tool*

Real work, but nothing a user would call a feature — so it is here and
not in the app's own list.

- The bone tool has two pointers of its own, one per mode: the four-way pointer while placing, with its hot spot dead centre where the bone's origin will land, and the pointing hand while posing, whose hot spot is the fingertip — the precise end you want when the thing to grab is a handle five pixels across. One tool doing two jobs needs the pointer to say which, since nothing else on the canvas does.

- The pointer now changes on the key press rather than on the next mouse move. Invalidating the cursor rect only schedules a rebuild, and AppKit applies it at the next cursor update — so pressing A with the hand still gave you the old pointer until you twitched the mouse.

- The first bone of a frame is visible while it is being drawn. The whole rig overlay — the drag preview included — was drawn only once an armature existed, and the first bone is placed when it does not: so the first drag in a frame showed nothing at all until the mouse came up, and every drag after it was live. A tool that answers the second use and not the first reads as broken rather than as empty.

- The bone being dragged carries a tip handle as well as its origin, in the same amber a tip being posed wears. It was a dashed line with one dot, which read as a line rather than as a bone about to exist.

- The cursor pipeline understands two things Figma writes that it did not. A stroke aligned to the outside is exported as a masked second copy of the path; laid down in that order it painted white over the glyph's own edges, so it is now drawn underneath, where the fill covers its inner half exactly as the mask cut it away. And a `<circle>` — which is how the dot marking a hot spot is written — is spelled out as four cubics instead of being silently dropped.

---

## 15 September — no version

*⌥-drag to duplicate*

Real work, but nothing a user would call a feature — so it is here and
not in the app's own list.

- ⌥-drag with the cursor leaves a copy behind: the original stays where it was and the copy comes away under the hand. It is the gesture every vector editor has, and without it duplicating something meant copy, paste, and then drag it off the thing it landed on.

- The copy is made in place and the drag provides the offset, so ⌥-clicking without moving changes nothing. It lands directly in front of what it came from, in that layer's own stack — a copy made inside a group stays in the group, beside the original.

- Both halves are one undo. An ⌥-drag is one action to the hand that did it, and needing two presses of ⌘Z to get back would be counting the implementation out loud.

- ⌥ no longer pans while the cursor is in hand — it cannot both pan and duplicate, and the pointer is a promise about what the next press does. ⌃ pans with every tool, and the hand tool is still there; ⌥ still pans with the brush and the shapes, which have no use of their own for it. The pen already worked this way.

- A duplicate gets a new identity all the way down, which is the half that was missing. Copying only ever renamed a boolean's children, so a copied *group* handed back children still carrying the originals' ids — and two layers in one frame answering to the same id is not cosmetic: every lookup finds whichever comes first, so a move, a colour or a delete aimed at one hits the other. Paste had the same hole and is fixed with it.

- It also gets a new track, where a track means "this same element, once per frame". Inheriting the original's would make ⌥-clicking either copy select both of them, in every frame, ever after.

- Selecting a group and something inside it and duplicating gives one copy rather than two — the outermost of what is selected is copied, since the copy of the group already contains the child.

---

## 15 September — no version

*A pointer for ⌥-drag*

Real work, but nothing a user would call a feature — so it is here and
not in the app's own list.

- Holding ⌥ over something the cursor could take hold of shows the doubled arrow, so the duplicate is visible before it is made rather than discovered afterwards.

- It answers the key rather than the next mouse move. Pressing ⌥ with the hand still is the whole case worth having — you are already over the thing you meant to copy.

- Over bare paper it stays an ordinary arrow, because an ⌥-drag there is a marquee and a copy-shaped pointer would be promising a duplicate of nothing. Over a transform grip it stays the resize arrow, for the same reason: ⌥ on a corner still resizes.

- The pointer was being placed from the event that asked for it, and a key press carries no mouse position — so the pen's pointer had the same hole, and only ever looked right because a mouse move followed closely enough to cover it. Both now read where the mouse actually is and which modifiers are actually down.

---

## v0.0.2.2 — 15 September

**Bones** · *Rigging a grouped drawing*

- The bone tool works on grouped artwork. Claiming, click-to-bind, the hover highlight and the ownership outline all walked the top of the layer stack and asked each layer for its shape — and a group has none, so a grouped character was invisible to every one of them. A bone drawn into it claimed nothing and the drawing simply never moved.

- A rig owns shapes, never the group holding them, and reaches through any depth of grouping to find them. Grouping is organisation — thirty shapes read as four things — and it must not change what a bone lies inside, or tidying the layer list would silently re-rig the character.

- Owning the group itself would be worse than merely inconsistent. A group's area is the union of its children's, so a bone in a forearm lies inside the whole-body group as surely as it lies inside the forearm — one bone would take the entire character, which is the runaway that enclosure was chosen over proximity to avoid.

- A boolean goes the same way, its children being its inputs: the shapes deform and the operation re-evaluates from them, which is what makes a rigged boolean behave rather than snap.

---

## 15 September — no version

*The layers panel, quieter*

Real work, but nothing a user would call a feature — so it is here and
not in the app's own list.

- A layer an armature drives says so, with a small bone before the visibility toggle. A group says it for whatever is inside it — armatures own shapes, never the group holding them, so a grouped character had nothing anywhere telling you it was rigged until you opened every group in the list to find out.

- The eye only appears while the pointer is on the row. A column of them down a long list is a row of controls nobody asked for, and each one competes with the drawing's own swatch for the eye.

- A layer that is switched *off* keeps its crossed eye whatever the pointer is doing. That is the layer saying something about itself rather than the panel offering a control, and a hidden layer with nothing on its row would be a layer you could only find by hunting.

- The eye is faded rather than removed, so its slot is always there and the bone beside it cannot shift sideways when the pointer arrives.

- Deleting a rig now clears it at every depth. It only ever cleared the top of the stack, so a grouped shape was left pointing at an armature that no longer existed — harmless to draw, since posing checks the index, but the layer still called itself rigged and the next armature would have silently inherited it.

---

## v0.0.2.2 — 15 September

**Bones** · *A group is one thing*

- A group rigs as a single object. Binding it binds everything inside it, and the armature carries down to each shape at draw time — so a grouped character is rigged by pointing at the character, not by getting a bone far enough inside one particular shape of it.

- Select something and the bone takes that, whole. A selection is an answer already given, so nothing is measured and nothing is unpredictable: the same gesture over the same drawing binds the same layers every time. With nothing selected, enclosure still decides, but each layer is now weighed as one object — a group by the shapes inside it, taken whole rather than picked apart.

- The gap between a group's shapes is still outside it, since the area is the real subpaths rather than a bounding box. A bone drawn through the hole in a doughnut binds nothing, which is the same answer it gives for a single shape.

- Clicking and hovering follow: a click binds or releases a grouped drawing whole, and the highlight outlines every shape in it, because that is what the click will take.

- Binding the whole of a character was previously refused on the grounds that one bone would then drag all of it. That was wrong. A layer follows the whole armature, weighted per point — the arm bones move the arm and the torso bone holds the torso — so the bone that claims a layer has no special hold over it. The fear was of proximity claiming *unrelated* drawings, which explicit ownership already prevents.

- A shape inside a bound group can still be bound to a different armature of its own, which overrides what it inherits.

---

## v0.0.3.1 — 15 September

**Dynamic strokes** · *A line with a hand in it*

- Lines can wander off the path they were drawn on. Three dials under Dynamic: how far it strays, how tightly, and how much of that straying is made afresh on every frame.

- The third dial is the one that matters in an animator. At zero, every frame wanders identically and a held drawing is perfectly still — surface texture and nothing more. Turned up, each frame is its own, which is the boil of a line redrawn by hand. In between the two are mixed, so a rigged character can breathe without shimmering apart. A pose held over forty frames is the deadest thing in the app, and this is what puts a hand back into it.

- Never baked into the drawing. The anchors on disk stay the clean line that was drawn and the wander is added when the frame is painted — same arrangement as the rig, for the same reasons: the dials stay live long after the stroke is finished, undo takes back a setting rather than a redrawn line, and nothing can drift out of step.

- Clicks and selection boxes read the still line. A box that shivered with the texture inside it would be a box you could not aim at, and the wander belongs to the painting rather than to the shape.

- Points are pushed sideways only, never along the line. A stroke that also stretched and bunched along its own length would read as the drawing melting rather than as the hand shaking.

- A closed path comes back to where it started: the noise is made to repeat a whole number of times around it. Without that every circle wore a nick where its end met its beginning.

- A group hands its wander down to everything inside it, so a whole character can be given one hand rather than one stroke at a time.

- The fine end of Frequency stops where it does on purpose. Every crest costs anchors and anchors are what the rasteriser pays for — finer than this and a stroke came out with twelve times the geometry it went in with, and a frame took longer to paint than it took to draw.

---

## v0.0.3.1 — 15 September

**Dynamic strokes** · *Rough ground*

- The wander is rough now rather than wavy. It was one smooth wave, which however it was dressed read as a ripple; it is three laid over each other, each twice as fine and about half as tall as the one under it. A big shape with smaller shapes on it is what makes ground look like ground.

- Turning Wiggle up also shortens the curve's handles, so a hard setting comes out as facets and broken ground rather than as rounded swells. Re-fitting the wandered points with full tangents was quietly smoothing off every crest the noise had just made — the dial was working and the fit was undoing it.

- The line is rough while you are drawing it, not once you let go. The texture is half of what the line *is*, and a stroke that went down smooth and roughened a moment later is a stroke you cannot aim. The stroke takes its identity at the moment the pen goes down, so the preview and the finished layer are the same line and it does not change shape at the release.

- The dials moved under Stroke, beside the width. They are the same question about the same mark — how thick the line is, then how steadily it is drawn — and a group of their own put the hand holding the pen in a different part of the panel from the pen.

- A straight segment is written to the path as a line rather than as a cubic with no bend in it. That one change made a frame of rough lines four times faster to paint, and plain drawings about three times faster as well: every shape drawn with corners had been asking the rasteriser to flatten curves that were never curved.

---

## v0.0.3.1 — 15 September

**Dynamic strokes** · *Smoothen*

- Smoothen is a dial of its own, which is what it should have been. It was read off the Wiggle amount — a shortcut taken to make a hard setting come out rough — and that welded two independent questions together: a wide gentle swell and a tight jagged scratch were both unreachable. The three now name what they name: how many bumps, how big, how jagged.

- It works on the waves rather than on the corners. Jaggedness *is* the fine waves, so rounding the corners off afterwards only files down what they made and leaves the line busy; smoothing now quietens the finer waves, and at the top of the dial the line becomes a single clean swell. The corner-rounding moves with it, since they are one question asked of two parts of the same pipe.

- Wiggle now means the same thing at both ends of Smoothen. The waves were normalised by their summed height, and independent waves mostly cancel — so three of them reached barely half as far as one, and the amplitude quietly depended on how rough the line was. Normalising by power fixes it, and has the side effect that the dial now delivers most of what it promises rather than a third of it.

- The dials sit in the order the questions come in — Frequency, Wiggle, Smoothen — with Boil last, being the only one that asks about the frames rather than about the line.

- A drawing saved before Smoothen existed still opens, with it at nothing, which is how those lines were painted.

---

## 15 September — no version

*The build history, restructured*

The app's own list had grown into a developer's diary: twenty builds, one per
change, and sixteen lines to say that strokes can wobble. Rebuilt at Nidhin's
asking, in three passes — terser lines, then user-facing lines, then features
only. It now holds three builds and twenty-seven lines; this file holds the
other hundred-odd.

The rule it settled on: a line ships if the app can now do something it could
not before. A cursor, a hotkey, a rearrangement or a fix is not that, however
much work it was.

---

## v0.0.4.1 — 15 September

**Pencil** · *A nib that leaves grain*

- A pencil nib under Stroke, in four grades. An addition to the stroke rather than a replacement: the colour, the width, the path and the fill are all still the layer's own, and the nib only changes how the outline is laid down.
- The model is graphite against paper. `ink` is how much the stroke wants at a point — full along the centreline, falling away across the width. `tooth` is how high the sheet stands there. Where the ink beats the tooth there is graphite and where it does not there is bare paper, and that one comparison produces a dense core dissolving into separate specks at the fringe without a speck ever being placed by hand.
- Built first as a raster mask, which was the wrong answer and was rebuilt at Nidhin's suggestion as geometry: the outline eaten into along both edges, with holes punched through where the paper stood proud. Vector settles three things at once — it survives the SVG export, it stays crisp at any zoom where a mask is only as good as the resolution it was built at, and it costs what a path costs.
- The paper is held in *document* coordinates and shares one seed across the whole drawing. Two lines that cross have to meet the same sheet or they read as two pictures laid over each other, and the grain must not slide about when the artboard is panned.
- `Grain.swift`'s bitmap was no use for it: photographic speckle authored as a tint for dark panels, at the size of a panel rather than of a pencil mark. The tooth is generated from the noise already written for the wander, which tiles exactly and makes the grain size a number rather than an asset.
- Three false starts on the cost, each measured rather than guessed. Blamed the buffer copy and rewrote it to draw straight into the image's memory: no change. Blamed the per-pixel pass and skipped eight bytes at a time: no change, because the benchmark that said the walk was free had been optimised away. The vector rebuild then went *slower* — 269 ms for sixty strokes — and that one was the fill: CoreGraphics scan-converting thousands of tiny subpaths. Budgeting the holes, so the grid opens up instead of multiplying, brought it to 39 ms against 13 ms for a plain stroke.
- The first vector attempt read as woven cloth: holes on a regular lattice as identical axis-aligned squares. Fixed by jittering each hole most of a cell in both directions from two unrelated noise fields, varying the size by a factor of three, and making the speck a four-sided shape with every corner pushed about. Sameness gives it away as much as regularity does.
- The mark is cached, keyed on the centreline — forty-odd points — rather than on the mark, which is thousands. A boiling stroke changes every frame and misses every time; that is correct, and it is the only case that does.
- Known cost: an SVG carries about 48 KB per pencil stroke, since every speck is a subpath. A long animation of them will make a large file.

---

## 15 September — no version

*Picking a nib by looking at it*

Real work, but nothing a user would call a feature — a control changed shape, so
it is here and not in the app's own list.

- The five nibs were a row of segments, and a 208pt panel had already truncated "Medium" to "Medi…". The next brush added would have had nowhere to go at all.
- The deeper reason is that the names are not the choice. "Soft" and "Light" tell you nothing you could act on; a stroke of each tells you everything. The menu rows now carry a sample above the name.
- The samples are drawn with the same `Pencil` the canvas uses, not with artwork of their own. A picker showing a *drawing* of a brush can be wrong about it; one showing the brush's own mark cannot, and it follows any change to the nib for free.
- `MenuEntry` gained an optional preview and the menu row a second line, so this is available to any future list where the choice is a look rather than a word.
- A wave, not a rule: a brush's character is in how it turns, and a straight line shows none of it.
- The shut control shows the mark rather than the word. It answers the only question anyone asks of it — what am I about to draw with — without making you translate a name back into a picture you have already been shown. The name stays in the menu, which is where it earns its keep: it is how you tell someone else which one you meant.

---

## 15 September — no version

*Marks instead of words on the dynamic rows*

Real work, but nothing a user would call a feature — labels became icons, so it
is here and not in the app's own list.

- Frequency, Wiggle, Smoothen and Boil lost their labels and took icons, with the track beside each rather than under it. Four words stacked down a panel are four lines of reading before you reach the first control; four marks are a row of things you recognise.
- The name comes back on a hover held past **two seconds**. Longer than the system's own, deliberately: these sit in a panel whose controls are dragged past constantly, and a tip at half a second would be a panel that flickers while you work. At two it only ever answers a question you are actually asking. Drawn rather than handed to `.help()`, which brings its own chrome and corner into a panel that draws both itself.
- Fixed the icon generator instead of hand-splicing four more icons into it. `home` and the five `feature*` icons had been pasted straight into `Icons.swift` with no artwork on disk, so re-running the script dropped them and broke the build — the file had carried a warning about it since the bone icon went in the same way. Their path data was written back out as real `.svg` files, the script's list brought back in step, and the whole set regenerated: 57 icons to 61, nothing lost and nothing changed. The warning is gone with it.
- Two wrong turns on the tip, both found by probing rather than reasoning. It did not appear with a two-second delay, nor with none, nor even rendered unconditionally — so the state was never the problem. Colouring the icon by its own hover state proved `onHover` was firing on the right icon all along. The overlay was drawing and then being painted over: the slider track is a *later sibling* in the row, and an overlay outranks its own content but not the views drawn after it. A `zIndex` on the icon settled it.
- Several runs before that were lost to the window having been resized and the app sitting on the home screen — the coordinates were measured against a stale screenshot, which is worth remembering the next time a hover "does not work".

---

## 15 September — no version

*The nib control, and a lighter title face*

Real work, but a control's proportions and a change of weight — so it is here
and not in the app's own list.

- The nib sample now runs the full width of the control, stopping at the chevron with its own padding, and the box is taller to give the stroke room above and below it.
- It is *drawn* to that width rather than scaled into it. The sample is a stroke, and a stroke stretched to fill smears its grain — which would make the picker lie about the very thing it exists to show. `MenuRow` now asks for the preview at a width instead of being handed one ready-made, and `NibPreview` caches per width, of which there are only ever one or two.
- Montagu Slab moved from Regular to Light. One constant: the loader matches on the PostScript name and looks the file up under the same string, so the file is named `MontaguSlab48pt-Light.ttf` to match `MontaguSlab48pt-Light`. The leading is asked of the face rather than hard-coded, so it followed the change on its own — which is what that code was written for.
- The Regular weight is gone from this build. Not in the original either, which uses a different face entirely — it is on the Desktop beside the Light, and is an open licence besides.

---

## 15 September — no version

*Holding a line straight*

A modifier, by the same rule that kept the duplicate cursor out of the app's own
list — so it is here and not there.

- ⇧ with the pen puts the next point on one of eight rays out of the last one, at 45° apart — which is how a horizontal, a vertical or a true diagonal gets drawn without aiming. The rubber band shows the point ⇧ would place, not the one the pointer is over, so the line drawn ahead of the press cannot promise something the press will not do.
- ⇧ with the pointer pins a move to one axis, across or up, the way Figma does it. The axis is decided from the *start* of the drag rather than the last position, and re-decided on every move — swing past the diagonal and it changes, where an axis latched once could only be undone by letting go.
- The point the drag remembers is the constrained one, not the pointer's own. That is what lets ⇧ go mid-drag and hand the selection straight back to the pointer in one step: it has been lagging by exactly the component that was being suppressed, so the difference is already the right correction.
- The same ⇧ reaches the pen's handles and its points: a curve can leave a point square to the page, and an anchor can be dragged out along the direction the line was drawn in. ⇧ on the shape tools still means a square or a circle, which it always did.
- Snapped **sideways** onto the ray rather than kept at its full distance from the origin. A hand 20° off the diagonal has drawn a line of some length; projecting keeps the point beside the hand, where holding the radius would run it out ahead of the pointer and make the lock feel like it was pulling.
- `mouseDragged` was split so that `flagsChanged` can run it too. A modifier pressed in the middle of a drag has to take hold where the hand already is — ⇧ that only straightened the line after a further nudge of the mouse is the same complaint as a bone handle that appears only once you let go. `flagsChanged` carries no position of its own, so the pointer is re-read rather than remembered.
- ⇧ on something already selected now waits for the release to decide what it meant. It is two intentions that are identical at the moment of the press: a click, which drops that layer from the selection, or the start of a drag held straight. Dropping it at once left ⇧-drag dragging everything *except* the thing under the pointer — so the drop happens on release, and only if the hand never moved. Figma draws the same distinction.
- Checked by measurement, not by eye. A pen path drawn with ⇧ came back out of the saved file at 0.000°, −90.000°, 45.000° and 90.000°; a ⇧-locked move of a 45-anchor blob came back at dx 200.456, dy 0.000. The mid-drag case was the one worth watching rather than measuring: the shape snapped back onto its row the instant ⇧ went down, with the mouse stationary.

---

## 10 October — no version

*re-Flip becomes Flip*

A name and an icon, not a feature, so it is here and not in the app's own list.

- The original Flip was archived to `Claude Code/Archive/Flip v1`, and this project took its place: the folder, the GitHub repository (`inbox-nidhinm/Flip`), the window title, the home screen, the first onboarding page and the README all say Flip now.
- The icon went back to the original green one. The dark version only ever meant "this is the development build", and there is no longer a second build to tell it apart from.
- The app took the original's identifier, `ai.flip.app`, so it inherits Flip's settings rather than starting fresh as a stranger.
- One creations folder instead of two. The default is `~/Documents/Flip Creations` again, and the three drawings from `re-Flip Creations` were moved in beside the originals. The comment that kept the two apart, written so that a new engine could not reach old drawings, was rewritten: with one app left, there is nothing to keep apart.
- Flip's code moved from the Unlicense to the MIT License, as Twine and Pine did the same day. The README's License section says so; Colorful and Montagu Slab keep their own terms.
