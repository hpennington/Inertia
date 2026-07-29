# Installation

## Requirements

| | |
| --- | --- |
| App target | iOS 17+ (or macOS 14+) |
| Editor | macOS, with Xcode command line tools installed (`xcrun simctl`) |
| Language | Swift 5.9+ / SwiftUI |

The iOS 17 floor is not arbitrary: the runtime plays your tracks through SwiftUI's
`KeyframeAnimator`, which is an iOS 17 API.

## Add the Swift package

In Xcode, choose **File → Add Package Dependencies…** and enter:

```
https://github.com/hpennington/Inertia
```

Add the `Inertia` library product to your app target.

Or declare it in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hpennington/Inertia", branch: "main")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: ["Inertia"]
    )
]
```

Then import it wherever you use it:

```swift
import Inertia
```

## Add the animation file to your target

The runtime loads animations from a JSON resource in your app bundle, looked up by the
container's `id`. A container created with `id: "animation"` reads `animation.json`.

1. Create an empty `animation.json` next to your Swift sources containing `[]`.
2. Drag it into your Xcode project.
3. Confirm it appears under **Target → Build Phases → Copy Bundle Resources**.

!!! warning "The file is required in release builds"

    Outside editor mode, `InertiaContainer` reads this resource during
    initialization and traps if it is missing or fails to decode. An empty
    array is a valid animation file; a missing file is not.

Once the editor is writing animations for this project, you copy its `animation.json`
over this one. See [Projects](../editor/projects.md) for where the editor keeps it.

## Add the editor build flag

Editor mode should be compiled in for development builds only. The convention used by
the example app is a `INERTIA_EDITOR` Swift flag on a dedicated scheme or build
configuration:

1. Select your target → **Build Settings**.
2. Find **Other Swift Flags** (`OTHER_SWIFT_FLAGS`).
3. For the configuration you want to edit in, add `-D INERTIA_EDITOR`.

Then read it in one place:

```swift
struct AppEnvironment {
    #if INERTIA_EDITOR
    static let isInertiaEditor = true
    #else
    static let isInertiaEditor = false
    #endif
}
```

The next page wires this into your root view.

## Next

- [Quickstart](quickstart.md) — get a view animating.
- [Editor mode](editor-mode.md) — connect a running app to the editor.
