# Animatable values

Every keyframe carries all five values. There is no partial keyframe — you cannot animate
only opacity and leave position to whatever another track is doing.

All three runtimes read the same five values and compose them into the same matrix. Where
they differ is how they get *between* keyframes — see [Interpolation](#interpolation).

| Key | Type | Neutral value | Meaning |
| --- | --- | --- | --- |
| `translate` | `[x, y]` | `[0, 0]` | Offset as a fraction of the container's size |
| `scale` | number | `1` | Uniform scale |
| `rotate` | degrees | `0` | Rotation anchored at the view's top-left |
| `rotateCenter` | degrees | `0` | Rotation anchored at the view's center |
| `opacity` | `0`–`1` | `1` | `0` fully transparent, `1` fully opaque |

## `translate` is normalized

Translation is stored as a fraction of the **container's** size, not the view's, and not
in points. The runtime multiplies by the container's measured width and height:

```
offsetX = translate[0] × containerWidth
offsetY = translate[1] × containerHeight
```

| Value | Result |
| --- | --- |
| `[0, 0]` | Where the view lays out |
| `[0.5, 0]` | Half the container's width to the right |
| `[-1, 0]` | A full container width to the left |
| `[0, 0.25]` | A quarter of the container's height down |

This is why one animation file works on a 375pt phone and a 430pt one: an animation that
slides a card in from off-screen left stays off-screen left on both.

It also means the container's size matters. A container that is not the full screen makes
every `translate` in it relative to that smaller box. This is easiest to get wrong on
Compose, where `InertiaContainer` wraps its content rather than filling the screen.

Positive `y` is down, which is the coordinate space of all three platforms.

## `scale`

Uniform — there is no separate `scaleX`/`scaleY`. It scales about the view's center and
does not affect layout: neighbouring views do not move out of the way. Applied through
`scaleEffect` on SwiftUI, a `graphicsLayer` on Compose, and a CSS `scale()` on the web.

## Rotation

Two rotation values, applied together, differing only in anchor:

- `rotateCenter` spins the view in place.
- `rotate` swings it about its top-left corner, which moves the view as well as turning
  it.

Both are in degrees, positive clockwise, and both are applied on every path — editor
mode, standalone playback, and a frame held by the playhead — in that order: `rotate` about
the top-left first, then `rotateCenter` about the center of the result.

Two anchors need two transforms, since a layer carries one origin. Compose stacks a
`graphicsLayer` per anchor; the web wraps `rotate` in a half-box shift and its inverse,
which walks the pivot out to the corner and back. Both compose the same matrix SwiftUI's
`anchor: .topLeading` produces.

Neither is recorded by dragging — a drag in the viewport writes `translate` only, and a
recorded keyframe starts with both rotations at `0`. To rotate, type a value into the
**Rotate** or **Rotate Center** field of the keyframe editor, or write it into the file
by hand.

## `opacity`

Straight opacity. Values outside `0...1` are not meaningful; every runtime sanitizes
non-finite values rather than passing them on, which on SwiftUI would trap.

## Interpolation

This is the one place the runtimes visibly disagree. The poses *at* the keyframes are
identical; the paths between them are not.

=== "SwiftUI"

    Keyframes interpolate with a cubic spline (`CubicKeyframe`) fitted across the track, so
    motion eases through intermediate keyframes rather than moving in straight segments
    between them.

    A spline can **overshoot**. Three keyframes moving a view right, then further right,
    then back can swing past the last position before settling.

=== "Compose"

    Each segment is solved independently with a cubic ease-in-out — accelerating out of the
    keyframe before and decelerating into the keyframe after.

    This approximates the SwiftUI runtime's spline but does not overshoot: a value never
    goes past the keyframe it is heading for.

=== "React"

    Each segment is solved independently with a cubic ease-in-out — accelerating out of the
    keyframe before and decelerating into the keyframe after.

    This approximates the SwiftUI runtime's spline but does not overshoot: a value never
    goes past the keyframe it is heading for.

Two things hold on every runtime:

- Durations must be positive, because interpolation divides by the keyframe's duration.
  Any duration that is zero, negative or non-finite is rewritten to **1ms** before the
  track is played, so such a keyframe reads as an instant jump rather than producing `NaN`.
- A pose the runtime cannot draw is replaced rather than passed on. SwiftUI drops a
  keyframe whose `values` are non-finite from the track altogether, taking its duration
  with it, so the keyframes after it land earlier than the file says; Compose and React
  substitute the neutral pose for that keyframe and keep its timing.

There is no per-keyframe easing curve in the format. If you need a different feel, add
intermediate keyframes.

## The neutral pose

```json
{
  "scale": 1,
  "translate": [0, 0],
  "rotate": 0,
  "rotateCenter": 0,
  "opacity": 1
}
```

A keyframe of exactly this leaves the view exactly where layout put it. It is a useful
value to start and end tracks on, and it is what every runtime falls back to when a pose
turns out to be undrawable.
