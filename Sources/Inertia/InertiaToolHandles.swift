//
//  InertiaToolHandles.swift
//  Inertia
//
//  The chrome a selected actionable grows in editor mode, one set per tool.
//
//  The editor's toolbar picks the tool and sends it over; the gesture itself
//  happens here, in the app under test, because that is where the node is. Each
//  tool drives exactly one property of `InertiaAnimationValues` and reports the
//  whole transform back — see `InertiaMessage.MessageEdit`.
//

import SwiftUI

/// What the editor's gestures have added on top of the values an actionable's
/// schema puts it at.
///
/// A delta rather than an absolute transform: the schema is what an actionable
/// *is* at, and the editor folds a gesture into it and pushes it back, at which
/// point this returns to `.none`. Holding it separately is what lets the two be
/// told apart, so the same move is never counted twice.
struct InertiaToolEdit: Equatable {
    /// Points in the container's coordinate space, which is what the drag is
    /// measured in. Normalized against the container only on the way out.
    var translate: CGSize = .zero
    /// Degrees, about the node's top-left corner.
    var rotate: CGFloat = .zero
    /// Degrees, about the node's center.
    var rotateCenter: CGFloat = .zero
    /// Added to the schema's scale rather than multiplying it, so scale
    /// accumulates across gestures exactly like every other property here.
    var scale: CGFloat = .zero
    var opacity: CGFloat = .zero

    static let none = InertiaToolEdit()

    var isNone: Bool { self == .none }

    static func + (lhs: InertiaToolEdit, rhs: InertiaToolEdit) -> InertiaToolEdit {
        InertiaToolEdit(
            translate: CGSize(
                width: lhs.translate.width + rhs.translate.width,
                height: lhs.translate.height + rhs.translate.height
            ),
            rotate: lhs.rotate + rhs.rotate,
            rotateCenter: lhs.rotateCenter + rhs.rotateCenter,
            scale: lhs.scale + rhs.scale,
            opacity: lhs.opacity + rhs.opacity
        )
    }
}

extension InertiaAnimationValues {
    /// This transform with an in-progress edit folded into it — what the node is
    /// drawn at while a handle is being dragged, and what the editor is told
    /// once it is let go.
    ///
    /// Scale and opacity are clamped rather than left to run: a scale through
    /// zero flips the node inside out and a negative opacity is not a thing a
    /// keyframe can hold.
    func applying(_ edit: InertiaToolEdit, containerSize: CGSize) -> InertiaAnimationValues {
        guard edit != .none else { return self }

        let width = containerSize.width > 0 ? containerSize.width : 1
        let height = containerSize.height > 0 ? containerSize.height : 1

        return InertiaAnimationValues(
            scale: max(InertiaToolHandles.minimumScale, scale + edit.scale),
            translate: CGSize(
                width: translate.width + edit.translate.width / width,
                height: translate.height + edit.translate.height / height
            ),
            rotate: rotate + edit.rotate,
            rotateCenter: rotateCenter + edit.rotateCenter,
            opacity: min(1, max(0, opacity + edit.opacity))
        )
    }

    /// Where `point` — given in the actionable's own laid-out box, origin at its
    /// top-left — is drawn in the container once this transform has been
    /// applied.
    ///
    /// The same stack `InertiaEditable.body` puts on the node, in the same
    /// order: scale about the center, rotate about the top-left, rotate about
    /// the center, then the offset. Each anchor is resolved against the *layout*
    /// frame, which is how SwiftUI composes geometry effects — an inner effect
    /// never moves an outer one's anchor.
    ///
    /// The handles are drawn inside the transform and so need none of this; the
    /// gesture math does, because a rotation is an angle swept about a point and
    /// that point has to be in the space the drag reports its locations in.
    func drawnPoint(_ point: CGPoint, in layoutFrame: CGRect, containerSize: CGSize) -> CGPoint {
        let center = CGPoint(x: layoutFrame.midX, y: layoutFrame.midY)
        let topLeft = CGPoint(x: layoutFrame.minX, y: layoutFrame.minY)

        var result = CGPoint(x: layoutFrame.minX + point.x, y: layoutFrame.minY + point.y)
        result = CGPoint(
            x: center.x + (result.x - center.x) * scale,
            y: center.y + (result.y - center.y) * scale
        )
        result = Self.rotating(result, around: topLeft, degrees: rotate)
        result = Self.rotating(result, around: center, degrees: rotateCenter)

        return CGPoint(
            x: result.x + translate.width * containerSize.width,
            y: result.y + translate.height * containerSize.height
        )
    }

