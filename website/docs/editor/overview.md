# Editor tour

The Inertia editor is a macOS app. It hosts a live iOS Simulator, shows you the
Inertia-tagged view hierarchy of the app running inside it, and records what you drag
as keyframes on a timeline.

## Layout

```
┌───────────────┬─────────────────────────────┬───────────────┐
│               │                             │               │
│   Hierarchy   │          Viewport           │  Animations   │
│               │      (live simulator)       │  Properties   │
│               │                             │               │
├───────────────┴─────────────────────────────┴───────────────┤
│                          Timeline                            │
└──────────────────────────────────────────────────────────────┘
```

### Hierarchy

The tree of every view in your app that has an `.inertia(_:)` modifier, as reported by
the running app. Selecting a node here selects it in the simulator; selecting in the
simulator selects it here. Nodes only appear once the app has connected — an empty tree
means no connection.

### Viewport

The actual simulator, streamed. You interact with it directly: taps and gestures go
through to the app, so you can navigate to the screen you want to animate before you
start recording.

Above it sits the toolbar, with a **Home** button, the simulator's connection status,
and the geometry of the current selection — its position and size, which is useful when
you want to know what a normalized `translate` value works out to in points.

While a selection is active, guides are drawn over the viewport: the container's center
lines, plus dashed lines tracking the selected view's edges and center. They make it
possible to line something up against the container rather than by eye.

### Animations panel

The animations available in the project, and which of them are attached to the selected
node. A view with no attached animation has nothing to record into; attaching one gives
it a track on the timeline.

### Timeline

The playhead, the transport controls, and one row of keypoints per animated view. This
is where authoring happens — see [Timeline and keyframes](timeline.md).

## Framework picker

The editor has a segmented control for the target framework. **SwiftUI** is the
supported option; the others are present but not documented here.

## Autosave

The editor saves the open project every 10 seconds while you work, and on close. It will
not overwrite a project with an empty animation store, so a connection that drops before
the app reports anything cannot wipe work you already recorded.

You can still lose the last few seconds of edits to a crash. Nothing here replaces
having the project directory under version control if the animations matter.

## Installing your app

The editor can install and launch a build on the simulator for you, rather than round
tripping through Xcode. Point it at a built `.app` bundle and it runs `simctl install`
followed by a launch, reading the bundle identifier out of the bundle itself.

Builds you install this way still need the `INERTIA_EDITOR` flag compiled in — the
editor cannot turn on editor mode in an app that was not built for it. See
[Editor mode](../getting-started/editor-mode.md).
