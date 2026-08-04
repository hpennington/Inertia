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
between your live app and the **shape canvas**. Three things change with it:

| | Over the app | Over the canvas |
| --- | --- | --- |
| Viewport | Your app, live | Every drawing the app is currently showing, on its own |
| Hierarchy | Multi-select, no visibility controls | One row at a time, with a show/hide button per row |
| Right panel | The animations outline | The [shape properties](#shape-properties) of the picked shape |
| Transform column, recording off | Moves where a track starts from | Places the picked shape in its parent |
| Transform column, recording on | Writes a keyframe at the playhead | Writes a keyframe at the playhead |

The canvas is the same Metal renderer the runtime draws with, on a stage the size of the
device screen, so a shape drawn small reads as small rather than blown up to fill the
panel. Each drawing is centred, because the middle of a view is what its shapes are
measured from — two views carrying drawings therefore overlap, which is what the hierarchy's
eye buttons are for.

**It plays.** Everything on the canvas is drawn at the editor's playhead: press
<kbd>Space</kbd> or scrub, and the canvas shows the frame the app under test is showing,
with none of the app's own views over it.

What is *on* the canvas is not what is selected. The whole of the app's drawing is shown
whatever you pick; selection only says which shape the properties panel describes, which
one the tools move, and which one gets the green border.

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

The stroke is drawn **inside** the outline, so adding one never moves the shape or grows
the box it occupies. A stroke thicker than half the shape's smaller side is held there and
draws as a solid shape.

Editing properties is not recording. A description is what the shape *is* before anything
plays, so it lands wherever the playhead is parked and whether or not recording is armed,
and it leaves the shape's own track alone.

## Placing a shape in its parent

A shape's corners are drawn about the origin of whatever holds it, so every inserted vector
starts dead centre. To move it, use the **transform column** to the right of the viewport
with drawing mode **on** and recording **off** — the column is titled *Offset* there.

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

!!! warning "Stacking is iOS-only today"

    The SwiftUI runtime honours `zIndex` and `position`. Compose and React ignore both:
    they draw every shape behind the view's content, in the order it was authored. The
    editor's canvas follows SwiftUI, so a drawing that relies on either will look right in
    the editor and stack differently on Android and the web. See [Choosing a
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

1. **Select the shape** in the hierarchy — over the app or over the canvas, either works.
2. **Position the playhead.**
3. **Arm recording.**
4. **Drag the shape** in the app viewport, or move the transform column's sliders.

A shape that was never animated is given a track here, starting from where it was drawn.
Its keypoints appear on the timeline as a row indented under the view it is drawn behind,
marked with a scribble icon — a shape moves *with* that view as well as on its own track,
and the indent is what says so. The same rows appear in the animations outline, grouped
under the animation that carries them.

Nested shapes are the exception: they have nothing a track could move, so the transform
column stays on placement for them however recording is set.

## Hiding and deleting

**Hide** — the eye button on every hierarchy row while drawing mode is on. Hiding is a way
of getting at what is drawn underneath while you work: it is the editor's own state, is
never written to the project, and the app under test goes on drawing everything.

**Delete** — right-click a shape row in either hierarchy and choose **Delete _shape_**. It
is taken at its word with no confirmation, the same as deleting a keypoint, and it takes
everything nested inside the shape with it.

## What gets written

Shapes live on the animation schema of the view they are drawn against, under a `shapes`
key, and are saved with everything else — autosave every 10 seconds, or when you close the
project. See [Animation files](../guides/animation-file.md#shape-object) for the format.

Every insert, property change, offset and delete is pushed to the running app immediately.
If a change does not show up in your app, the app has stopped listening — see
[Editor mode](../getting-started/editor-mode.md).
