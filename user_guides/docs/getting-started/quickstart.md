# Quickstart

This walks through the three pieces every Inertia app has: a container, one or more
tagged views, and an animation file.

## 1. Wrap your root view in a container

The container is the coordinate space animations are measured against, and the owner of
the animation data. Put it at the root of your app.

=== "SwiftUI"

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
    struct MyApp: App {
        var body: some Scene {
            WindowGroup {
                InertiaContainer(
                    dev: AppEnvironment.isInertiaEditor,  // (1)!
                    id: "animation",                      // (2)!
                    hierarchyId: "animation"              // (3)!
                ) {
                    ContentView()
                }
            }
        }
    }
    ```

    1. `true` connects to the editor and takes animations from it. `false` loads them from
       the bundle. Drive it from a build flag rather than hardcoding it — see
       [Installation](installation.md).
    2. The animation file's name without its extension. `"animation"` loads
       `animation.json` from the bundle. Keep this as `"animation"` — it doubles as the
       container id the editor sends animations to.
    3. The root node's id in the view hierarchy the editor draws. Any stable string works.

    There is also a modifier form, if you prefer it:

    ```swift
    ContentView()
        .inertiaContainer(dev: AppEnvironment.isInertiaEditor, id: "animation", hierarchyId: "animation")
    ```

=== "Compose"

    ```kotlin
    import org.inertiagraphics.inertia.InertiaContainer

    class MainActivity : ComponentActivity() {
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            setContent {
                MaterialTheme {
                    InertiaContainer(
                        dev = true,                       // (1)!
                        id = "animation",                 // (2)!
                        hierarchyId = "animation",        // (3)!
                        baseURL = "ws://127.0.0.1:8070"   // (4)!
                    ) {
                        DemoApp()
                    }
                }
            }
        }
    }
    ```

    1. `true` takes animations from the editor over the socket; `false` reads
       `assets/animation.json` and never opens one. Wire it to your own build flag.
    2. The container id the editor addresses its schemas to. Keep it as `"animation"` —
       the runtime drops schemas meant for any other container.
    3. The id of the container's own node, which every actionable inside it hangs from.
       Usually the same string as `id`.
    4. Where the editor is listening. `127.0.0.1:8070` works from an emulator because the
       editor opens an `adb reverse` tunnel for that port; a physical device wants the
       Mac's address on the local network instead.

    !!! note "The container fills the space it is given"

        `InertiaContainer` measures itself with `fillMaxSize()`, so it is as big as its
        host lets it be — the same rectangle the SwiftUI and React containers occupy.
        Since `translate` is a fraction of that box, don't nest the container inside
        something that constrains it, or every offset in it resolves against a smaller box
        than the one you authored against.

=== "React"

    ```tsx
    import { InertiaContainer } from "inertia-react";

    const isDev = process.env.REACT_APP_INERTIA_DEV !== "false";
    const baseURL = process.env.REACT_APP_INERTIA_BASE_URL ?? "http://localhost:8000";

    export default function App() {
      return (
        <InertiaContainer
          id="animation"      /* (1)! */
          baseURL={baseURL}   /* (2)! */
          dev={isDev}         /* (3)! */
        >
          <DemoContent />
        </InertiaContainer>
      );
    }
    ```

    1. The container id the editor addresses its schemas to, and the basename of the JSON
       file fetched outside editor mode. Keep it as `"animation"`.
    2. Where `<id>.json` is served from when `dev` is false. It is **not** the editor's
       address — the editor connection is always `ws://127.0.0.1:8080`.
    3. `true` takes animations from the editor over the socket; `false` fetches them from
       `baseURL` and never opens a socket.

## 2. Tag the views you want to animate

Wrap each view you want to move, with an id. That id is how a view and an animation track
find each other, in the editor and at runtime.

=== "SwiftUI"

    ```swift
    struct ContentView: View {
        var body: some View {
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue)
                    .frame(width: 200, height: 120)
                    .overlay { Text("Card").foregroundStyle(.white) }
                    .inertia("card0")

                Image(systemName: "airplane")
                    .font(.largeTitle)
                    .inertia("plane")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    ```

    Order matters: `.inertia(_:)` wraps whatever it is applied to, so put it after the
    modifiers that define the view's appearance and size, the way you would with
    `.frame` or `.background`.

=== "Compose"

    ```kotlin
    import org.inertiagraphics.inertia.Inertia

    @Composable
    fun DemoApp() {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Inertia(id = "card0") {
                Box(
                    Modifier
                        .size(200.dp, 120.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.Blue)
                )
            }

            Inertia(id = "plane") {
                Text("✈", fontSize = 34.sp)
            }
        }
    }
    ```

    `Inertia` puts its content in a `Box` and animates that box, so it takes the size
    of what you give it. Size and shape the content, not the wrapper.

