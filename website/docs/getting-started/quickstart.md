# Quickstart

This walks through the three pieces every Inertia app has: a container, one or more
tagged views, and an animation file.

## 1. Wrap your root view in a container

`InertiaContainer` is the coordinate space animations are measured against, and the
owner of the animation data. Put it at the root of your scene.

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
   [Installation](installation.md#add-the-editor-build-flag).
2. The animation file's name without its extension. `"animation"` loads
   `animation.json` from the bundle.
3. The root node's id in the view hierarchy the editor draws. Any stable string works.

There is also a modifier form, if you prefer it:

```swift
ContentView()
    .inertiaContainer(dev: AppEnvironment.isInertiaEditor, id: "animation", hierarchyId: "animation")
```

## 2. Tag the views you want to animate

Apply `.inertia(_:)` with an id. That id is how a view and an animation track find each
other, in the editor and at runtime.

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

!!! tip "Keeping ids organized"

    Plain strings are fine, but an enum keeps the two ends honest:

    ```swift
    enum AnimationID: String, CaseIterable {
        case card0, plane
    }

    // .inertia(AnimationID.card0.rawValue)
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

## 4. Trigger it

Nothing animates until its id is triggered. Reach the container's data model through the
environment and ask for it:

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

Build and run, tap **Animate**, and the card slides in.

The environment value is only populated inside an `InertiaContainer`. To play on appear,
call `trigger(_:)` from `.onAppear` — the `invokeType` field in the file does not do this
for you. See [Triggering animations](../guides/triggering.md).

## Next

You now have the runtime side working. The editor is what makes authoring these tracks
bearable — see [Editor mode](editor-mode.md).
