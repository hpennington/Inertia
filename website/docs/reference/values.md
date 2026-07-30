# Animatable values

Every keyframe carries all five values. There is no partial keyframe — you cannot animate
only opacity and leave position to whatever another track is doing.

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
every `translate` in it relative to that smaller box.

Positive `y` is down, matching SwiftUI's coordinate space.

## `scale`

Uniform — there is no separate `scaleX`/`scaleY`. Applied via `scaleEffect`, so it scales
about the view's center and does not affect layout: neighbouring views do not move out of
the way.

## Rotation

Two rotation values, applied together, differing only in anchor:

- `rotateCenter` spins the view in place.
- `rotate` swings it about its top-left corner, which moves the view as well as turning
  it.

Both are in degrees, positive clockwise, and both are applied on every path — editor
mode, bundled playback, and a frame held by the playhead — in that order: `rotate` about
the top-left first, then `rotateCenter` about the center of the result.

Neither is recorded by dragging — a drag in the viewport writes `translate` only, and a
recorded keyframe starts with both rotations at `0`. To rotate, type a value into the
**Rotate** or **Rotate Center** field of the keyframe editor, or write it into the file
by hand.

## `opacity`

Straight `opacity` modifier. Values outside `0...1` are not meaningful; the runtime
sanitizes non-finite values rather than passing them to SwiftUI, which would trap.

## Interpolation

Keyframes interpolate with a cubic spline (`CubicKeyframe`), so motion eases through
intermediate keyframes rather than moving in straight segments between them. Three
consequences worth knowing:

- A spline can overshoot. Three keyframes moving a view right, then further right, then
  back can swing past the last position before settling.
- Durations must be positive, because the spline divides by the keyframe's duration. The
  runtime rewrites any duration that is zero, negative or non-finite to **1ms** before
  handing the track to SwiftUI, so such a keyframe reads as an instant jump rather than
  producing `NaN`.
- A keyframe whose `values` are non-finite is dropped from the track altogether, taking
  its duration with it — the keyframes after it therefore land earlier than the file
  says.

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

A keyframe of exactly this leaves the view as SwiftUI laid it out. It is a useful value to
start and end tracks on.
