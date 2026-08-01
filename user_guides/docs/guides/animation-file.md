# Animation files

An animation file is a JSON array of animation objects, one per animated view. The editor
writes it, and every runtime reads the same format — from the app bundle in SwiftUI, over
HTTP in React, and over the editor's socket in all three.

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
          "translate": [-0.648, -0.003],
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
          "translate": [0.008, -0.012],
          "rotate": 0,
          "rotateCenter": 0,
          "opacity": 1
        }
      }
    ]
  }
]
```

## Animation object

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Matches the id the animated view was tagged with — `.inertia("card0")`, `Inertiaable(hierarchyIdPrefix = "card0")`, `<Inertiaable hierarchyIdPrefix="card0">`. |
| `initialValues` | object | The pose the view sits at before the animation runs. |
| `invokeType` | `"auto"` \| `"trigger"` | Whether it plays as soon as its schema arrives, or waits to be triggered. |
| `keyframes` | array | The poses to animate through, in order. |

!!! note "`invokeType` is not honoured on every runtime"

    Compose and React start an `"auto"` animation as soon as they hold its schema. The
    SwiftUI runtime stores the field and ignores it — an `"auto"` track on iOS still waits
    for `trigger(_:)`. See [Triggering animations](triggering.md).

## Keyframe object

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Unique within the track. The editor writes UUIDs. |
| `duration` | number | Seconds to reach *this* keyframe from the previous one. |
| `values` | object | The pose at this keyframe. |

### `duration` is relative

This is the part of the format that surprises people. `duration` is not a timestamp and
not the length of the whole animation — it is the time taken to travel from the preceding
keyframe to this one.

So a track with durations `0, 1, 2` has keyframes at absolute times 0s, 1s, and 3s.

![Three keyframes with durations 0, 1 and 2 land at 0s, 1s and 3s, because each duration is the travel time from the keyframe before it.](../assets/diagrams/keyframe-durations-dark.svg){ .diagram }

A leading keyframe with `duration: 0` is therefore a starting pose that takes no time to
reach, not a keyframe that waits.

!!! note "Non-positive durations are repaired, not honoured"

    Interpolation divides by the keyframe's duration, so the runtime rewrites any
    duration that is zero, negative or non-finite to 1ms before playing the track. That
    keeps a hand-edited file from producing `NaN` and a view that vanishes, but the
    keyframe reads as an instant jump, and every keyframe after it lands 1ms later than
    the file implies. The editor keeps its own durations above the same minimum.

    A leading keyframe at `duration: 0` is the normal case and behaves as intended: the
    view is at its starting pose 1ms in, which is not something you can see.

### `values`

Every keyframe carries all five values — there is no notion of animating only one
property and leaving the others alone. See [Animatable values](../reference/values.md).

## Loop length

The file does not record how long the loop is. At runtime the loop is

```
max(loopDuration, longest track in the file)
```

where `loopDuration` starts at the runtime default of 3 seconds and changes only when
the editor sends a new timeline length, or — on SwiftUI, which is the runtime that exposes
it to the app — when your app sets `inertia.loopDuration`. A track
shorter than the loop holds its final pose until the loop comes around; a track longer
than `loopDuration` stretches the loop for every track, so they all still restart
together.

![A 4-second track stretches the loop past the 3-second loopDuration, and a 2-second track holds its final pose for the remaining 2 seconds.](../assets/diagrams/loop-length-dark.svg){ .diagram }

So an animation authored on a 5-second timeline plays back over a 5-second loop only if
one of its tracks actually runs the full 5 seconds. If the longest ends at 4 seconds the
loop is 4 seconds; if it ends at 2 seconds the loop falls back to the 3-second default.
Either keep the editor's loop duration at 3 seconds, or set the loop duration in your app
to the length you authored against — which today only the SwiftUI runtime lets you do.

## Naming and lookup

The container's `id` is the file's name. One file holds every animation for that container.

=== "SwiftUI"

    `InertiaContainer(id: "animation", …)` loads `animation.json` from the app bundle.

    Outside editor mode the file must exist and must decode — the container reads it during
    initialization and **traps** if it cannot. An empty array is a valid file; a missing
    one is a crash.

=== "Compose"

    There is no lookup. The Compose container never loads an animation file for itself —
    schemas only ever arrive from the editor over the socket, addressed to the container
    id. See [Choosing a runtime](../getting-started/runtimes.md).

=== "React"

    `<InertiaContainer id="animation" baseURL="http://localhost:8000">` fetches
    `http://localhost:8000/animation.json`.

    A failed fetch is logged and otherwise ignored, so a missing file leaves every tagged
    view at its initial pose rather than crashing. The server needs CORS headers if it is
    not the same origin as your page.
