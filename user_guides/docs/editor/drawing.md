# Drawing vectors

Not everything you want to animate is a view you already built. A shape drawn in the
editor — a rectangle behind a card, a circle badge over an avatar, a triangle that slides
in from off-screen — is authored against one of your tagged views and travels in the same
`animation.inertia` file as its keyframes.

Shapes are drawn by the **runtime**, not by the editor. What you draw here is what your
app renders: all three runtimes read the same shape model and rasterize it themselves, in
editor mode and in release alike. There is no exported image and nothing to bundle
alongside the animation file.

## What a shape is measured in

A shape belongs to a tagged view, and is sized in multiples of that view's **shorter
side** — one length across and down alike, so a circle of `width: 1, height: 1` is round
on a view of any proportion.

| Size | What it draws |
| --- | --- |
| `0.5` | Half the view's shorter side |
| `1` | The full shorter side |
| `3` | Three times it — well outside the view |

Nothing clips a shape to its view. Coordinates outside the view go on being drawn, because
the canvas the shape lands on is the *container's*, so a backdrop three times the size of
the card it sits behind is authored simply by saying `3`.

The origin is the **center of the view**, which is where a described vector's outline is
drawn about. To put a shape anywhere else, give it an [offset](#placing-a-shape-in-its-parent).

!!! tip "1 is the whole thing"

    Sizes, stroke widths and offsets are all in these units. A stroke of `0.01` is a hairline
    against a half-view shape; a stroke of `0.5` on that same shape fills it in.

## Inserting a shape

The lower half of the tool palette down the left of the viewport is the **vector palette**:
rectangle, square, circle, oval, triangle.

1. **Select exactly one row** in the hierarchy. The vector buttons are dim until you do —
   a shape is drawn into one view, so with nothing or several things picked there is no
   answer to where it goes.
2. **Click a vector.** A modal opens describing the shape before anything lands in the
   project.
3. **Fill it in** and click **Insert**.

| Field | Starts at | Meaning |
| --- | --- | --- |
| Fill | Opaque indigo | The colour flooding the outline. Take the opacity to zero for a shape that is only its outline. |
| Stroke | None | The colour of the outline itself. Picking one brings a stroke width of `0.01` along with it. |
| Width / Height | `0.5` | In multiples of the view's shorter side. |
| Z-Index | One above the shapes already there | Order among the shapes beside it — higher draws in front. |
| Position | Behind | Which side of the view's own content the shape is drawn on: **Behind** or **In Front**. |
| Own Canvas | Off | Whether the shape gets a rendering layer to itself. See [Stacking](#stacking). |

Every shape is inserted as backdrop — drawn from the moment the view it backs is on screen,
whether or not anything has been triggered. A shape that should appear *with* the animation
instead is that said in the properties panel afterwards; see [When a shape
appears](#when-a-shape-appears).

**Insert** stays disabled for a shape that would be invisible: one with neither a fill nor
a stroke, or one measuring nothing in a direction.

Where the shape lands depends on what was selected:

- **A view row** — the shape joins that view's own canvas.
- **A shape row** — the new shape is drawn *inside* that shape. See [Nesting](#nesting-shapes).

A view that has never been animated gets an animation schema here — one that does nothing,
carrying a drawing. That is what the shape is stored on, which is why the shape shows up in
the same file as the keyframes.

## Drawing mode

The toggle at the **bottom of the tool palette** (the scribble icon) swaps the viewport
between your live app and the **shape canvas**. What changes with it:

| | Over the app | Over the canvas |
| --- | --- | --- |
| Viewport | Your app, live | Every drawing the app is currently showing, on its own |
| Hierarchy | Multi-select, focus toggle, no visibility controls | One row at a time, with a show/hide button per row |
| Right panel | The animations outline | The [shape properties](#shape-properties) of the picked shape |
| Timeline | As you left it | [Animations hidden](timeline.md#hiding-the-animations) on the way in, restored on the way out |
| Clock | The runtime's own | The editor's |
| Drag or transform column, recording off | Moves where a track starts from | Places the picked shape in its parent |
| Drag or transform column, recording on | Writes a keyframe at the playhead | Writes a keyframe at the playhead |

The canvas is the same Metal renderer the runtime draws with, on a stage the size of the
device screen, so a shape drawn small reads as small rather than blown up to fill the
panel. Each drawing is centred, because the middle of a view is what its shapes are
measured from — two views carrying drawings therefore overlap, which is what the hierarchy's
eye buttons are for. The drawing holding the picked shape comes to the front, so nothing
drawn over it covers its border, its handles, or the presses meant for them.

**It is edited.** The picked shape grows the same handles the app under test grows for the
active tool, on the same geometry, and a drag on them is a drag on the shape — moved,
turned, scaled and faded here as well as over there. What the drag lands on is the toolset's
to say, which is the fork the table above draws.

**It plays**, off the editor's own clock rather than the app's. The runtime is parked while
the canvas is up: it is behind the canvas and nobody is watching it, and a run left going
there would walk away from the frame the canvas is drawing. Playback carries across the swap
in both directions, and closing the canvas hands the app the playhead you can see before
telling it to play on.

Opening the canvas also [hides the animations](timeline.md#hiding-the-animations), so every
drawing sits where it was drawn while you place it. Turn the timeline's toggle back off to
watch a run on the canvas.

What is *on* the canvas is not what is selected. The whole of the app's drawing is shown
whatever you pick; selection only says which shape the properties panel describes, which
one the tools reach, and which one gets the green border and the handles.

## Picking a shape

Three ways in, all writing the same selection — pick a shape one way and its row lights up
the other:

- **Its row in the hierarchy**, over the app or over the canvas.
- **Clicking it in the app viewport**, with focus on. A shape is backdrop in a shipped
  build and takes no touches there at all; this is editor mode only.
- **Clicking it on the shape canvas.**

A click has to land on the *artwork*, not on the box around it. A press in the corner beside
a circle, or in the margin beside a triangle's slope, falls through to whatever is behind
instead of being swallowed by a backdrop you cannot see there — and an unfilled shape is its
outline and nothing more, so a press through the middle of a ring misses it too. Nested
shapes are picked this way as well, even though they have no box of their own: the shape a
press lands on is worked out by testing the point against the drawing, innermost and
front-most first.

Clicking a picked shape again puts it back down.

!!! note "An empty canvas"

    Three different messages, because the fix differs: **Waiting for the app to connect**,
    **Every drawing is hidden** (turn an eye back on), and **Nothing is drawn on the views
    on screen** — the project may hold drawings for views that are not currently laid out,
    and a shape can only be drawn once the runtime has reported the size of the view it is
    measured against.

## Shape properties

While drawing mode is on, the right-hand panel describes the picked shape. Every field
writes into the project as you move it and is pushed to the running app, so the app and
the canvas both follow the picker.

| Field | Meaning |
| --- | --- |
| Shape | Which vector it is drawn as. Swapping it keeps the size, paint, placement, track and anything nested inside. |
| Fill | The colour flooding the outline. Transparent means no fill. |
| Stroke | The colour of the outline. Transparent means no outline. |
| Stroke Width | How thick the outline is, in the same units as the size. Dim until a stroke colour is picked. |
| Width / Height | Multiples of the view's shorter side — or of the *parent shape's*, for a nested shape. |
| Z-Index | Order among its siblings. Higher draws in front. |
| Position | Behind or in front of the view's content. Dim for a nested shape. |
| Own Canvas | Whether the shape is a rendering layer of its own. Dim for a nested shape. |
| Show Before | Whether the shape is drawn while the animation waits to play, or only once it is playing. Dim for a nested shape. See [When a shape appears](#when-a-shape-appears). |

The stroke is drawn **inside** the outline, so adding one never moves the shape or grows
the box it occupies. A stroke thicker than half the shape's smaller side is held there and
draws as a solid shape.

Editing properties is not recording. A description is what the shape *is* before anything
plays, so it lands wherever the playhead is parked and whether or not recording is armed,
and it leaves the shape's own track alone.

## When a shape appears

A shape is backdrop by default: drawn from the moment the view it backs is on screen,
whether or not anything has been triggered. That is what a halo behind a card wants, and
exactly what a shape that is *part* of the animation — the puff a button gives off when it
is pressed — does not. Left as backdrop, that puff sits there in full view for however long
the app waits to trigger the track.

Turning **Show Before** off says so outright: nothing is drawn until the run is on screen,
and the shape appears with it. It replaces the workaround of authoring an opacity of zero
into the first keyframe of a track the shape did not otherwise need.

- The shape being worked on stays drawn in the editor whatever this says, since a shape that
  vanished until the timeline was rolling could not be authored at all. The green border is
  the sign that it is being shown for the editor's sake.
- A nested shape has no say. It is drawn into its parent's canvas, so it comes and goes with
  the parent — which is why the panel dims the toggle there, alongside Position and Own
  Canvas.
- All three runtimes read it, and a file written before it existed reads back as backdrop.

## Placing a shape in its parent

A shape's corners are drawn about the origin of whatever holds it, so every inserted vector
starts dead centre. To move it, drag it with drawing mode **on** and recording **off** —
either by its handles on the canvas, or with the **transform column** to the right of the
viewport, which is titled *Offset* there.

It takes the same five properties a keyframe does — translate, rotate, rotate center, scale
and opacity — and the translation is in the same units as the size: multiples of the shorter
side of whatever holds the shape. An offset of `0.5` across moves it by half the view's
shorter side, which is the same distance `width: 0.5` makes it wide.

This is placement, not animation:

- It is the same at every point on the timeline. Nothing about it appears on the timeline.
- It is baked into the geometry handed to the renderer, which is why it is the **only** way
  to move a nested shape — a child has no canvas of its own to transform.
- A track the shape carries plays *on top of* it, moving the shape from where this put it.

## Nesting shapes

Select a shape row and insert another vector: the new one is drawn **inside** it and is
listed under it in the hierarchy.

A nested shape is part of its parent's drawing rather than a drawing of its own:

- Its size is in multiples of the **parent shape's** shorter side, not the view's.
- It is drawn on the parent's canvas, so its **Position** and **Own Canvas** say nothing and
  the panel dims them.
- Every transform that moves the parent moves it too — a face drawn inside a head turns when
  the head does.
- It cannot carry a track. Move it with an offset instead.

Deleting a shape deletes everything drawn inside it.

## Stacking

Three separate controls, applied in this order:

**Position** comes first. `Behind` hangs the canvas off the view as a background, `In Front`
as an overlay. Nothing drawn behind a view can be lifted in front of it by counting higher.

**Z-Index** orders the shapes drawn on one side of the content, among their siblings only.
Higher draws in front; ties keep the order they were authored in. A z-index on a child
cannot lift it out from behind a shape its parent sits behind.

!!! note "Stacking reads the same on all three runtimes"

    SwiftUI, Compose and React all honour `zIndex` and `position`, and the editor's canvas
    stacks the same way, so a drawing that relies on either looks the same in the editor as
    it does on iOS, Android and the web. A stack that comes out in file order on one of
    them is an app built against an older runtime — see [Choosing a
    runtime](../getting-started/runtimes.md#drawn-vectors).

**Own Canvas** is a rendering decision rather than an ordering one. Shapes that sit next to
each other normally share one canvas, which is what keeps a drawing of forty static shapes
to a single rendering layer. A shape earns its own canvas when it carries a track, or when
it is the one selected — and this toggle asks for one up front. Reach for it when a shape
has to stay a layer of its own so something can be stacked between it and its neighbours.

## Animating a shape

A top-level shape can carry a track of its own, which is what makes it a drawing rather
than a backdrop: the corners say what is drawn, the track says how it moves, and the view it
was authored against carries both.

1. **[Pick the shape](#picking-a-shape)** — a hierarchy row, a click in the viewport, or a
   click on the canvas.
2. **Position the playhead.**
3. **Arm recording.** On the canvas, also turn [Hide
   Animations](timeline.md#hiding-the-animations) back off, or the take will be recorded
   against drawings the canvas is holding still.
4. **Drag the shape** — in the app viewport or on the shape canvas — or move the transform
   column's sliders.

A shape that was never animated is given a track here, starting from where it was drawn.
Its keypoints appear on the timeline as a row indented under the view it is drawn behind,
marked with a scribble icon — a shape moves *with* that view as well as on its own track,
and the indent is what says so. The same rows appear in the animations outline, grouped
under the animation that carries them.

Nested shapes are the exception: they have nothing a track could move, so the tools and the
transform column stay on placement for them however recording is set.

## Hiding and deleting

**Hide** — the eye button on every hierarchy row while drawing mode is on. Hiding is a way
of getting at what is drawn underneath while you work: it is the editor's own state, is
never written to the project, and the app under test goes on drawing everything.

**Delete the shape** — right-click a shape row in either hierarchy and choose **Delete
_shape_**. It is taken at its word with no confirmation, the same as deleting a keypoint,
and it takes everything nested inside the shape with it.

**Delete its track** — right-click the drawing's row in the animations outline and choose
**Delete Shape Animation**. Only the track goes; the shape stays on the canvas, sitting
where its placement puts it, ready to record another. No confirmation here either.

Deleting the **animation** a drawing belongs to takes the drawing with it. A shape is stored
on the schema of the view it is drawn behind rather than beside the animations, so it has
nowhere left to be — the same bargain a nested shape makes with its parent. That one does
ask first.

## What gets written

Shapes live on the animation schema of the view they are drawn against, under a `shapes`
key, and are saved with everything else — autosave every 10 seconds, or when you close the
project. See [Animation files](../guides/animation-file.md#shape-object) for the format.

Every insert, property change, offset and delete is pushed to the running app immediately.
If a change does not show up in your app, the app has stopped listening — see
[Editor mode](../getting-started/editor-mode.md).
