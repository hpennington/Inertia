# Editor tour

The Inertia editor is a macOS app. It hosts a live copy of your app — an iOS Simulator, an
Android emulator, or a web page — shows you the Inertia-tagged view hierarchy the app
reports, and records what you drag as keyframes on a timeline.

## Layout

```
┌───────────────┬───┬─────────────────────┬───┬───────────────┐
│               │ T │                     │ T │               │
│   Hierarchy   │ o │      Viewport       │ r │  Animations   │
│               │ o │  (your live app)    │ a │  Properties   │
│               │ l │                     │ n │               │
├───────────────┴───┴─────────────────────┴───┴───────────────┤
│                          Timeline                            │
└──────────────────────────────────────────────────────────────┘
```

### Hierarchy

The tree of every tagged view in your app, as reported by the running app. Selecting a node
here selects it in the viewport; selecting in the viewport selects it here. Nodes only
appear once the app has connected — an empty tree means no connection.

The scope button in the panel's header is **focus**. It puts the app under test into
editing mode, which is what makes its views answer to a click and a drag rather than
passing both through to the app itself. Selecting a view or a drawn shape by clicking it
in the viewport needs it on; picking rows here works either way.

Vectors drawn against a view are listed underneath it, with anything nested inside them
listed under that — see [Drawing vectors](drawing.md).

### Viewport

Your app, live. You interact with it directly: taps and gestures go through to the app, so
you can navigate to the screen you want to animate before you start recording. What is
actually in the pane depends on the target:

| Target | Viewport | Toolbar |
| --- | --- | --- |
| iOS | The simulator, streamed from its `IOSurface` | **Home**, connection status, and the geometry of the current selection |
| Android | The emulator, streamed as H.264 over `adb` | **Back**, **Home**, **Recents**, and connection status |
| Web | Your dev server, in a web view | An address bar above the pane, defaulting to `http://localhost:3000` |

The selection geometry readout — the position and size of the selected view, useful for
working out what a normalized `translate` comes to in points — is reported by the SwiftUI
and React runtimes. Compose does not send it, so it stays blank on the Android target.

While you drag a selected view, guides are drawn over the viewport: the container's center
lines, plus dashed lines tracking the view's edges and center. They make it possible to
line something up against the container rather than by eye. All three runtimes draw them.

A shape drawn against a view is picked by clicking it too, in editor mode, and the click
has to land on the artwork — the corner beside a circle, or the margin beside a triangle's
slope, goes through to whatever is behind it. See [Drawing vectors](drawing.md).

The scribble toggle at the bottom of the tool palette replaces the app with the **shape
canvas** — the vectors you have drawn, by themselves, drawn and dragged with the app
nowhere in the picture. See [Drawing vectors](drawing.md#drawing-mode).

### Tool palette

The narrow column between the hierarchy and the viewport. The top half is the five
**tools** — Move, Rotate, Rotation Center, Opacity, Scale — one of which is always active,
deciding what a drag on the selected node changes. They are modal: off the record a gesture
moves where the animation *starts* from, and with recording armed the same gesture writes a
keyframe at the playhead. The palette turns red to say which of the two it is in.

The active tool hangs its handles on whatever is selected, over the app and over the shape
canvas alike — the same knobs on the same geometry either way. What a drag lands on is what
differs: over the canvas the transform toolset places the picked shape in its parent rather
than moving a view there is no app to move. See [Drawing vectors](drawing.md#drawing-mode).

The lower half is the **vector palette**, which draws shapes into the selected view, and the
scribble toggle at the very bottom swaps the viewport into drawing mode. Both are covered in
[Drawing vectors](drawing.md).

### Transform column

The narrow column on the other side of the viewport: the property the active tool edits, as
a slider and a field. A drag needs the node to be somewhere reachable — off-screen, behind
another view or scaled to nothing, it is not — and these edit the same values wherever it
has got to. An edit lands exactly where a drag would land it, so the column follows the
palette's two modes rather than having any of its own.

*When* a slider authors follows from that. Off the record it authors as it moves, so the
node follows the thumb; recording, it waits for the release, because every value on the way
there would otherwise be a keypoint at the same time on the timeline.

### Animations panel

The animations available in the project, and which of them are attached to the selected
node. A view with no attached animation has nothing to record into; attaching one gives
it a track on the timeline. Drawings that carry a track of their own are listed under the
animation that holds them, and a drawing's row carries the one menu item that is about its
track rather than about the shape: **Delete Shape Animation**, which takes the track off
and leaves the drawing where it is.

While drawing mode is on, this panel describes the selected shape instead — see [Shape
properties](drawing.md#shape-properties).

### Timeline

The playhead, the transport controls, and one row of keypoints per animated view. This
is where authoring happens — see [Timeline and keyframes](timeline.md). **Hide
Animations**, at the right-hand end of the transport row, sets the tracks aside and
switches the rest of the timeline off — see [Hiding the
animations](timeline.md#hiding-the-animations).

## Framework picker

A segmented control above the animations panel chooses the target: **Web**, **iOS** or
**Android**. Switching it swaps the viewport and points the editor at that runtime's
listener — 8080, 8060 and 8070 respectively.

The three listeners run independently, so an app on each can be connected at once and
switching the picker moves between them without anything reconnecting. What the picker does
*not* do is convert a project: the animations are the same file either way, but you record
them against whichever app is in the viewport.

See [Choosing a runtime](../getting-started/runtimes.md) for what each target supports.

## Autosave

The editor saves the open project every 10 seconds while you work, and on close. It will
not overwrite a project with an empty animation store, so a connection that drops before
the app reports anything cannot wipe work you already recorded.

You can still lose the last few seconds of edits to a crash. Nothing here replaces
having the project directory under version control if the animations matter.

## Getting your app in front of it

=== "SwiftUI"

    The editor can install and launch a build on the simulator for you, rather than round
    tripping through Xcode. Point it at a built `.app` bundle and it runs `simctl install`
    followed by a launch, reading the bundle identifier out of the bundle itself.

    Builds you install this way still need the `INERTIA_EDITOR` flag compiled in — the
    editor cannot turn on editor mode in an app that was not built for it.

=== "Compose"

    Start an emulator yourself — the editor attaches to a running one but never boots one
    — then install the app from Android Studio or with `adb install -r`.

    Once a device appears, the editor opens the `adb reverse` tunnel and starts the screen
    stream on its own. Relaunching the app reconnects; you do not need to touch the editor.

=== "React"

    Start your dev server and put its URL in the address bar above the viewport. The editor
    loads it in a web view. Reloading the page redials the editor.

See [Editor mode](../getting-started/editor-mode.md) for the connection details.
