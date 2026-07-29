# Troubleshooting

## The app crashes on launch in a release build

`InertiaContainer` with `dev: false` reads `<id>.json` from the bundle during
initialization and traps if it is missing or does not decode.

Check, in order:

1. The file exists and its name matches the container's `id` — `id: "animation"` needs
   `animation.json`.
2. It is listed under **Target → Build Phases → Copy Bundle Resources**.
3. It parses. `[]` is valid; a trailing comma is not.

## The editor's hierarchy panel is empty

The tree is reported by the running app, so an empty panel means no app has connected.

- Is the app built with the `INERTIA_EDITOR` flag, and is `dev` actually `true`? An app
  built without it connects to nothing, however it was installed.
- Is the app running in the foreground on the simulator the editor is attached to?
- Does the app have at least one `.inertia(_:)` view? A container with no tagged views
  reports a tree with only its root.
- Is anything else holding port **8060**?

Console output from the runtime is prefixed `[INERTIA_LOG]`, which makes it easy to filter
in Console.app or `xcrun simctl spawn booted log stream`.

## Dragging a view records nothing

Recording has to be armed — the record button on the timeline, red when active. With it
off, dragging repositions the view in the viewport but writes no keyframe. See
[Timeline and keyframes](editor/timeline.md).

## A view does not animate

The runtime plays a track only once its id has been triggered:

```swift
inertia.trigger("card0")
```

`invokeType: "auto"` in the file does not do this — the SwiftUI runtime does not act on
that field. See [Triggering animations](guides/triggering.md).

If it is triggered and still still, check the id matches exactly. `.inertia("Card0")` and
an animation with `"id": "card0"` never find each other, and nothing warns you.

## A view disappears mid-animation

Almost always a zero or negative keyframe `duration`. The cubic interpolation divides by
the duration, producing `NaN`, and a view offset by `NaN` is not drawn.

The editor keeps durations above a small positive minimum, so this generally comes from
hand-edited files. Leading keyframes at `duration: 0` are fine — they are starting poses.

## The animation is in the wrong place on a different device

`translate` is a fraction of the **container's** size. If the container is not the region
you thought it was, every offset in it is scaled against the wrong box.

Check that `InertiaContainer` wraps what you intend — usually the root view, filling the
screen — and that nothing between it and the animated view constrains the frame in a way
you did not mean.

## Playback in the editor does not match the app

Two likely causes:

- **Loop duration.** The editor's loop length is not stored in the animation file. An
  animation authored on a 5-second timeline still loops over the runtime's 3-second
  default when loaded from the bundle. Either keep the editor at 3 seconds or set
  `inertia.loopDuration` in your app to match.
- **`rotate`.** The editor's live preview draws `rotateCenter` but not `rotate`. A
  top-left rotation shows up in a `dev: false` build and not in the editor.

## Scrubbing the playhead does nothing

Scrubbing is disabled during playback — pause first with <kbd>Space</kbd> or the transport
button. While playing, the playhead is reporting the runtime's clock rather than driving
it.

## <kbd>Space</kbd> does not play or pause

The shortcut is suppressed while a text field has focus, so a space you type in the loop
duration field or a search box inserts a space instead of toggling playback. Click into the
viewport and try again. It is also suppressed while the install sheet is open.

## Edits vanished after a crash

The editor autosaves every 10 seconds and on close, so a crash can cost the last few
seconds of work. It deliberately will not save an empty animation store over a project
that has animations, so a dropped connection cannot blank a project — but keep the project
directory in version control if the animations matter.
