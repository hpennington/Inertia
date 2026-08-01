# React API

The React runtime is two packages. `inertia-react` is what your app imports; it depends on
`inertia-base`, which holds the framework-agnostic core and is worth reaching into only for
the shared constants and types.

```tsx
import { InertiaContainer, Inertiaable, useInertia } from "inertia-react";
```

React 18.3.1 is a peer dependency — your app supplies React, and a second copy resolving
inside the package breaks hooks.

## `InertiaContainer`

The root of an Inertia hierarchy. It owns the animation data, measures the canvas
`translate` values are resolved against, holds the editor connection, and drives the clock
every actionable inside it is drawn from.

```tsx
type InertiaContainerProps = {
  children: React.ReactElement;
  id: string;
  baseURL: string;
  dev: boolean;
};
```

| Prop | Meaning |
| --- | --- |
| `id` | The container id the editor addresses its schemas to, and the basename of the JSON fetched outside editor mode. |
| `baseURL` | Where `<id>.json` is fetched from when `dev` is false. **Not** the editor's address. |
| `dev` | `true` takes animations from the editor over the socket and never fetches; `false` fetches from `baseURL` and never opens a socket. |

```tsx
<InertiaContainer id="animation" baseURL="http://localhost:8000" dev={isDev}>
  <App />
</InertiaContainer>
```

!!! warning "The editor only addresses the container id `animation`"

    The editor sends every schema against the container id `"animation"`, and the runtime
    drops any schema whose container id does not match its own. Use `id="animation"` for
    any container you intend to author in the editor.

### Where the animation comes from

With `dev` false the container fetches `` `${baseURL}/${id}.json` `` on mount, and logs an
error if the request fails — a missing file is a still page rather than a crash. The server
needs CORS headers if it is not the same origin as your app.

With `dev` true it connects to the editor at `ws://127.0.0.1:8080`. That address is fixed:
`baseURL` has no bearing on it.

The canvas is measured with a `ResizeObserver`, so a container that resizes re-resolves
every `translate` against the new size.

## `Inertiaable`

```tsx
type InertiaableProps = {
  children: React.ReactElement;
  hierarchyIdPrefix: string;
};
```

Wraps one element and animates it under the given id.

```tsx
<Inertiaable hierarchyIdPrefix="card0">
  <div style={{ width: 200, height: 120, background: "blue" }} />
</Inertiaable>
```

`hierarchyIdPrefix` is the id you look up in the animation file and pass to `trigger`. Each
*instance* claims a distinct hierarchy id by appending an index (`card0--0`, `card0--1`),
which is what lets the editor tell copies apart — see [Animation IDs](../guides/ids.md).

It renders an `inline-block` wrapper `div` carrying `data-inertia-id`, and the playback
controller writes `transform` and `opacity` onto that wrapper directly, outside React's
render cycle. So a frame of animation does not re-render your component tree.

The transform is composed as `translate → rotateCenter → rotate (about the top-left, via a
half-box shift and its inverse) → scale`, which is the same matrix the SwiftUI runtime
builds for the same schema.

In editor mode the wrapper also handles clicks for selection, drags that record
translation, and draws the selection border.

## `useInertia`

The app's handle on playback. Throws *"useInertia must be used within an
InertiaContainer"* outside a container.

```tsx
const inertia = useInertia();
```

```ts
{
  trigger(id: string): void;
  cancel(id: string): void;
  restart(id: string): void;
  isCancelled(id: string): boolean;
  setRepeating(value: boolean): void;
  isRepeating(): boolean;
}
```

- **`trigger`** starts an animation that was waiting on its `trigger` invoke type. Arriving
  mid-run it joins the run in progress rather than cutting it short.
- **`cancel`** stops an animation and returns it to its `initialValues`, where it stays
  until `restart`.
- **`restart`** clears a cancellation and plays from the top. Because every actionable in a
  container shares one clock, this rewinds the playhead for all of them.
- **`setRepeating`** — on by default. With it off, each track plays its keyframes once and
  holds its final pose.

```tsx
React.useEffect(() => {
  inertia.setRepeating(false);
}, [inertia]);
```

The returned object is memoized on the controller, so it is stable across renders and safe
in a dependency array.

Loop duration is not exposed here. It starts at the default and changes only when the
editor sends a new timeline length.

## `InertiaPlaybackController`

The class behind `useInertia`, exported for the rare case of driving playback without the
hook. It owns the clock, the schema map, the registered nodes, and the per-frame render.
Everything an app needs is on the hook; reach for the class only if you are wiring the
runtime up yourself.

## From `inertia-base`

The shared core. The types match the file format exactly:

```ts
export type InertiaAnimationValues = {
  scale: number;
  translate: [number, number];   // fraction of the canvas
  rotate: number;
  rotateCenter: number;
  opacity: number;
};

export type InertiaAnimationKeyframe = {
  id: string;
  values: InertiaAnimationValues;
  duration: number;   // seconds since the previous keyframe
};

export interface InertiaAnimationSchema {
  id: string;
  initialValues: InertiaAnimationValues;
  invokeType: InertiaAnimationInvokeType;   // "trigger" | "auto"
  keyframes: Array<InertiaAnimationKeyframe>;
}
```

Playback constants and the interpolation helpers, should you want to sample a track
yourself:

```ts
import {
  InertiaPlayback,   // defaultLoopDuration, clampLoopDuration
  valuesAtTime,      // (schema, time, loopDuration, isRepeating) => values
  trackDuration,     // (schema) => seconds
  playableKeyframes, // keyframes with non-positive durations repaired
  sanitizeValues,    // falls back to the identity pose for non-finite input
} from "inertia-base";
```

`InertiaAnimationInvokeType` is a string enum (`"trigger"` / `"auto"`) rather than a
numeric one, because that is how it is written in the file and a numeric enum could never
round-trip it.

## Types you are unlikely to need

`Tree`, `Node`, `WebSocketClient`, `MessageSchema`, `InertiaSchemaWrapper`,
`AnimationSignal` and the other message types are exported because the editor talks to them
over the wire. They are part of the editor protocol rather than the app-facing API.

`withDrag`, `DraggableProps` and `DraggableInertiaableGuts` are the drag machinery
`Inertiaable` is built from, exported for composition rather than for direct use.

## Logging

The runtime logs to the browser console with an `[INERTIA_LOG]` prefix, which makes it easy
to filter in devtools. It traces schema arrival, id registration and the socket lifecycle —
the three places an animation usually goes missing.
