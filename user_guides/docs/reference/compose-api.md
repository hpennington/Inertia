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
    dev: Boolean,
    id: String,
    hierarchyId: String,
    baseURL: String,
    content: @Composable () -> Unit
)
```

| Parameter | Meaning |
| --- | --- |
| `dev` | `true` takes animations from the editor over the socket; `false` reads `assets/<id>.inertia` and never opens a socket. |
| `id` | The container id the editor addresses its schemas to, and the basename of the asset read outside editor mode. Schemas for any other container are dropped. |
| `hierarchyId` | The id of the container's own node — the root every actionable inside it hangs from. Usually the same string as `id`. |
| `baseURL` | The editor's WebSocket address, passed through as given — `ws://10.0.2.2:8070` from a stock emulator, a LAN address from a device. |

```kotlin
InertiaContainer(
    dev = BuildConfig.INERTIA_EDITOR,
    id = "animation",
    hierarchyId = "animation",
    baseURL = "ws://127.0.0.1:8070"
) {
    DemoApp()
}
```

This is the same argument list the SwiftUI and React containers take, in the same order.
SwiftUI has no `baseURL` — it reads from a `Bundle` and reaches the editor at
`127.0.0.1:8060` — and on React `baseURL` is an HTTP origin rather than a socket.

!!! warning "The editor only addresses the container id `animation`"

    The editor sends every schema against the container id `"animation"`, and the runtime
    drops any schema whose container id does not match its own. Use `id = "animation"` for
    any container you intend to author in the editor.

### Where the animation comes from

With `dev` false the container reads `assets/<id>.inertia` and logs an error if the file is
missing or fails to decode — a broken animation leaves the actionables at their layout
positions rather than bringing the app down. Put the file the editor exported at
`app/src/main/assets/animation.inertia`.

With `dev` true it dials `baseURL` and takes its schemas from the editor. No socket is
opened when `dev` is false, so the container is safe to leave in a release build.

The container fills the space its host offers it (`fillMaxSize()`). Since `translate` is a
fraction of that box, this is the same rectangle SwiftUI's `GeometryReader` reports and the
React container's div occupies — which is what makes one animation file move the same
distance on all three.

## `Inertia`

```kotlin
@Composable
fun Inertia(
    id: String,
    content: @Composable () -> Unit
)
```

Wraps one composable and animates it under the given id.

```kotlin
Inertia(id = "card0") {
    Box(Modifier.size(200.dp, 120.dp).background(Color.Blue))
}
```

`id` is the id you look up in the animation file and the same id you pass to `trigger`.
Each *instance* of the composable claims a distinct hierarchy id by appending an index
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
val LocalInertia: ProvidableCompositionLocal<InertiaPlaybackController>
```

The playback handle for the enclosing container.

```kotlin
val inertia = LocalInertia.current
```

It has no default — reading it outside an `InertiaContainer` throws
*"LocalInertia was read outside of an InertiaContainer."*

## `InertiaPlaybackController`

The clock every actionable in a container is drawn from, and the app's controls over it.
Keyed by the `id` you gave `Inertia`, so starting an id starts every instance sharing it.

### App-facing controls

```kotlin
fun trigger(id: String)
fun cancel(id: String)
fun restart(id: String)
fun isCancelled(id: String): Boolean
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
var isRepeating: Boolean     // default true
var loopDuration: Float      // seconds; the editor overwrites it on a timeline resize
val playheadTime: Float      // read-only, seconds into the run
val seekTime: Float?         // read-only; non-null while the editor has it parked
```

`isRepeating` is the one an app usually sets. With it off, each track plays its own
keyframes once and holds its final pose:

```kotlin
LaunchedEffect(inertia) {
    inertia.isRepeating = false
}
```

`loopDuration` applies from the next frame, so changing it mid-run stretches the loop
rather than waiting for a restart. The editor overwrites it whenever its timeline is
resized, so an app that sets it and then attaches the editor will see its value replaced.

## `InertiaPlayback`

```kotlin
object InertiaPlayback {
    const val defaultLoopDuration: Float                          // 3.0
    val loopDurationRange: ClosedFloatingPointRange<Float>        // 0.1f..60.0f
    fun clampLoopDuration(seconds: Float): Float
}
```

The same constants the editor clamps its timeline to, under the same name on all three
runtimes.

## Data types

The schema types are `kotlinx.serialization` data classes matching the file format:

```kotlin
@Serializable
data class InertiaAnimationSchema(
    val id: String,
    val initialValues: InertiaAnimationValues = InertiaAnimationValues(),
    val invokeType: InertiaAnimationInvokeType,   // trigger | auto
    val keyframes: List<InertiaAnimationKeyframe> = emptyList(),
    val shapes: List<InertiaShape> = emptyList()
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

Note that `translate` is a `List<Float>` rather than a pair, to match the array in the
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

`InertiaShape`, `InertiaShapeProperties` and `Vertex` describe the vector shapes a schema
can carry behind an actionable. `InertiaShapeCanvas` draws them; you do not construct them
yourself, the editor authors them.

`getHostForWebSocket()`, `isValidIPv4()` and `getFirstDnsIP()` are host-discovery helpers
that shell out to `ip route`. Nothing in the runtime calls them — `baseURL` is passed
through as given.
