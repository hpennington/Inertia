# Compose API

Everything on this page comes from the `org.inertiagraphics.inertia` package, published as
`com.github.hpennington:inertia-compose` through JitPack.

## `InertiaContainer`

The root of an Inertia hierarchy. It owns the animation data, defines the box `translate`
values are measured against, holds the editor connection, and drives the clock every
actionable inside it samples.

```kotlin
@Composable
fun InertiaContainer(
    id: String,
    baseURL: String,
    dev: Boolean = false,
    content: @Composable () -> Unit
)
```

| Parameter | Meaning |
| --- | --- |
| `id` | The container id the editor addresses its schemas to. Schemas for any other container are dropped. |
| `baseURL` | The editor's WebSocket address, passed through as given — `ws://127.0.0.1:8070` from an emulator. |
| `dev` | **Accepted and not read.** See the warning below. |

```kotlin
InertiaContainer(id = "animation", baseURL = "ws://127.0.0.1:8070", dev = true) {
    DemoApp()
}
```

!!! warning "`dev` has no effect"

    The container connects to `baseURL` unconditionally and has no path that loads an
    animation file for itself. There is nothing for a build without an editor to play, and
    it will keep retrying the dial. Keep the container out of release builds yourself —
    see [Choosing a runtime](../getting-started/runtimes.md).

!!! warning "The editor only addresses the container id `animation`"

    The editor sends every schema against the container id `"animation"`, and the runtime
    drops any schema whose container id does not match its own. Use `id = "animation"` for
    any container you intend to author in the editor.

The container measures itself with `wrapContentSize()`, so it is as large as its content.
Since `translate` is a fraction of the container's size, give it content that fills the
screen unless you specifically want a smaller coordinate space.

## `Inertiaable`

```kotlin
@Composable
fun Inertiaable(
    hierarchyIdPrefix: String,
    content: @Composable () -> Unit
)
```

Wraps one composable and animates it under the given id.

```kotlin
Inertiaable(hierarchyIdPrefix = "card0") {
    Box(Modifier.size(200.dp, 120.dp).background(Color.Blue))
}
```

`hierarchyIdPrefix` is the id you look up in the animation file and pass to `trigger`. Each
*instance* of the composable claims a distinct hierarchy id by appending an index
(`card0--0`, `card0--1`), which is what lets the editor tell copies apart — see
[Animation IDs](../guides/ids.md).

The wrapper is a `Box`, so it takes the size of what you put in it. It applies the
animation through three chained `graphicsLayer` blocks — offset, `rotateCenter` and opacity
on the outside, then `rotate` about the top-left, then `scale` — which composes the same
matrix the SwiftUI runtime does for the same schema.

In editor mode (`isActionable`, set by the editor) it also handles taps for selection,
drags that record translation, and draws the selection border.

## `LocalInertia`

```kotlin
val LocalInertia: ProvidableCompositionLocal<InertiaPlayback>
```

The playback handle for the enclosing container.

```kotlin
val inertia = LocalInertia.current
```

It has no default — reading it outside an `InertiaContainer` throws
*"LocalInertia was read outside of an InertiaContainer."*

## `InertiaPlayback`

The clock every actionable in a container is drawn from, and the app's controls over it.
Keyed by `hierarchyIdPrefix`, so starting an id starts every instance sharing it.

### App-facing controls

```kotlin
fun trigger(hierarchyIdPrefix: String)
fun cancel(hierarchyIdPrefix: String)
fun restart(hierarchyIdPrefix: String)
fun isCancelled(hierarchyIdPrefix: String): Boolean
```

- **`trigger`** starts an animation that was waiting on its `trigger` invoke type. Arriving
  mid-run it joins the run in progress rather than cutting it short. A cancelled animation
  is left where it is.
- **`cancel`** stops an animation and returns it to its `initialValues`, where it stays
  until `restart`. Cancelling the last running animation stops the clock.
- **`restart`** clears a cancellation and plays from the top of the timeline. Because every
  actionable in a container shares one clock, this rewinds the playhead for all of them.

### State

```kotlin
var isRepeating: Boolean                       // default true
val loopDuration: Float                        // read-only; set by the editor
val playbackDuration: Float                    // max(loopDuration, longest track)
val playheadTime: Float                        // read-only, seconds into the run
val isRunning: Boolean                         // read-only
val seekTime: Float?                           // read-only; non-null while parked
```

`isRepeating` is the one an app usually sets. With it off, each track plays its own
keyframes once and holds its final pose:

```kotlin
LaunchedEffect(inertia) {
    inertia.isRepeating = false
}
```

`loopDuration` is read-only to the app — it starts at the default and changes only when the
editor sends a new timeline length.

## `InertiaPlaybackDefaults`

```kotlin
object InertiaPlaybackDefaults {
    val defaultLoopDuration: Float
    fun clampLoopDuration(seconds: Float): Float
}
```

The same constants the editor clamps its timeline to.

## Data types

The schema types are `kotlinx.serialization` data classes matching the file format:

```kotlin
@Serializable
data class InertiaAnimationSchema(
    val id: String,
    val initialValues: InertiaAnimationValues = InertiaAnimationValues(),
    val invokeType: InertiaAnimationInvokeType,   // trigger | auto
    val keyframes: List<InertiaAnimationKeyframe> = emptyList()
)

@Serializable
data class InertiaAnimationKeyframe(
    val id: String,
    val values: InertiaAnimationValues,
    val duration: Float   // seconds since the previous keyframe
)

@Serializable
data class InertiaAnimationValues(
    val scale: Float = 1.0f,
    val translate: List<Float> = listOf(0.0f, 0.0f),  // [x, y], fraction of the container
    val rotate: Float = 0.0f,
    val rotateCenter: Float = 0.0f,
    val opacity: Float = 1.0f
)
```

Note that `translate` is a `List<Float>` rather than a pair, to match the JSON array in the
file. See [Animatable values](values.md).

## Logging

```kotlin
object InertiaLog {
    var isEnabled: Boolean   // true by default
}
```

Traces the path a schema takes from the socket to the screen, under the `Inertia` tag:

```sh
adb logcat -s Inertia
```

Set `InertiaLog.isEnabled = false` to silence it.

## Types you are unlikely to need

`Tree`, `Node`, `WebSocketClient`, `MessageSchema`, `InertiaSchemaWrapper`,
`AnimationSignal` and the other message types are public because the editor talks to them
over the wire. They are part of the editor protocol rather than the app-facing API.

`InertiaShape` and `InertiaObjectType` are remnants of an earlier shape-based model that
the keyframe model replaced; nothing decodes into them any more.

`getHostForWebSocket()`, `isValidIPv4()` and `getFirstDnsIP()` are host-discovery helpers
that shell out to `ip route`. Nothing in the runtime calls them — `baseURL` is passed
through as given.
