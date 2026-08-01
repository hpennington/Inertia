# SwiftUI API

Everything in this page comes from `import Inertia`. The equivalents for the other
runtimes are on [Compose API](compose-api.md) and [React API](react-api.md).

## `InertiaContainer`

The root of an Inertia hierarchy. It owns the animation data, defines the coordinate space
`translate` values are measured against, and provides the environment its children read.

```swift
InertiaContainer(
    bundle: Bundle = Bundle.main,
    dev: Bool,
    id: InertiaID,
    hierarchyId: String,
    @ViewBuilder content: @escaping () -> Content
)
```

| Parameter | Meaning |
| --- | --- |
| `bundle` | Where to look for the animation resource. Defaults to the main bundle. |
| `dev` | `true` takes animations from the editor and opens the editor channel; `false` loads them from `bundle` and never dials out. |
| `id` | Resource name of the animation file, without `.json`. Also the container id the editor addresses its schemas to — see the warning below. |
| `hierarchyId` | Id of the root node in the view hierarchy the editor draws. |

```swift
InertiaContainer(dev: false, id: "animation", hierarchyId: "animation") {
    ContentView()
}
```

!!! warning "The resource must exist when `dev` is `false`"

    With `dev: false` the initializer reads `id`.json from `bundle` and traps if the
    resource is missing or fails to decode. `[]` is a valid file.

!!! warning "The editor only addresses the container id `animation`"

    The runtime drops any schema whose container id does not match its own, and the
    editor sends every schema against the container id `"animation"`. A container with a
    different `id` therefore loads its bundled file normally but receives nothing from
    the editor — the app connects, the hierarchy appears, and playback does nothing.

    Use `id: "animation"` for any container you intend to author in the editor.

### Modifier form

```swift
func inertiaContainer(dev: Bool, id: InertiaID, hierarchyId: String) -> some View
```

```swift
ContentView()
    .inertiaContainer(dev: false, id: "animation", hierarchyId: "animation")
```

## `View.inertia(_:)`

```swift
func inertia(_ hierarchyId: String) -> some View
```

Tags a view as animatable under the given id. Apply it after the modifiers that determine
the view's appearance and size:

```swift
RoundedRectangle(cornerRadius: 12)
    .fill(.blue)
    .frame(width: 200, height: 120)
    .inertia("card0")
```

What the modifier installs depends on the environment: inside a container with `dev: true`
it installs the editable representation — selectable, draggable, reporting to the editor.
Otherwise it installs the plain animating one. See [Animation IDs](../guides/ids.md) for how
the id relates to instances.

## `View.inertiaEditor(_:)`

```swift
func inertiaEditor(_ isEditor: Bool) -> some View
```

Sets editor mode for a subtree. `InertiaContainer` already sets it from its `dev`
parameter; use this only if you need to override it for part of a hierarchy.

## `InertiaDataModel`

The container's animation state, reached through the environment:

```swift
@Environment(\.inertiaDataModel) private var inertia: InertiaDataModel!
```

`nil` outside an `InertiaContainer`.

### Playback

```swift
func trigger(_ id: InertiaID)
```

Starts the container's clock and marks `id`'s track as running. Nothing animates until an
id is triggered — see [Triggering animations](../guides/triggering.md).

```swift
var isRepeating: Bool             // default true
var loopDuration: CGFloat         // seconds; NOT clamped on assignment
private(set) var playheadTime: CGFloat   // seconds into the current loop
private(set) var seekTime: CGFloat?      // non-nil while the editor is holding a frame
```

Assigning to `loopDuration` stores the value as given. `InertiaPlayback.loopDurationRange`
is what the editor clamps its timeline to, and what `clampLoopDuration(_:)` applies to
lengths arriving from the editor — pass your own values through it yourself if they are
not already trusted.

The loop the runtime plays is `max(loopDuration, longest track)`, so a track longer than
`loopDuration` stretches the loop for every track rather than being truncated.

`pause`, `seek` and `resume` are driven by the editor over the socket and are not part of
the public API — an app can only start playback, not stop it.

### Hierarchy

```swift
func registerHierarchyIdPrefix(_ prefix: String)
```

Registers a prefix and seeds its animation state. `.inertia(_:)` does this for you; you
would only call it directly when driving the runtime without the modifier.

## `InertiaPlayback`

Playback constants, shared with the editor.

```swift
static let defaultLoopDuration: CGFloat                  // 3.0
static let loopDurationRange: ClosedRange<CGFloat>       // 0.1...60.0
static func clampLoopDuration(_ seconds: CGFloat) -> CGFloat
```

A loop lasts as long as the timeline the animation was authored on, not as long as its
last keyframe. Tracks are padded to the loop so that views with animations of different
lengths restart together.

## `InertiaAnimationSchema`

The decoded form of one animation object in the file.

```swift
public struct InertiaAnimationSchema: Codable, Identifiable, Equatable {
    public let id: InertiaID
    public let initialValues: InertiaAnimationValues
    public let invokeType: InertiaAnimationInvokeType   // .auto | .trigger
    public let keyframes: [InertiaAnimationKeyframe]
}
```

```swift
public struct InertiaAnimationKeyframe: Codable {
    public let id: String
    public let values: InertiaAnimationValues
    public let duration: CGFloat   // seconds since the previous keyframe
}
```

## `InertiaAnimationValues`

One pose. Conforms to `VectorArithmetic` and `Animatable`, which is what lets SwiftUI
interpolate it.

```swift
public struct InertiaAnimationValues {
    public var scale: CGFloat
    public var translate: CGSize   // fraction of the container's size
    public var rotate: CGFloat     // degrees, top-left anchor, applied first
    public var rotateCenter: CGFloat  // degrees, center anchor
    public var opacity: CGFloat
}
```

See [Animatable values](values.md).

## `InertiaID`

```swift
public typealias InertiaID = String
```

## Types you are unlikely to need

`Node`, `Tree`, `AnimationSignal`, `InertiaMessage`, `InertiaSchemaWrapper` and
`InertiaWebSocketClient` are public because the editor talks to them over the wire. They
are part of the editor protocol rather than the app-facing API, and can change without
that being a breaking change for apps.

`InertiaWebSocketClient.shared.setEnabled(_:host:port:)` opens and closes the editor
channel for the whole process. `InertiaContainer` calls it from its `dev` flag on appear,
and the client refuses to dial until it has been enabled, so you should not need to call
it yourself unless you are driving the runtime without a container.

The `host` defaults to `127.0.0.1`, which is what a simulator needs — it shares the Mac's
network stack. A runtime on a physical device has to be pointed at the Mac's address on
the local network instead.

`InertiaViewModel` is also public and exposes `trigger`, `cancel` and `restart`, but the
three are currently no-ops left over from an earlier schema, and `InertiaContainer` does
not inject it into the environment. Use `\.inertiaDataModel` instead.