=== "React"

    ```tsx
    import { Inertia } from "inertia-react";

    function DemoContent() {
      return (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <Inertia id="card0">
            <div style={{ width: 200, height: 120, borderRadius: 12, background: "blue" }} />
          </Inertia>

          <Inertia id="plane">
            <span style={{ fontSize: 34 }}>✈</span>
          </Inertia>
        </div>
      );
    }
    ```

    `Inertia` renders an `inline-block` wrapper `div` around its child and writes the
    transform onto that wrapper. It takes a single child element.

!!! tip "Keeping ids organized"

    Plain strings are fine, but a shared constant keeps the two ends honest:

    === "SwiftUI"

        ```swift
        enum AnimationID: String, CaseIterable {
            case card0, plane
        }

        // .inertia(AnimationID.card0.rawValue)
        ```

    === "Compose"

        ```kotlin
        object AnimationID {
            const val CARD0 = "card0"
            const val PLANE = "plane"
        }

        // Inertia(id = AnimationID.CARD0) { … }
        ```

    === "React"

        ```ts
        export const AnimationID = {
          card0: "card0",
          plane: "plane",
        } as const;

        // <Inertia id={AnimationID.card0}>
        ```

    See [Animation IDs](../guides/ids.md) for how ids behave when a tagged view
    appears more than once.

## 3. Give it an animation

Animations normally come from the editor, but the file is plain JSON and hand-writing
one is a good way to see the shape of it. This moves `card0` from left of center to
center over three seconds:

```json title="animation.json"
[
  {
    "id": "card0",
    "invokeType": "trigger",
    "initialValues": {
      "scale": 1,
      "translate": [0, 0],
      "rotate": 0,
      "rotateCenter": 0,
      "opacity": 1
    },
    "keyframes": [
      {
        "id": "1A9DA10A-9E90-49B6-943B-D10756FA3C2C",
        "duration": 0,
        "values": {
          "scale": 1,
          "translate": [-0.5, 0],
          "rotate": 0,
          "rotateCenter": 0,
          "opacity": 1
        }
      },
      {
        "id": "F5F9E292-E987-442C-89CC-C2CB09B56971",
        "duration": 3,
        "values": {
          "scale": 1,
          "translate": [0, 0],
          "rotate": 0,
          "rotateCenter": 0,
          "opacity": 1
        }
      }
    ]
  }
]
```

Two things about that file worth knowing up front:

- **`duration` is relative.** It is how long the animation takes to reach *this*
  keyframe from the one before it. The first keyframe at `duration: 0` is a starting
  pose, not a wait.
- **`translate` is normalized.** `-0.5` is half the container's width to the left, not
  half a point. That is what makes one animation file work across device sizes.

Where that file lives depends on the runtime: the app bundle for SwiftUI, an HTTP server
for React. The Compose runtime only ever receives animations from the editor over the
socket, so there is nothing to place — connect the editor instead.

## 4. Trigger it

Nothing animates until its id is triggered. Reach the container's playback handle and ask
for it:

=== "SwiftUI"

    ```swift
    struct ContentView: View {
        @Environment(\.inertiaDataModel) private var inertia: InertiaDataModel!

        var body: some View {
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue)
                    .frame(width: 200, height: 120)
                    .inertia("card0")

                Button("Animate") {
                    inertia.trigger("card0")
                }
            }
        }
    }
    ```

    The environment value is only populated inside an `InertiaContainer`.

=== "Compose"

    ```kotlin
    import org.inertiagraphics.inertia.LocalInertia

    @Composable
    fun DemoApp() {
        val inertia = LocalInertia.current

        Column {
            Inertia(id = "card0") { /* … */ }

            Button(onClick = { inertia.trigger("card0") }) {
                Text("Animate")
            }
        }
    }
    ```

    `LocalInertia` throws if it is read outside an `InertiaContainer`. Compose also gives
    you `restart("card0")`, which rewinds the playhead and plays from the top — that is
    what you usually want behind a button that can be pressed twice.

=== "React"

    ```tsx
    import { useInertia } from "inertia-react";

    function DemoContent() {
      const inertia = useInertia();

      return (
        <>
          <Inertia id="card0">
            <div style={{ width: 200, height: 120, background: "blue" }} />
          </Inertia>

          <button onClick={() => inertia.trigger("card0")}>Animate</button>
        </>
      );
    }
    ```

    `useInertia` throws if it is called outside an `InertiaContainer`. React also gives you
    `restart("card0")`, which rewinds the playhead and plays from the top — that is what
    you usually want behind a button that can be pressed twice.

Build and run, press **Animate**, and the card slides in.

To play on appear, call `trigger` from `onAppear` / `LaunchedEffect` / `useEffect` — the
`invokeType` field in the file does not do this for you on every runtime. See
[Triggering animations](../guides/triggering.md).

## Next

You now have the runtime side working. The editor is what makes authoring these tracks
bearable — see [Editor mode](editor-mode.md).