    private static func rotating(_ point: CGPoint, around anchor: CGPoint, degrees: CGFloat) -> CGPoint {
        guard degrees != 0 else { return point }

        let radians = degrees * .pi / 180
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y

        return CGPoint(
            x: anchor.x + dx * cos(radians) - dy * sin(radians),
            y: anchor.y + dx * sin(radians) + dy * cos(radians)
        )
    }
}

/// The handles a selected actionable shows for the active tool.
///
/// Sits in the node's overlay, inside everything that transforms it, so the
/// chrome stays glued to the node as it turns and scales. The knobs themselves
/// are counter-scaled so they stay the same size on screen whatever the node has
/// been scaled to.
struct InertiaToolHandles: View {
    /// A node scaled to nothing has no box left to grab, and a negative scale
    /// mirrors it. This is the smallest scale a handle will author.
    static let minimumScale: CGFloat = 0.01

    let tool: InertiaTool
    /// The transform the node is drawn with right now, gesture included.
    let values: InertiaAnimationValues
    /// The node's box as laid out, in the container's coordinate space.
    let layoutFrame: CGRect
    let containerSize: CGSize
    /// The container's named coordinate space, which the drags report their
    /// locations in. Without one there is nothing to measure an angle against,
    /// so the handles stay off.
    let containerSpace: String?
    /// The edit the gesture has produced so far, replaced on every change.
    let onChange: (InertiaToolEdit) -> Void
    /// The gesture is over — fold what it produced into the node's position and
    /// tell the editor.
    let onEnded: () -> Void

    /// Where the gesture started, taken once so the math stays measured against
    /// the transform the node had before the drag rather than the one it is
    /// being given.
    @State private var start: GestureStart? = nil

    private struct GestureStart {
        /// The point the gesture turns or scales about, in container space.
        let anchor: CGPoint
        /// The pointer's opening vector from `anchor`, which an angle or a
        /// distance ratio is taken relative to.
        let reference: CGVector
        /// The node's transform when the gesture began.
        let values: InertiaAnimationValues
    }

    private var size: CGSize { layoutFrame.size }

    /// How far outside the node's box a knob sits, and how big it is drawn.
    /// Divided through by the scale the node is drawn at so the chrome keeps its
    /// size on screen.
    private var chromeScale: CGFloat {
        let scale = values.scale
        return scale.isFinite && scale > Self.minimumScale ? 1 / scale : 1
    }

    private var knobRadius: CGFloat { 6 * chromeScale }
    private var knobGap: CGFloat { 22 * chromeScale }
    /// The knob's own outline, which stays fine next to the chrome it sits on.
    private var lineWidth: CGFloat { 1.5 * chromeScale }
    /// The rings and the track: heavier than a hairline so they read against
    /// whatever the app happens to be drawing underneath them.
    private var chromeLineWidth: CGFloat { 3 * chromeScale }

    private var isValid: Bool {
        size.width > 0 && size.height > 0
            && size.width.isFinite && size.height.isFinite
            && layoutFrame.origin.x.isFinite && layoutFrame.origin.y.isFinite
            && containerSpace != nil
    }

