# Inertia

Inertia is a keyframe animation editor and SwiftUI runtime for animating the UI you
already built. You wire a modifier onto the views you want to move, run your app in
the editor, drag those views around on a timeline, and Inertia writes the result to a
JSON file that ships in your app bundle.

There is no separate rendering surface and no exported video. The thing you animate in
the editor is the real SwiftUI view, and at runtime it animates through SwiftUI's own
keyframe animation APIs.

<div class="grid cards" markdown>

- :material-download: **[Install the runtime](getting-started/installation.md)**

    Add the Swift package to your app and wrap your root view.

- :material-rocket-launch: **[Quickstart](getting-started/quickstart.md)**

    Get a view moving in about ten minutes.

- :material-timeline-clock: **[Use the editor](editor/overview.md)**

    Record keyframes against a live simulator.

- :material-code-json: **[Animation file format](guides/animation-file.md)**

    What the editor writes, and what the runtime reads.

</div>

## How it fits together

![The editor connects to your app over a local WebSocket, trades the view hierarchy for animation schemas, and writes the animation.json your shipped app bundles.](assets/diagrams/architecture-dark.svg){ .diagram }

In **editor mode** your app hosts a local WebSocket server and the editor connects to it.
The app reports its Inertia-tagged view hierarchy, and the editor pushes animation schemas
back as you edit, so what you see in the simulator is the animation as it currently
stands.

In **release mode** none of that is running. The container loads `animation.json` out of
your app bundle and plays it through SwiftUI's keyframe animator. The WebSocket server is
gated on the same `dev` flag, so a shipped build never opens a listening socket.

## What you can animate

Each tagged view gets a track of keyframes over five values:

| Value | Meaning |
| --- | --- |
| `translate` | `[x, y]` offset, as a fraction of the container's size |
| `scale` | Uniform scale factor (`1.0` is unchanged) |
| `rotate` | Rotation in degrees, anchored top-left |
| `rotateCenter` | Rotation in degrees, anchored at the view's center |
| `opacity` | `0.0` transparent through `1.0` opaque |

See [Animatable values](reference/values.md) for the details, including why `translate`
is normalized rather than in points.

## Platform support

Inertia's runtime is SwiftUI, targeting iOS 17 and later — the keyframe animation APIs
it builds on landed in iOS 17. The editor is a macOS app and drives the iOS Simulator
through `simctl`.

!!! note "Other platforms"

    There are React and Jetpack Compose runtimes in the repository, but they are not
    documented here. This site covers the SwiftUI path only.

## Where to go next

Start with [Installation](getting-started/installation.md) if you have an app you want to
animate. If you would rather read about the workflow before touching your project, the
[editor tour](editor/overview.md) is the shortest route to understanding what Inertia
actually does.
