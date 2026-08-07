# Inertia

**A keyframe animation editor for the UI you already built.**

Wrap the views you want to move, run your app inside the Inertia editor, drag those views
around on a timeline, and Inertia writes the result to a JSON file your app loads at
runtime.

There is no separate rendering surface and no exported video. The thing you animate in the
editor is the real view in your real app — a real `RoundedRectangle`, a real `Card`
composable, a real `<div>` — playing through the platform's own animation engine.

📚 **[Read the user guides →](https://hpennington.github.io/Inertia/)**

https://github.com/user-attachments/assets/7da417fa-e707-41e1-bc93-a0ca68540f73

## Why Inertia

Design tools export a video or a Lottie file — something that plays *next to* your UI
rather than being it. Code-first animation libraries keep you in a compile-run-tweak loop
where the feedback for a 40ms timing change is a rebuild.

Inertia sits between the two. Your app is the canvas:

- **You animate real components.** No re-implementation, no parallel design file that
  drifts from the app.
- **You keep native performance.** SwiftUI plays tracks through `KeyframeAnimator`;
  Compose and React sample the same tracks on their own clocks. Nothing is rasterized.
- **The handoff is a JSON file.** Designers scrub a timeline, developers `git add` the
  result. One file, three runtimes, identical ids.
- **Editing is live.** The app connects to the editor over a local WebSocket, reports its
  tagged hierarchy, and receives schema updates as you edit. What you see running is the
  animation as it currently stands.

## Runtimes

| Runtime | Package | Editor target |
| --- | --- | --- |
| **SwiftUI** | `Inertia` (Swift package) | iOS Simulator, driven through `simctl` |
| **Jetpack Compose** | `com.github.hpennington:inertia-compose` | Android emulator, over `adb` |
| **React** | `inertia-react` + `inertia-base` | Your dev server, in a `WKWebView` |

The editor is a macOS app in every case.

## Features

- 🌍 Three runtimes — SwiftUI, Jetpack Compose, React — on one file format
- 🎨 WYSIWYG keyframe editor with MessagePack export
- ⚡ Native playback: `KeyframeAnimator` on iOS, native clocks on Android and web
- 🎛️ Playback control from your app: `trigger`, `cancel`, `restart`, `isCancelled`
- 🔁 Looping or play-once, switchable at runtime
- 🎯 Editor mode: select, drag, and scrub live against a running build
- 📐 Alignment guides while dragging, on SwiftUI and Compose
- 🔺 Vertex shapes authored behind a view, rendered with Metal (SwiftUI), GLES (Compose)
  and WebGL (React)
- 📦 One `.inertia` project folder per app, versioned alongside your source

## Installation

### SwiftUI

In Xcode: **File → Add Package Dependencies…** and enter
`https://github.com/hpennington/Inertia`. Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hpennington/Inertia", branch: "main")
],
targets: [
    .target(name: "MyApp", dependencies: ["Inertia"])
]
```

Requires **iOS 17+ / macOS 14+** and Swift 5.9+. The iOS 17 floor is `KeyframeAnimator`.

Add an `animation.inertia` containing `[]` to your target's **Copy Bundle Resources** — the
container reads it by `id` at init and traps if it is missing. Then add `-D INERTIA_EDITOR`
to **Other Swift Flags** for the configuration you want to edit in.

### Jetpack Compose

The runtime is published through JitPack:

**`settings.gradle.kts`**

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

**`app/build.gradle.kts`**

```kotlin
dependencies {
    implementation("com.github.hpennington:inertia-compose:v1.6.0")
}
```

Requires `minSdk` 26 and Kotlin 2.0+ / JVM 17. The runtime dials the editor over plain
`ws://`, so grant `android.permission.INTERNET` and permit cleartext to `127.0.0.1`,
`localhost`, and `10.0.2.2` in a `network_security_config.xml` — preferably from a `debug`
source set. See [Installation](https://hpennington.github.io/Inertia/getting-started/installation/).

### React

The runtime is published to npm as two packages — `inertia-base` is the framework-agnostic
core, `inertia-react` the bindings on top of it. Installing the latter pulls in the former:

```sh
npm install inertia-react
```

**`package.json`**

```json
{
  "dependencies": {
    "inertia-react": "^0.5.0"
  }
}
```

To work against local checkouts instead — building both out of this repository — run
`./scripts/build_react.sh` and point the dependency at the directory with
`"inertia-react": "file:../path/to/runtime-web/inertia-react"`.

React 18.3.1 is a **peer** dependency, so your app supplies it — a second copy of React
resolving inside the package breaks hooks.

## Usage

Three pieces on every runtime: a **container** that owns the animation data and measures
the box `translate` is resolved against, an **actionable** wrapping each view you want to
move, and a **playback handle** for starting it.

### SwiftUI

```swift
import SwiftUI
import Inertia

struct AppEnvironment {
    #if INERTIA_EDITOR
    static let isInertiaEditor = true
    #else
    static let isInertiaEditor = false
    #endif
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            InertiaContainer(
                dev: AppEnvironment.isInertiaEditor, // editor mode when built with -D INERTIA_EDITOR
                id: "animation",                     // reads animation.inertia from the bundle
                hierarchyId: "animation"             // this container's node in the hierarchy
            ) {
                ContentView()
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.inertiaDataModel) private var inertia: InertiaDataModel!

    var body: some View {
        VStack(spacing: 16) {
            Card(title: "Welcome", subtitle: "Tap trigger to animate.")
                .inertia("card0")   // tag the view with an animation id

            Card(title: "Second Card", subtitle: "Same animation, own state.")
                .inertia("card1")

            Button("Trigger") {
                inertia.restart("card0")
                inertia.restart("card1")
            }
        }
        .onAppear { inertia.isRepeating = false }   // play once and hold
        .padding()
    }
}
```

`.inertiaContainer(dev:id:hierarchyId:)` is available as a modifier if you would rather not
nest.

### Jetpack Compose

```kotlin
import org.inertiagraphics.inertia.InertiaContainer
import org.inertiagraphics.inertia.Inertia
import org.inertiagraphics.inertia.LocalInertia

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                InertiaContainer(
                    dev = true,
                    id = "animation",
                    hierarchyId = "animation",
                    baseURL = "ws://127.0.0.1:8070"  // the editor, through `adb reverse`
                ) {
                    DemoApp()
                }
            }
        }
    }
}

@Composable
fun DemoApp() {
    val inertia = LocalInertia.current

    LaunchedEffect(inertia) { inertia.isRepeating = false }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Inertia(id = "card0") {
            DemoCard(title = "Welcome", subtitle = "Tap trigger to animate.")
        }
        Inertia(id = "card1") {
            DemoCard(title = "Second Card", subtitle = "Same animation, own state.")
        }
        Button(onClick = {
            inertia.restart("card0")
            inertia.restart("card1")
        }) {
            Text("Trigger")
        }
    }
}
```

### React

```tsx
import { InertiaContainer, Inertia, useInertia } from "inertia-react";

const isDev = process.env.REACT_APP_INERTIA_DEV !== "false";
const baseURL = process.env.REACT_APP_INERTIA_BASE_URL ?? "http://localhost:8000";

function DemoApp() {
  const inertia = useInertia();

  React.useEffect(() => {
    inertia.isRepeating = false;
  }, [inertia]);

  return (
    <div>
      <Inertia id="card0">
        <Card title="Welcome" subtitle="Tap trigger to animate." />
      </Inertia>

      <Inertia id="card1">
        <Card title="Second Card" subtitle="Same animation, own state." />
      </Inertia>

      <button
        onClick={() => {
          inertia.trigger("card0");
          inertia.trigger("card1");
        }}
      >
        Trigger
      </button>
    </div>
  );
}

export default function App() {
  return (
    <InertiaContainer id="animation" baseURL={baseURL} dev={isDev}>
      <DemoApp />
    </InertiaContainer>
  );
}
```

Outside editor mode the React container fetches `<baseURL>/<id>.inertia` over HTTP, so
something has to serve the editor's animations directory with CORS headers. The repository
ships `example/demo.inertia/animations/serve_animations.py` for exactly that. In editor
mode the socket is dialed at `ws://127.0.0.1:8080` regardless of `baseURL`.

### Shapes

Vertex shapes are authored in the editor against an actionable and travel in that
animation's `shapes` array, so there is no shape API to call from your app — tagging the
view is the whole of it. A card whose animation carries shapes draws them the moment the
schema arrives:

```kotlin
Inertia(id = "card0") {          // shapes authored behind "card0" render here
    DemoCard(title = "Welcome", subtitle = "Tap trigger to animate.")
}
```

On Compose those shapes go through **OpenGL ES 2.0**. The runtime creates its own EGL
context and draws the flattened triangle list into a `TextureView` behind the actionable's
content — a `TextureView` rather than a `GLSurfaceView` because a `SurfaceView` composites
in its own window layer, either behind the whole app or on top of every Compose view,
neither of which is a backdrop. Drawing is on demand: the vertex buffer is rebuilt only
when the schema or the layout changes, and the animation moves the surface as a layer
rather than redrawing it per frame.

Nothing has to be enabled for this. GLES 2.0 is present on every device at `minSdk` 26,
`TextureView` needs hardware acceleration, which is on by default, and no permission or
manifest entry is involved. If the context cannot be created the runtime logs through
`InertiaLog` and the views still animate — you lose the shapes, not the app.

Two kinds of shape come out of the editor, on Compose as on the other runtimes:

| | Where it is drawn | How it moves |
| --- | --- | --- |
| Backdrop (no `animation`) | Behind the actionable, in one canvas | Carried by the actionable's own transforms |
| Drawn shape (own `animation`) | Its own canvas, in authoring order | Its own track, stacked on the actionable's |

A shape's coordinates are multiples of the actionable — `(0, 0)` its top-left, `(1, 1)` its
bottom-right — and nothing clips them to that box, so a shape three times the size of the
card it backs is authored simply by saying `3`. The canvas is sized to the shapes rather
than to the view, and measured as zero-sized, so an oversized backdrop never grows the
layout it sits behind.

One difference worth knowing: a drawn shape shares the actionable's clock but not its
`invokeType`. A shape animation marked `"auto"` starts as soon as the clock runs, even
while the actionable it backs is still waiting on your `trigger` call.

## API, side by side

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| Import | `import Inertia` | `org.inertiagraphics.inertia` | `from "inertia-react"` |
| Container | `InertiaContainer(dev:id:hierarchyId:)` | `InertiaContainer(dev, id, hierarchyId, baseURL)` | `<InertiaContainer dev id hierarchyId baseURL>` |
| Tag a view | `.inertia("card0")` | `Inertia(id = "card0") { … }` | `<Inertia id="card0">` |
| Playback handle | `@Environment(\.inertiaDataModel)` | `LocalInertia.current` | `useInertia()` |
| Start | `trigger(_:)` | `trigger(…)` | `trigger(…)` |
| Stop / rewind | `cancel(_:)`, `restart(_:)` | `cancel`, `restart` | `cancel`, `restart` |
| Query | `isCancelled(_:)` | `isCancelled` | `isCancelled` |
| Looping | `isRepeating` | `isRepeating` | `isRepeating` |
| Loop length | `loopDuration` | `loopDuration` | `loopDuration` |
| Playhead (read-only) | `playheadTime`, `seekTime` | `playheadTime`, `seekTime` | `playheadTime`, `seekTime` |
| Constants | `InertiaPlayback` | `InertiaPlayback` | `InertiaPlayback` |
| Editor port | 8060 | 8070 | 8080 |

`trigger` starts an animation whose `invokeType` is `"trigger"`; one arriving mid-run joins
the run in progress rather than cutting it short. `restart` is the one that starts over —
and because every actionable in a container is drawn from one clock, it rewinds all of
them. `cancel` returns an animation to its initial values and leaves it there until
`restart`.

## Animation file format

The editor writes an array of animation objects, one per tagged id:

```json
[
  {
    "id": "card0",
    "initialValues": {
      "opacity": 1,
      "rotate": 0,
      "rotateCenter": 0,
      "scale": 1,
      "translate": [0, 0]
    },
    "invokeType": "trigger",
    "keyframes": [
      {
        "id": "1266F363-B284-4579-BED2-B12309243086",
        "duration": 0.001,
        "values": {
          "opacity": 1,
          "rotate": 0,
          "rotateCenter": 0,
          "scale": 0,
          "translate": [-0.0083, -0.2699]
        }
      },
      {
        "id": "9BA29E95-D9E3-4F21-B46A-723B3A1398A7",
        "duration": 2.011,
        "values": {
          "opacity": 1,
          "rotate": 90,
          "rotateCenter": 180,
          "scale": 1,
          "translate": [-0.0133, 0.2789]
        }
      }
    ],
    "shapes": []
  }
]
```

| Field | Meaning |
| --- | --- |
| `id` | Matches the id passed to `.inertia()` / `Inertia` |
| `initialValues` | The pose before anything runs, and where `cancel` returns to |
| `invokeType` | `"auto"` starts when the view appears; `"trigger"` waits for your call |
| `keyframes` | The track: each entry is a pose and how long to take reaching it |
| `duration` | Seconds for that keyframe's segment |
| `shapes` | Optional vertex geometry drawn behind the view — omit for none. Metal on SwiftUI, GLES on Compose, WebGL on React |

### Animatable values

| Value | Meaning |
| --- | --- |
| `translate` | `[x, y]` offset as a **fraction of the container's size**, so a track survives a resize |
| `scale` | Uniform scale factor (`1.0` unchanged) |
| `rotate` | Degrees, anchored top-left |
| `rotateCenter` | Degrees, anchored at the view's center |
| `opacity` | `0.0` transparent through `1.0` opaque |

### Shape objects

An entry in `shapes` is either a ring of corners or a described vector, and may carry a
track of its own:

```json
"shapes": [
  {
    "shape": {
      "id": "…",
      "type": "rectangle",
      "width": 0.5,
      "height": 0.5,
      "fill": { "red": 0.2, "green": 0.4, "blue": 0.9, "alpha": 1 },
      "stroke": { "red": 1, "green": 1, "blue": 1, "alpha": 1 },
      "strokeWidth": 0.02
    },
    "animation": null
  },
  {
    "vertices": [
      { "position": { "x": 0, "y": 0 }, "color": { "red": 1, "green": 0, "blue": 0.5, "alpha": 1 } }
    ],
    "animation": { "id": "…", "invokeType": "auto", "keyframes": [] }
  }
]
```

| Field | Meaning |
| --- | --- |
| `vertices` | Corners as authored: `position` in multiples of the actionable, `color` in 0–1 RGBA |
| `shape` | A described vector instead — `type` is `rectangle`, `square`, `circle`, `oval`, or `triangle`, sized in the same multiples |
| `shape.fill` | The colour flooding the outline, 0–1 RGBA. Omit for a shape that is only its outline |
| `shape.stroke` | The colour of the outline itself, 0–1 RGBA. Omit for a shape that is only its area |
| `shape.strokeWidth` | Outline thickness, in the same multiples of the actionable the shape is sized in. Drawn *inside* the outline, so a stroke never grows the shape's box. Defaults to `0`, which is no outline |
| `animation` | A track for this shape alone. Omitted or `null` makes it a backdrop moved by the actionable |

## Editor mode vs. release

In **editor mode** (`dev: true`) the app connects to the editor's local WebSocket server,
reports its Inertia-tagged view hierarchy, and receives schemas as you edit. Tagged views
become selectable and draggable, and all three runtimes follow the editor's playhead —
pause, resume, seek, loop duration — and report their position back so the timeline tracks
a running animation.

In **release mode** none of that runs. The container loads the animation for itself and
plays it on its own clock: from the app bundle on SwiftUI, from `assets/` on Compose, over
HTTP on React.

## Known differences between runtimes

The runtimes are deliberately parallel, but they are not at the same level of maturity.

- **SwiftUI is strict about the bundled file.** With `dev: false` the container reads the
  resource during init and traps if it is missing or fails to decode. `[]` is valid; absent
  is a crash. Compose and React log an error and leave the views at their layout
  positions instead.
- **Interpolation differs.** SwiftUI fits a cubic spline across the whole track, so motion
  can overshoot a keyframe on the way to the next. Compose and React solve each segment
  with a cubic ease-in-out, which never overshoots. The poses at the keyframes are
  identical; the paths between them are not.
- **Shape rendering is per-platform.** SwiftUI draws through Metal, Compose through
  OpenGL ES 2.0, React through WebGL. The vertices and colours are the same on all three —
  fills and strokes included, down to the corner — but the compositing is each platform's
  own.
- **The editor installs and launches builds on the iOS Simulator only.** On Android and web
  you launch the app yourself; everything after that is the same.

[Choosing a runtime](https://hpennington.github.io/Inertia/getting-started/runtimes/) has
the full comparison.

## Documentation

- [Installation](https://hpennington.github.io/Inertia/getting-started/installation/) — add a runtime to your app
- [Quickstart](https://hpennington.github.io/Inertia/getting-started/quickstart/) — get a view moving
- [Choosing a runtime](https://hpennington.github.io/Inertia/getting-started/runtimes/) — where they differ
- [Editor tour](https://hpennington.github.io/Inertia/editor/overview/) — recording keyframes against a live app
- [Animation file format](https://hpennington.github.io/Inertia/guides/animation-file/) — what the editor writes

## Status

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| Author in the editor | ✅ | ✅ | ✅ |
| Ship the result | ✅ (bundle the JSON) | ✅ (`assets/`) | ✅ (serve the JSON) |
| Shape rendering | ✅ Metal | ✅ GLES 2.0 | ✅ WebGL |
| Distribution | Swift Package Manager | JitPack | build from source |

All three expose the same API and ship the same animation file. The SwiftUI runtime is the
one kept most current — it is where new work lands first, and its cubic-spline
interpolation is the reference the other two approximate.

---

*Inertia Team • 2025*
