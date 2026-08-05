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
4. **An animation file** — `animation.inertia`, written by the editor.

## The API, side by side

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| Import | `import Inertia` | `org.inertiagraphics.inertia` | `from "inertia-react"` |
| Container | `InertiaContainer(dev:id:hierarchyId:)` | `InertiaContainer(dev, id, hierarchyId, baseURL)` | `<InertiaContainer dev id hierarchyId baseURL>` |
| Tag a view | `.inertia("card0")` | `Inertia(id = "card0") { … }` | `<Inertia id="card0">` |
| Playback handle | `@Environment(\.inertiaDataModel)` | `LocalInertia.current` | `useInertia()` |
| Start / stop / restart | `trigger`, `cancel`, `restart` | `trigger`, `cancel`, `restart` | `trigger`, `cancel`, `restart` |
| Query | `isCancelled(id)` | `isCancelled(id)` | `isCancelled(id)` |
| Settable | `isRepeating`, `loopDuration` | `isRepeating`, `loopDuration` | `isRepeating`, `loopDuration` |
| Read-only | `playheadTime`, `seekTime` | `playheadTime`, `seekTime` | `playheadTime`, `seekTime` |
| Constants | `InertiaPlayback` | `InertiaPlayback` | `InertiaPlayback` |
| Editor port | 8060 | 8070 | 8080 |

The three surfaces are the same. SwiftUI is the reference the other two are aligned to, so
what you learn on one carries over: the id you tag a view with is the id you pass to
`trigger`, and `isRepeating` and `loopDuration` are properties you assign to rather than
setter functions.

SwiftUI is the one runtime with no `baseURL` — it reads its animation file from a `Bundle`
and reaches the editor at `127.0.0.1:8060`. Note also that `baseURL` is not the same thing
on the other two: React fetches its animation file from it, while Compose dials the editor
at it.

## Where they still differ

### Loading an animation outside the editor

All three load their own animation file when `dev` is false, and none of them opens a
socket in that mode. Where the file comes from differs:

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| `dev: false` loads | `<id>.inertia` from the app bundle | `<id>.inertia` from `assets/` | `fetch("<baseURL>/<id>.inertia")` |
| A missing or broken file | **traps** | logs, draws nothing | logs, draws nothing |

The SwiftUI runtime is the strict one: with `dev: false` the container reads the bundled
resource during initialization and **traps** if it is missing or fails to decode. An empty
array — the single byte `0x90` — is a valid file; a missing one is a crash. Compose and React log an error and leave
every tagged view at its layout position.

React's path also means something has to be serving that file with CORS headers if it is
not on the same origin as your app. It is fetched as bytes, so no content type is
required, but `application/msgpack` is the correct one to send.

### Interpolation

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| Between keyframes | cubic spline (`CubicKeyframe`) | cubic ease-in-out per segment | cubic ease-in-out per segment |

SwiftUI hands the track to `KeyframeAnimator`, which fits a spline across the whole track
— so motion can overshoot a keyframe on its way to the next one. Compose and React solve
each segment independently with a cubic ease-in-out, which never overshoots. The same file
therefore reads slightly differently on iOS than on Android or the web; the poses at the
keyframes are identical, the paths between them are not.

### Drawn vectors

All three runtimes rasterize the [vectors you draw in the editor](../editor/drawing.md)
themselves — Metal on SwiftUI, OpenGL ES on Compose, WebGL on React — from the shapes
carried in the animation file. Fills, strokes, nesting, per-shape placement, per-shape
tracks, `showsBeforeAnimation`, and both stacking controls — `zIndex` and `position` — work
the same everywhere.

A file missing any of those fields reads the same on all three as well: no z-index is the
bottom of the stack in file order, no `position` is a backdrop, and no
`showsBeforeAnimation` is a shape drawn whether or not anything is playing.

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

Pick the runtime that matches the app you want to animate. All three author the same way in
the editor, ship the same animation file, and expose the same API.

The SwiftUI runtime is the one kept most current — it is where new work lands first, and
its cubic-spline interpolation is the reference the other two approximate.

## Next

- [Installation](installation.md) — add a runtime to your app.
- [Quickstart](quickstart.md) — get a view moving.
