# Editor tour

The Inertia editor is a macOS app. It hosts a live copy of your app — an iOS Simulator, an
Android emulator, or a web page — shows you the Inertia-tagged view hierarchy the app
reports, and records what you drag as keyframes on a timeline.

## Layout

```
┌───────────────┬─────────────────────────────┬───────────────┐
│               │                             │               │
│   Hierarchy   │          Viewport           │  Animations   │
│               │      (your live app)        │  Properties   │
│               │                             │               │
├───────────────┴─────────────────────────────┴───────────────┤
│                          Timeline                            │
└──────────────────────────────────────────────────────────────┘
```

### Hierarchy

The tree of every tagged view in your app, as reported by the running app. Selecting a node
here selects it in the viewport; selecting in the viewport selects it here. Nodes only
appear once the app has connected — an empty tree means no connection.

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

### Animations panel

The animations available in the project, and which of them are attached to the selected
node. A view with no attached animation has nothing to record into; attaching one gives
it a track on the timeline.

### Timeline

The playhead, the transport controls, and one row of keypoints per animated view. This
is where authoring happens — see [Timeline and keyframes](timeline.md).

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
