# Choosing a runtime

Three runtimes read the animations the editor writes. They are separate implementations
of one model, kept deliberately parallel — the same file format, the same ids, the same
five animatable values, the same clock semantics — but they are not at the same level of
maturity, and the differences that remain are worth knowing before you start.

## The shared model

Every runtime has the same four pieces:

1. **A container** — one per animated region. It owns the animation data, measures the box
   that `translate` values are resolved against, and holds the editor connection.
2. **An actionable** — a wrapper around one view. It registers itself in the hierarchy the
   editor draws, claims an id, and applies the animated transform. In editor mode it is
   also selectable and draggable.
3. **A playback handle** — the app's way to start an animation. Nothing animates until an
   id is triggered.
4. **An animation file** — `animation.json`, written by the editor.

## The API, side by side

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| Import | `import Inertia` | `org.inertiagraphics.inertia` | `from "inertia-react"` |
| Container | `InertiaContainer(dev:id:hierarchyId:)` | `InertiaContainer(id, baseURL, dev)` | `<InertiaContainer id baseURL dev>` |
| Tag a view | `.inertia("card0")` | `Inertiaable("card0") { … }` | `<Inertiaable hierarchyIdPrefix="card0">` |
| Playback handle | `@Environment(\.inertiaDataModel)` | `LocalInertia.current` | `useInertia()` |
| Start an animation | `trigger(_:)` | `trigger(…)` | `trigger(…)` |
| Stop / restart | — | `cancel`, `restart` | `cancel`, `restart` |
| Editor port | 8060 | 8070 | 8080 |

The Compose and React runtimes expose `cancel` and `restart`; the SwiftUI one does not,
so a SwiftUI app can start a run but not stop or rewind it.

## Where they still differ

### Loading an animation outside the editor

This is the big one.

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| `dev: false` loads | `<id>.json` from the app bundle | **nothing** | `fetch("<baseURL>/<id>.json")` |
| `dev: false` opens a socket | no | **yes, always** | no |

The Compose container accepts a `dev` parameter and never reads it: it connects to
`baseURL` unconditionally, and has no path that loads an animation file for itself. In
practice the Compose runtime is an editor-time tool today — a build with no editor
listening connects to nothing and every tagged view sits at its initial pose.

!!! warning "Do not ship a Compose build with `InertiaContainer` in it"

    Because the `dev` flag is not honoured, a released Compose app would keep retrying a
    WebSocket dial to whatever `baseURL` names, and would still show no animation. Gate
    the container out of release builds yourself — a build-variant source set, or a
    `BuildConfig.DEBUG` branch around the container.

The SwiftUI runtime goes the other way and is strict about it: with `dev: false` the
container reads the bundled resource during initialization and **traps** if it is missing
or fails to decode. An empty `[]` is a valid file; a missing one is a crash.

React sits in between. It fetches `<baseURL>/<id>.json` over HTTP and logs an error if the
request fails, so a missing file is a still page rather than a crash — but it does mean
something has to be serving that JSON with CORS headers.

### Interpolation

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| Between keyframes | cubic spline (`CubicKeyframe`) | cubic ease-in-out per segment | cubic ease-in-out per segment |

SwiftUI hands the track to `KeyframeAnimator`, which fits a spline across the whole track
— so motion can overshoot a keyframe on its way to the next one. Compose and React solve
each segment independently with a cubic ease-in-out, which never overshoots. The same file
therefore reads slightly differently on iOS than on Android or the web; the poses at the
keyframes are identical, the paths between them are not.

### Editor transport

All three follow the editor's playhead: pause, resume, seek and loop-duration changes
arrive over the socket, and all three report their playback position back so the editor's
playhead can track a running animation. All three draw alignment guides while you drag.

The one gap is the selection geometry the viewport toolbar shows — position and size of the
selected view. SwiftUI and React report it; Compose does not, so the readout stays blank on
the Android target.

### What the editor can install for you

The editor installs and launches a build on the **iOS Simulator** for you. On Android and
Web you launch the app yourself — from Android Studio or `adb install`, or by starting
your dev server. Everything after that is the same.

## Which to pick

If you are animating an iOS app, use the SwiftUI runtime: it is the one that is kept
current, and the only one with a supported release path today.

Use the Compose and React runtimes when the app you want to animate is already an Android
or web app. Author against them in the editor exactly as you would for iOS — just know
that on Compose, shipping the result is not yet a solved path.

## Next

- [Installation](installation.md) — add a runtime to your app.
- [Quickstart](quickstart.md) — get a view moving.
