# Editor mode

Editor mode is what lets you drag your app's real views around and have the movement
recorded as keyframes. It is a different code path in the runtime, switched on by the
`dev` flag on the container.

## What changes when `dev` is `true`

| | `dev: false` | `dev: true` |
| --- | --- | --- |
| Animations come from | `animation.inertia`, loaded by the container | the editor, over a WebSocket |
| Tagged views | animate | animate, and are selectable and draggable |
| Playback clock | runs in the app | still runs in the app; the editor pauses, scrubs and resumes it by message, and mirrors its position on the playhead |
| WebSocket client | never started | dialing the editor |

Because the container never touches its animation file in editor mode, you can start
authoring before you have one at all.

!!! warning "Editor mode requires the container id `animation`"

    The editor addresses every schema it sends to the container id `"animation"`, and each
    runtime drops schemas meant for a different container. A container with any other `id`
    connects and shows its hierarchy but never receives an animation.

## Ports

The editor hosts; the app dials in. Each runtime has its own port, so all three can be
open at once:

| Runtime | Editor target | Port | The app dials |
| --- | --- | --- | --- |
| SwiftUI | iOS | **8060** | `ws://127.0.0.1:8060` |
| Compose | Android | **8070** | `ws://127.0.0.1:8070` |
| React | Web | **8080** | `ws://127.0.0.1:8080` |

Because the app dials in and retries, order does not matter: open the editor first and the
app attaches when it launches, or launch the app and it picks the editor up once the editor
is listening.

## Turning it on

=== "SwiftUI"

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

    The `dev` flag gates the WebSocket client itself: with `dev: false` the runtime never
    dials port 8060, so a shipped build never reaches for an editor.

=== "Compose"

    ```kotlin
    InertiaContainer(
        dev = true,
        id = "animation",
        hierarchyId = "animation",
        baseURL = "ws://127.0.0.1:8070"
    ) {
        DemoApp()
    }
    ```

    `dev` gates the socket here too: with `dev = false` the container never dials the
    editor and reads `assets/animation.inertia` instead, so it is safe to leave in a release
    build.

    `baseURL` is passed through as given. From an emulator, `127.0.0.1` reaches the editor
    because the editor opens an `adb reverse` tunnel for port 8070 when it attaches — see
    below. From a physical device, point it at your Mac's address on the local network
    instead.

=== "React"

    ```tsx
    const isDev = process.env.REACT_APP_INERTIA_DEV !== "false";

    <InertiaContainer id="animation" baseURL={baseURL} dev={isDev}>
      <DemoContent />
    </InertiaContainer>
    ```

    With `dev` false the container never opens a socket, so a production bundle does not
    reach for an editor.

    Note that `baseURL` is **not** the editor's address. The editor connection is always
    `ws://127.0.0.1:8080`; `baseURL` is only where `<id>.inertia` is fetched from when `dev`
    is false.

## Connecting

=== "SwiftUI"

    1. Boot an iOS Simulator, or let the editor pick a booted one.
    2. Open the Inertia editor, open (or create) a project, and select **iOS** in the
       framework picker.
    3. Build your app with the `INERTIA_EDITOR` flag and install it on that simulator —
       from Xcode, or through the editor's **Install and launch** panel.
    4. Launch the app.

    The simulator shares the Mac's network stack, so `127.0.0.1` reaches the editor with
    no address to discover.

=== "Compose"

    1. Start an Android emulator — from Android Studio's Device Manager, or
       `emulator -avd <name>`. The editor never boots one for you.
    2. Open the Inertia editor, open (or create) a project, and select **Android** in the
       framework picker.
    3. Install and launch your app on that emulator, from Android Studio or
       `adb install -r app-debug.apk`.

    The editor needs `adb` on its `PATH` or an `ANDROID_HOME` pointing at the SDK; it also
    checks `~/Library/Android/sdk/platform-tools` and the Homebrew prefixes. With a device
    attached it does two things:

    - Opens a reverse tunnel, `adb reverse tcp:8070 tcp:8070`, so `127.0.0.1:8070` inside
      the emulator is the editor's listener on your Mac. Without it, `127.0.0.1` is the
      emulator itself.
    - Pushes scrcpy's server onto the device and streams hardware-encoded H.264 back, which
      is what the viewport shows.

    The viewport toolbar has **Back**, **Home** and **Recents** buttons, since an emulator
    has no window chrome inside the editor.

=== "React"

    1. Start your dev server — `npm start`, which Create React App serves on port 3000.
    2. Open the Inertia editor, open (or create) a project, and select **Web** in the
       framework picker.
    3. Put your app's URL in the address bar above the viewport. It defaults to
       `http://localhost:3000`.

    The editor loads that URL in a web view, so your page and the editor are on the same
    machine and `ws://127.0.0.1:8080` reaches the listener directly. There is nothing to
    install and nothing to tunnel — reload the page and the runtime redials.

Once attached, the app sends its Inertia-tagged view hierarchy, the editor's hierarchy
panel fills in, and you are connected. Selecting a view in the viewport highlights it in
the editor and the other way around.

If the hierarchy panel stays empty, see [Troubleshooting](../troubleshooting.md).

## The authoring loop

Once connected, the cycle is short and is the same on every runtime:

1. Select a tagged view in the viewport.
2. Move the playhead to where you want a pose.
3. Turn on recording and drag the view.
4. Play the timeline back with <kbd>Space</kbd>.

That is the subject of [Timeline and keyframes](../editor/timeline.md).

## Getting the animation into your app

The editor writes to its project directory, not into your app's source tree. When you are
happy with the animation, take the file across:

=== "SwiftUI"

    ```sh
    cp ~/InertiaStorage/MyProject.inertia/animations/animation.inertia \
       path/to/MyApp/animation.inertia
    ```

    Then build without the `INERTIA_EDITOR` flag. The container now loads that file from
    the bundle and plays it with no editor involved.

=== "Compose"

    There is no path for this yet. The Compose container has no loader of its own, so the
    animation only ever exists on the wire — an Android build with no editor attached shows
    every tagged view at its initial pose.

    Until that changes, treat the Compose runtime as an authoring target: use it to record
    an animation against a real Android app, and ship the result through a runtime that can
    load it.

=== "React"

    Nothing to copy, as long as the animations directory is being served:

    ```sh
    cd ~/InertiaStorage/MyProject.inertia/animations
    python3 -m http.server 8000
    ```

    Then run with `dev` false and `baseURL` pointing at that server. For a real deploy,
    copy `animation.inertia` into your app's static assets and point `baseURL` at wherever
    they are served from.

[Projects](../editor/projects.md) covers the project layout.
