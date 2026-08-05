# Timeline and keyframes

The timeline runs along the bottom of the editor. It has a transport (play/pause and
record), a loop duration field, a ruler, and one row per animated view with a keypoint
for each of its keyframes.

## The controls

| Control | What it does |
| --- | --- |
| :material-play: / :material-pause: | Plays or pauses the loop. <kbd>Space</kbd> does the same thing. |
| :material-record-circle: | Arms keyframe recording. Red means armed. |
| Loop duration | How many seconds one loop lasts. |
| **Hide Animations** | Sets the animations aside and switches the rest of the timeline off. See [Hiding the animations](#hiding-the-animations). |
| Playhead | Drag to scrub. The app under test holds the frame the playhead points at. |

<kbd>Space</kbd> works anywhere in the editor except while you are typing in a text
field, so you can play back without moving the mouse out of the viewport. It is
suppressed while the animations are hidden, for the same reason the play button is
switched off there.

## Recording a keyframe

1. **Select** the view in the simulator viewport.
2. **Position the playhead** at the time you want the pose to land.
3. **Arm recording** with the record button.
4. **Drag the view** in the viewport. When you release, a keyframe is written at the
   playhead with the position you dropped it at.

Repeat for each pose. The order you record in does not matter — a keyframe goes where the
playhead is, not after whatever you recorded last.

A [drawn vector](drawing.md) records the same way: select the shape rather than the view,
and its keypoints land on a track of its own, drawn as a row indented under the view it is
drawn on and marked with a scribble icon. The shape moves *with* that view as well as
on its own track. Vectors nested inside another shape are the exception — they are drawn
into their parent's geometry and have no track, so they are moved with an
[offset](drawing.md#placing-a-shape-in-its-parent) instead.

Recording on top of an existing keypoint replaces it rather than stacking a second
keyframe at the same time — and it keeps the keypoint's id, so the timeline row and any
modal opened on it stay pointing at the same thing. Two keypoints closer together than a
millisecond or so are treated as the same keypoint, because a zero-length keyframe cannot
be interpolated.

The [transform column](overview.md#transform-column) records too, and it waits for the
release: off the record a slider authors every value it passes through, so the node
follows the thumb, but with recording armed only the value you let go on is written. The
ones on the way there would be a keypoint each at the same time on the timeline.

!!! warning "Nothing records without recording armed"

    With recording off, dragging a selected view moves it in the viewport but writes
    nothing. That is deliberate — it lets you reposition and inspect without editing —
    but it is the most common reason a drag seems not to have taken.

## Scrubbing

Dragging the playhead while playback is stopped holds every animated view at the values
its track reaches at that time, so the simulator shows the frame the timeline is pointing
at. It is the fastest way to check a pose.

Scrubbing is disabled while the animation is playing. During playback the playhead is
reporting a clock's position back to you, and dragging it would fight that clock. Which
clock depends on what is in the viewport: the runtime's while your app is there, since
that is the thing actually animating, and the editor's own while the [shape
canvas](drawing.md#drawing-mode) stands in for it. Playback carries across the swap
either way.

## Loop duration

The loop length is a property of the timeline, not of any one animation. Every track is
padded out to the loop: a view that stops moving after half a second holds its final pose
until the loop comes around again. That is what keeps tracks of different lengths
restarting together.

- Default: **3 seconds**
- Range: **0.1 to 60 seconds**
- Remembered across launches, since it reflects how you work rather than any one project

Changing it is pushed to the running app immediately, so playback in the simulator always
covers the span the timeline draws.

## Hiding the animations

**Hide Animations**, at the right-hand end of the transport row, sets the tracks aside.
It is for working on the drawings themselves rather than on how they move: with it on,
every vector on the [shape canvas](drawing.md#drawing-mode) is drawn where it was drawn,
untransformed, instead of wherever its track has carried it at the playhead.

Turning it on stops playback and switches off everything below it — the play button, the
record button, the loop duration field, and the rows themselves. The rows are dimmed
rather than taken away: they are what the toggle is about, and a timeline that emptied
itself would read as a project whose keyframes had gone. The toggle itself stays live,
since it is the way back.

Nothing is thrown away by it. The tracks are untouched, and turning it off puts every
drawing back where the playhead had it.

- The initial values go with the rest. A track that starts a shape half a screen along is
  still what is carrying it there, so leaving that one part on would keep the drawing away
  from centre with no way to see where it actually sits.
- Only the transforms change. Which drawings are on screen, what is picked, and the sizes
  they are drawn at are the same either way.

Opening the shape canvas turns it on for you, because that is what the canvas is for: the
tools there place a shape inside its parent, and a track playing over the top would be
moving the very thing the drag is placing. Ask for a run on the canvas by turning the
toggle back off; closing the canvas puts the setting back to whatever it was before.

## Deleting a keyframe

Right-click a keypoint on its row and choose **Delete Keyframe**.

The remaining keyframes stay at the times they were recorded at. This is worth stating
because the file stores durations *relative* to the preceding keyframe — removing one
naively would drag everything after it earlier by the gap that disappeared. The editor
refolds the durations so nothing else moves.

## What gets written

Keyframes are held in memory as you record and written to the project's
`animations/animation.inertia` on save — autosave every 10 seconds, or when you close the
project. Reopening a project loads its tracks back and parks each playhead at the end of
what was recorded, so recording continues after the existing keyframes.

See [Animation files](../guides/animation-file.md) for the format.
