# Triggering animations

An Inertia animation does not start on its own. The runtime plays a view's track once two
things are true: the container's clock is running, and that view's id has been triggered.
Both come from one call.

## Triggering from your app

Reach the container's data model through the environment and call `trigger(_:)` with the
same id you passed to `.inertia(_:)`:

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

The environment value is only populated inside an `InertiaContainer` — it is `nil`
anywhere else, which is why the force-unwrapped type above is safe in practice and
crashes loudly if you put the view outside a container.

## Playing on appear

There is no declarative "play on appear". Trigger it yourself:

```swift
RoundedRectangle(cornerRadius: 12)
    .inertia("card0")
    .onAppear { inertia.trigger("card0") }
```

!!! note "`invokeType` in the file"

    Animation files carry an `invokeType` of `"auto"` or `"trigger"`. The SwiftUI runtime
    stores it but does not currently act on it: a track with `"auto"` still waits for
    `trigger(_:)`. Treat the field as metadata the editor round-trips, and drive playback
    from your own code.

## Triggering several views together

Each id is triggered separately, but they share one clock, so triggering them in the same
turn of the run loop starts them together:

```swift
Button("Animate all") {
    inertia.trigger("card0")
    inertia.trigger("card1")
    inertia.trigger("plane")
}
```

Every track is padded to the loop length, so tracks of different lengths still restart in
step with each other.

## Repeating

Animations repeat by default. Turn it off on the data model:

```swift
inertia.isRepeating = false
inertia.trigger("card0")
```

With repeating off, each track plays its own keyframes once and stops on its final pose.
With it on, tracks are held out to the full loop duration and start over together.

## Loop duration

```swift
inertia.loopDuration = 1.5   // seconds, clamped to 0.1...60
```

`InertiaPlayback` exposes the same constants the editor uses:

```swift
InertiaPlayback.defaultLoopDuration   // 3.0
InertiaPlayback.loopDurationRange     // 0.1...60.0
InertiaPlayback.clampLoopDuration(_:) // brings a value into range
```

## What triggering does not do

`trigger(_:)` sets a view's track running and starts the container's clock. It does not
reset a track that is already playing, and there is no public "stop this one view" on the
data model. If you need a view to be able to restart from the beginning, structure it so
the view is removed and re-added, or keep the animation on a track short enough that the
loop does the work.
