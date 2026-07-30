# Editor mode

Editor mode is what lets you drag your app's real views around and have the movement
recorded as keyframes. It is a different code path in the runtime, switched on by the
`dev` flag on `InertiaContainer`.

## What changes when `dev` is `true`

| | `dev: false` | `dev: true` |
| --- | --- | --- |
| Animations come from | `animation.json` in the app bundle | the editor, over a WebSocket |
| Tagged views | animate | animate, and are selectable and draggable |
| Playback clock | runs in the app | still runs in the app; the editor pauses, scrubs and resumes it by message, and mirrors its position on the playhead |
| Starting an animation | `trigger(_:)` from your app | `trigger(_:)` from your app — the editor cannot start one |
| Bundle resource | required at init | not read |
| WebSocket server | never started | listening on port 8060 |

Because the container never touches the bundle resource in editor mode, you can start
authoring before you have an animation file at all.

!!! warning "Editor mode requires the container id `animation`"

    The editor addresses every schema it sends to the container id `"animation"`, and the
    runtime drops schemas meant for a different container. A container with any other `id`
    connects and shows its hierarchy but never receives an animation.

The `dev` flag also gates the WebSocket server itself: with `dev: false` the runtime never
opens a listener on port 8060, so a shipped build cannot be attached to.

## Wiring it to a build flag

Do not ship `dev: true`. Gate it on a compile-time flag so release builds cannot
accidentally include the editor path:

```swift
struct AppEnvironment {
    #if INERTIA_EDITOR
    static let isInertiaEditor = true
    #else
    static let isInertiaEditor = false
    #endif
}

InertiaContainer(dev: AppEnvironment.isInertiaEditor, id: "animation", hierarchyId: "animation") {
    ContentView()
}
```

Add `-D INERTIA_EDITOR` to **Other Swift Flags** for a dedicated scheme or build
configuration. The example app in the repository uses a separate target for this, which
also works and keeps the flag out of your main target entirely.

## Connecting

1. Boot an iOS Simulator, or let the editor pick a booted one.
2. Open the Inertia editor and open (or create) a project.
3. Build your app with the `INERTIA_EDITOR` flag and install it on that simulator —
   from Xcode, or through the editor's **Install and launch** panel.
4. Launch the app.

The app is the one hosting: on launch it starts a WebSocket **server** on port **8060**,
and the editor connects to it as a client at `ws://127.0.0.1:8060` — the simulator shares
the Mac's network stack, so there is no address to discover. Once attached, the app sends
its Inertia-tagged view hierarchy, the editor's hierarchy panel fills in, and you are
connected. Selecting a view in the simulator highlights it in the editor and the other
way around.

Because the editor dials in and retries, the order does not matter: launch the app first
and the editor picks it up, or leave the editor open and it attaches when the app comes
up.

If the hierarchy panel stays empty, see [Troubleshooting](../troubleshooting.md).

## The authoring loop

Once connected, the cycle is short:

1. Select a tagged view in the simulator.
2. Move the playhead to where you want a pose.
3. Turn on recording and drag the view.
4. Play the timeline back with <kbd>Space</kbd>.

That is the subject of [Timeline and keyframes](../editor/timeline.md).

## Getting the animation into your app

The editor writes to its project directory, not into your Xcode project. When you are
happy with the animation, copy the file across:

```sh
cp ~/InertiaStorage/MyProject.inertia/animations/animation.json \
   path/to/MyApp/animation.json
```

Then build without the `INERTIA_EDITOR` flag. The container now loads that file from the
bundle and plays it with no editor involved. [Projects](../editor/projects.md) covers the
project layout.
