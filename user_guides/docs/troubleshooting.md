# Troubleshooting

## The app crashes on launch in a release build

SwiftUI only. `InertiaContainer` with `dev: false` reads `<id>.inertia` from the bundle during
initialization and traps if it is missing or does not decode.

Check, in order:

1. The file exists and its name matches the container's `id` — `id: "animation"` needs
   `animation.inertia`.
2. It is listed under **Target → Build Phases → Copy Bundle Resources**.
3. It parses. `[]` is valid; a trailing comma is not.

The other two runtimes do not crash on a missing file: React logs a failed fetch and carries
on, and Compose has no file to miss.

## The editor's hierarchy panel is empty

The tree is reported by the running app, so an empty panel means no app has connected.

First check the obvious one: **is the framework picker on the right target?** Each runtime
has its own listener, and the panel only shows the one currently selected.

=== "SwiftUI"

    - Is the app built with the `INERTIA_EDITOR` flag, and is `dev` actually `true`? An app
      built without it connects to nothing, however it was installed.
    - Is the app running in the foreground on the simulator the editor is attached to?
    - Does the app have at least one `.inertia(_:)` view? A container with no tagged views
      reports a tree with only its root.
    - Is anything else holding port **8060**?

    Console output from the runtime is prefixed `[INERTIA_LOG]`, which makes it easy to
    filter in Console.app or `xcrun simctl spawn booted log stream`.

=== "Compose"

    - Is `baseURL` right? From an emulator it should be `ws://127.0.0.1:8070`, which works
      because the editor opens `adb reverse tcp:8070 tcp:8070`. If the editor never saw the
      device, that tunnel does not exist and `127.0.0.1` is the emulator itself. A stock
      emulator can also reach the host at `10.0.2.2`.
    - Is cleartext traffic permitted for that host? Android denies `ws://` by default from
      `targetSdk` 28 on — see [Installation](getting-started/installation.md).
    - Does the manifest have `android.permission.INTERNET`?
    - Is `adb` reachable by the editor? It looks on `PATH`, at `ANDROID_HOME`, at
      `~/Library/Android/sdk/platform-tools`, and in the Homebrew prefixes.
    - Is anything else holding port **8070**?

    The runtime logs under the `Inertia` tag: `adb logcat -s Inertia`.

=== "React"

    - Is `dev` actually `true`? With it false the container never opens a socket.
    - Is the page loaded in the editor's own web view? The runtime dials
      `ws://127.0.0.1:8080`, so a page served from another machine cannot reach it.
    - Is the page served over `https`? A secure page refuses a `ws://` dial outright.
    - Does the app have at least one `<Inertia>`? A container with no tagged views
      reports a tree with only its root.
    - Is anything else holding port **8080**?

    Console output is prefixed `[INERTIA_LOG]`, which filters cleanly in devtools.

## Dragging a view records nothing

Recording has to be armed — the record button on the timeline, red when active. With it
off, dragging repositions the view in the viewport but writes no keyframe. See
[Timeline and keyframes](editor/timeline.md).

## The vector palette is dim