    var body: some View {
        if isValid {
            ZStack(alignment: .topLeading) {
                switch tool {
                case .translate:
                    // The whole node is the handle — see `InertiaEditable`'s own
                    // drag gesture, which is live only for this tool.
                    EmptyView()
                case .rotate:
                    rotationHandle(anchor: .zero, radius: rotateRadius, knob: rotateKnob)
                case .rotateCenter:
                    rotationHandle(anchor: centerPoint, radius: rotateCenterRadius, knob: rotateCenterKnob)
                case .scale:
                    scaleHandles
                case .opacity:
                    opacityHandle
                }

                readout
            }
            // The box is only the layout frame; every knob hangs outside it and
            // must stay both visible and hittable.
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    // MARK: - Geometry

    private var centerPoint: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// The knob for the top-left rotation sits out along the box's diagonal, so
    /// it reads as belonging to the corner it turns about.
    private var rotateKnob: CGPoint {
        let diagonal = max(hypot(size.width, size.height), 1)
        let unit = CGVector(dx: size.width / diagonal, dy: size.height / diagonal)
        return CGPoint(x: -unit.dx * knobGap, y: -unit.dy * knobGap)
    }

    private var rotateRadius: CGFloat {
        hypot(rotateKnob.x, rotateKnob.y)
    }

    /// Centre rotation gets the familiar knob above the top edge.
    private var rotateCenterKnob: CGPoint {
        CGPoint(x: size.width / 2, y: -knobGap)
    }

    private var rotateCenterRadius: CGFloat {
        size.height / 2 + knobGap
    }

    private var corners: [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
    }

    private var opacityBarWidth: CGFloat { max(size.width, 60 * chromeScale) }

    private var opacityBarOrigin: CGPoint {
        CGPoint(x: (size.width - opacityBarWidth) / 2, y: size.height + knobGap)
    }

    // MARK: - Handles

    /// A dashed ring about `anchor` with a knob on it. Dragging the knob turns
    /// the node by the angle the pointer sweeps about the same anchor, so the
    /// knob stays under the finger.
    @ViewBuilder
    private func rotationHandle(anchor: CGPoint, radius: CGFloat, knob: CGPoint) -> some View {
        Circle()
            .strokeBorder(
                Color.green.opacity(0.6),
                style: StrokeStyle(
                    lineWidth: chromeLineWidth,
                    dash: [9 * chromeScale, 7 * chromeScale]
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: anchor.x - radius, y: anchor.y - radius)
            .allowsHitTesting(false)

        Path { path in
            path.move(to: anchor)
            path.addLine(to: knob)
        }
        .stroke(Color.green.opacity(0.6), lineWidth: chromeLineWidth)
        .allowsHitTesting(false)

        knobView
            .offset(x: knob.x - knobRadius, y: knob.y - knobRadius)
            .gesture(gesture(anchor: anchor) { start, location in
                var edit = InertiaToolEdit()
                let swept = angle(of: vector(from: start.anchor, to: location)) - angle(of: start.reference)
                if tool == .rotate {
                    edit.rotate = swept
                } else {
                    edit.rotateCenter = swept
                }
                return edit
            })
    }

    /// One knob per corner. Any of them scales the node about its center, by how
    /// much further out the pointer has been pulled.
    @ViewBuilder
    private var scaleHandles: some View {
        ForEach(Array(corners.enumerated()), id: \.offset) { _, corner in
            knobView
                .offset(x: corner.x - knobRadius, y: corner.y - knobRadius)
                .gesture(gesture(anchor: centerPoint) { start, location in
                    let opening = magnitude(start.reference)
                    guard opening > 1 else { return .none }

                    let factor = magnitude(vector(from: start.anchor, to: location)) / opening
                    var edit = InertiaToolEdit()
                    // A delta on the value the node started at, so the gesture
                    // composes with whatever its schema already scales it by.
                    edit.scale = max(Self.minimumScale, start.values.scale * factor) - start.values.scale
                    return edit
                })
        }
    }

    /// A track under the node filled to its current opacity. The knob runs the
    /// width of the track, which is the node's own width unless that is too
    /// narrow to aim at.
    @ViewBuilder
    private var opacityHandle: some View {
        let origin = opacityBarOrigin
        let width = opacityBarWidth
        let height = 7 * chromeScale
        let filled = width * min(1, max(0, values.opacity))

        Capsule()
            .fill(Color.green.opacity(0.25))
            .frame(width: width, height: height)
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)

        Capsule()
            .fill(Color.green)
            .frame(width: filled, height: height)
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)

        knobView
            .offset(x: origin.x + filled - knobRadius, y: origin.y + height / 2 - knobRadius)
            .gesture(gesture(anchor: origin) { start, location in
                var edit = InertiaToolEdit()
                // Measured along the track from where the gesture opened, so the
                // knob tracks the pointer instead of jumping to it. Against the
                // track as it is *drawn*: the drag reports container points,
                // while the chrome is laid out in the node's own space and
                // counter-scaled, so the two only agree once the node's scale is
                // put back in.
                let drawnWidth = max(self.size.width * start.values.scale, 60)
                let travelled = (location.x - (start.anchor.x + start.reference.dx)) / drawnWidth
                edit.opacity = min(1, max(0, start.values.opacity + travelled)) - start.values.opacity
                return edit
            })
    }

    private var knobView: some View {
        Circle()
            .fill(Color.green)
            .overlay { Circle().strokeBorder(Color.white, lineWidth: lineWidth) }
            .frame(width: knobRadius * 2, height: knobRadius * 2)
            // The knob is small and the drag has to start on it; the hit area is
            // held out to a finger's worth regardless of how far the node has
            // been scaled down.
            .contentShape(Circle().inset(by: -knobRadius))
    }

    /// What the tool is currently authoring, in the units the timeline will show
    /// it in. Sits above the node, out of the way of every handle.
    @ViewBuilder
    private var readout: some View {
        if let text = readoutText {
            Text(text)
                .font(.system(size: 24 * chromeScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12 * chromeScale)
                .padding(.vertical, 6 * chromeScale)
                .background(Color.green, in: Capsule())
                .fixedSize()
                .offset(x: 0, y: -knobGap - 42 * chromeScale)
                .allowsHitTesting(false)
        }
    }

    private var readoutText: String? {
        switch tool {
        case .translate:
            return nil
        case .rotate:
            return String(format: "%.0f°", values.rotate)
        case .rotateCenter:
            return String(format: "%.0f°", values.rotateCenter)
        case .scale:
            return String(format: "%.2f×", values.scale)
        case .opacity:
            return String(format: "%.0f%%", values.opacity * 100)
        }
    }

    // MARK: - Gestures

    /// A drag reported in the container's space, opened against `anchor` given
    /// in the node's own box.
    ///
    /// The container's space rather than the handle's own: a rotation is an
    /// angle about a fixed point, and the handle is inside everything that is
    /// turning it, so its local coordinates move with the very thing being
    /// measured.
    private func gesture(
        anchor: CGPoint,
        edit: @escaping (GestureStart, CGPoint) -> InertiaToolEdit
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(containerSpace ?? ""))
            .onChanged { value in
                let start = self.start ?? begin(anchor: anchor, at: value.startLocation)
                onChange(edit(start, value.location))
            }
            .onEnded { value in
                if let start = self.start {
                    onChange(edit(start, value.location))
                }
                self.start = nil
                onEnded()
            }
    }

    /// Takes the gesture's opening state, keyed off the anchor as it is drawn
    /// right now — before this gesture has moved anything.
    private func begin(anchor: CGPoint, at location: CGPoint) -> GestureStart {
        let drawnAnchor = values.drawnPoint(anchor, in: layoutFrame, containerSize: containerSize)
        let start = GestureStart(
            anchor: drawnAnchor,
            reference: vector(from: drawnAnchor, to: location),
            values: values
        )
        // Assigning during `onChanged` is what makes the first event of a
        // gesture the one that opens it; SwiftUI gives no separate hook.
        self.start = start
        return start
    }

    private func vector(from: CGPoint, to: CGPoint) -> CGVector {
        CGVector(dx: to.x - from.x, dy: to.y - from.y)
    }

    private func magnitude(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    private func angle(of vector: CGVector) -> CGFloat {
        atan2(vector.dy, vector.dx) * 180 / .pi
    }
}