A shape is drawn into one view, so the buttons only come alive with **exactly one** row
selected in the hierarchy. Nothing selected, or two rows selected, and there is no single
answer to where the shape would go. See [Drawing vectors](editor/drawing.md#inserting-a-shape).

## A shape was inserted but nothing appeared

Work down these in order:

1. **Is it visible at all?** A shape with no fill and no stroke draws nothing. The insert
   modal refuses that combination, but taking both colours to transparent in the properties
   panel afterwards does not.
2. **Is it behind something opaque?** A shape defaults to **Behind** the view's content. Try
   **In Front** — on iOS; the other two runtimes always draw behind, see [Choosing a
   runtime](getting-started/runtimes.md#drawn-vectors).
3. **Is it off-screen?** Sizes and offsets are multiples of the view's shorter side, so a
   `0.05` shape on a small view is a few points across, and an offset of `2` puts it well
   outside the screen.
4. **Is the view on screen?** A shape is measured against the view it was authored on. If
   that view is not laid out in the app right now, there is nothing to measure it against and
   nothing is drawn.

## The shape canvas is empty

The message says which of three things happened: **Waiting for the app to connect** (no
runtime attached), **Every drawing is hidden** (turn an eye button back on in the hierarchy),
or **Nothing is drawn on the views on screen** (the project's drawings belong to views the
app is not currently showing).

## A nested shape will not move

A shape drawn inside another has no rendering layer of its own, so it cannot carry a track
— recording a drag on it does nothing. Move it with an offset instead: drawing mode on,
recording off, and use the transform column. See
[Placing a shape in its parent](editor/drawing.md#placing-a-shape-in-its-parent).

## Shapes stack differently on Android or the web

Expected. `zIndex` and **In Front** are honoured by the SwiftUI runtime only; Compose and
React draw every shape behind the view's content, in the order the file lists them. The
editor's canvas follows SwiftUI. See [Choosing a
runtime](getting-started/runtimes.md#drawn-vectors).

## A view does not animate

The runtime plays a track only once its id has been triggered:

```
inertia.trigger("card0")
```

On SwiftUI, `invokeType: "auto"` in the file does not do this — that runtime does not act
on the field. Compose and React do start `auto` animations for you. See
[Triggering animations](guides/triggering.md).

If it is triggered and still still, check the id matches exactly. `.inertia("Card0")` and
an animation with `"id": "card0"` never find each other, and nothing warns you.

## An Android build shows nothing with the editor closed

Expected, for now. The Compose container never loads an animation file for itself — schemas
only ever arrive from the editor over the socket, so a build with no editor attached leaves
every tagged view at its initial pose while retrying the dial in the background.

See [Choosing a runtime](getting-started/runtimes.md), and keep the container out of
release builds.

## A React build shows nothing with `dev` false

The container fetches `<baseURL>/<id>.inertia` and logs the failure rather than crashing, so
this is almost always a fetch that did not land. In the console, look for
`[INERTIA_LOG]: Failed to load animation file` and check:

1. Something is actually serving that path.
2. It sends `Access-Control-Allow-Origin` if it is not the same origin as your page.
3. `baseURL` has no trailing slash — the URL is built as `` `${baseURL}/${id}.inertia` ``.

## Pressing play in the editor does nothing

=== "SwiftUI"

    The editor's play button resumes a run; it cannot start one. Resume only affects
    actionables the app has already triggered, so a view your app never calls `trigger(_:)`
    on stays still no matter what the transport does.

    Give the app a way to trigger while you author — a button, or `.onAppear` — then use
    the editor's transport to play, pause and scrub it.

=== "Compose"

    Play starts every registered animation regardless of `invokeType`, so a view that stays
    still is usually one whose schema never arrived rather than one that was never
    triggered. Check that it has an animation attached in the animations panel.

=== "React"

    Play starts every animation whose schema the runtime holds, regardless of `invokeType`,
    so a view that stays still is usually one whose schema never arrived rather than one
    that was never triggered. Check that it has an animation attached in the animations
    panel.

If nothing at all moves and the hierarchy panel is populated, check the container's `id` on
any runtime: the editor sends its schemas to the container id `animation`, and the runtime
drops schemas addressed to any other container.

## A view jumps between poses instead of moving

A keyframe `duration` that is zero, negative or non-finite. Interpolation divides by the
duration, so every runtime rewrites any such duration to 1ms before playing the track — the
view still animates, but that segment is over instantly.

The editor keeps durations above the same minimum, so this generally comes from
hand-edited files. Leading keyframes at `duration: 0` are fine — they are starting poses,
and 1ms of it is not visible.

A view that vanishes outright is a different problem: check `opacity`, `scale: 0`, and a
`translate` big enough to put it outside the container. Every runtime replaces a pose it
cannot draw with the neutral one, so a non-finite value leaves the view sitting still, not
missing.

## The animation is in the wrong place on a different device

`translate` is a fraction of the **container's** size. If the container is not the region
you thought it was, every offset in it is scaled against the wrong box.

Check that the container wraps what you intend — usually the root view, filling the screen
— and that nothing between it and the animated view constrains the frame in a way you did
not mean.

All three containers fill the space their host offers them — `GeometryReader` plus
`.frame(maxWidth:maxHeight: .infinity)` on SwiftUI, `fillMaxSize()` on Compose,
`width: 100%; height: 100%` on React — so they resolve `translate` against the same
rectangle. What differs is what the *host* offers: a container nested inside something that
constrains it gets the smaller box, and every offset in it scales down with it.

## The animation reads differently on iOS than on Android or the web

Expected, within limits. SwiftUI fits a cubic spline across the whole track, so motion can
overshoot a keyframe on the way to the next one. Compose and React solve each segment
independently with a cubic ease-in-out, which never overshoots.

The poses at the keyframes are identical on all three; only the paths between them differ.
If a track depends on the overshoot for its feel, add intermediate keyframes so the shape
is in the file rather than in the interpolator.

## Playback in the editor does not match the app

The likely cause is **loop duration**. The editor's loop length is not stored in the
animation file, so a standalone animation loops over `max(3 seconds, its longest track)`
however long the timeline you authored on was. An animation built against a 5-second
timeline whose longest track ends at 4 seconds loops over 4 seconds in the app.

Either keep the editor at 3 seconds, or — on SwiftUI, the runtime that exposes it — set
`inertia.loopDuration` in your app to the length you authored against.

## Scrubbing the playhead does nothing

Scrubbing is disabled during playback — pause first with <kbd>Space</kbd> or the transport
button. While playing, the playhead is reporting the runtime's clock rather than driving
it.

## <kbd>Space</kbd> does not play or pause

The shortcut is suppressed while a text field has focus, so a space you type in the loop
duration field, the web address bar, or a search box inserts a space instead of toggling
playback. Click into the viewport and try again. It is also suppressed while the install
sheet is open.

## Edits vanished after a crash

The editor autosaves every 10 seconds and on close, so a crash can cost the last few
seconds of work. It deliberately will not save an empty animation store over a project
that has animations, so a dropped connection cannot blank a project — but keep the project
directory in version control if the animations matter.
