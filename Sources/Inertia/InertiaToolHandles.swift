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
//  Public because the editor draws them too. Its shape canvas is the app's
//  drawings on a stage of their own, with no app under test on it to take a
//  gesture, so the same chrome is hung on the same geometry over there and the
//  edit is written straight into the project — see `ShapeCanvasView`. One set of
//  handles rather than a second set that merely looks like these: a knob is a
//  size, a reach and a hit area as much as an appearance, and two copies of
//  those drift.
//

import SwiftUI

/// What the editor's gestures have added on top of the values an actionable's
/// schema puts it at.
///
/// A delta rather than an absolute transform: the schema is what an actionable
/// *is* at, and the editor folds a gesture into it and pushes it back, at which
/// point this returns to `.none`. Holding it separately is what lets the two be
/// told apart, so the same move is never counted twice.
public struct InertiaToolEdit: Equatable {
    /// Points in the container's coordinate space, which is what the drag is
    /// measured in. Normalized against the container only on the way out.
    public var translate: CGSize = .zero
    /// Degrees, about the node's top-left corner.
    public var rotate: CGFloat = .zero
    /// Degrees, about the node's center.
    public var rotateCenter: CGFloat = .zero
    /// Added to the schema's scale rather than multiplying it, so scale
    /// accumulates across gestures exactly like every other property here.
    public var scale: CGFloat = .zero
    public var opacity: CGFloat = .zero

    public init(
        translate: CGSize = .zero,
        rotate: CGFloat = .zero,
        rotateCenter: CGFloat = .zero,
        scale: CGFloat = .zero,
        opacity: CGFloat = .zero
    ) {
        self.translate = translate
        self.rotate = rotate
        self.rotateCenter = rotateCenter
        self.scale = scale
        self.opacity = opacity
    }

    public static let none = InertiaToolEdit()

    public var isNone: Bool { self == .none }

    public static func + (lhs: InertiaToolEdit, rhs: InertiaToolEdit) -> InertiaToolEdit {
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

/// Which way one of the move tool's axis arrows lets a drag move the node.
///
/// The node's own body stays free in both directions; an arrow pins one
/// component of the drag to zero, for the moves that have to keep a row or a
/// column. Screen axes, not the node's own — see `InertiaTranslateAxes`.
public enum InertiaTranslateAxis: Hashable, CaseIterable, Sendable {
    case horizontal
    case vertical

    /// The drag with the component this axis does not author dropped.
    public func constrain(_ translation: CGSize) -> CGSize {
        switch self {
        case .horizontal:
            return CGSize(width: translation.width, height: 0)
        case .vertical:
            return CGSize(width: 0, height: translation.height)
        }
    }
}

/// Where the move tool's two axis arrows sit, in the container's coordinate
/// space.
///
/// Shared by the chrome that draws them and the gesture that runs them, because
/// the arrows carry no gesture of their own: the node's own drag — the one that
/// already moves it freely — is what a press on an arrow opens, and it asks this
/// which axis that press picked. One gesture rather than one per arrow keeps the
/// two out of each other's way; a knob with a `DragGesture` inside a node that
/// has one of its own leaves which of them wins up to SwiftUI.
///
/// Measured from the node's *drawn* box and axis-aligned however the node has
/// been turned, since what an arrow constrains is horizontal and vertical on
/// screen. The chrome is counter-rotated to match — see
/// `InertiaToolHandles.translateAxisHandles`.
public enum InertiaTranslateAxes {
    /// From the drawn edge of the node's box out to the arrow's tail.
    public static let gap: CGFloat = 22
    public static let length: CGFloat = 14
    public static let halfWidth: CGFloat = 7
    /// How far from an arrow's middle a press still takes it. Generous next to
    /// the arrow itself, which is small, and matched by the hit area the chrome
    /// holds out.
    public static let touchRadius: CGFloat = 24

    /// The middle of one arrow, which is both what it is drawn about and what a
    /// press is measured against.
    public static func center(_ axis: InertiaTranslateAxis, drawnCenter: CGPoint, drawnSize: CGSize) -> CGPoint {
        let reach = gap + length / 2

        switch axis {
        case .horizontal:
            return CGPoint(x: drawnCenter.x + drawnSize.width / 2 + reach, y: drawnCenter.y)
        case .vertical:
            return CGPoint(x: drawnCenter.x, y: drawnCenter.y - drawnSize.height / 2 - reach)
        }
    }

    /// The axis a press picked, or `nil` for anywhere else — the body of the
    /// node included, which is a free move.
    public static func axis(at point: CGPoint, drawnCenter: CGPoint, drawnSize: CGSize) -> InertiaTranslateAxis? {
        InertiaTranslateAxis.allCases.first { axis in
            let middle = center(axis, drawnCenter: drawnCenter, drawnSize: drawnSize)
            return hypot(point.x - middle.x, point.y - middle.y) <= touchRadius
        }
    }
}

public extension InertiaAnimationValues {
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
        drawnContainerPoint(
            CGPoint(x: layoutFrame.minX + point.x, y: layoutFrame.minY + point.y),
            in: layoutFrame,
            containerSize: containerSize
        )
    }

    /// The same, for a point already given in the container's space rather than
    /// in `layoutFrame`'s own box.
    ///
    /// What composes two of these. A shape's handles sit inside the actionable's
    /// transform as well as the shape's own, so the anchor a gesture is measured
    /// about is this transform applied to a point the inner one has already
    /// moved — and that point is a container point, not an offset into a box.
    func drawnContainerPoint(_ point: CGPoint, in layoutFrame: CGRect, containerSize: CGSize) -> CGPoint {
        let center = CGPoint(x: layoutFrame.midX, y: layoutFrame.midY)
        let topLeft = CGPoint(x: layoutFrame.minX, y: layoutFrame.minY)

        var result = point
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

    /// A drag measured on screen, restated in the space *inside* this transform
    /// — which is where an offset stacked under it is measured.
    ///
    /// A shape is moved by an offset applied within the actionable's own
    /// rotation and scale, so a drag to the right across a turned actionable is
    /// not a move to the right in the space the shape's offset lands in. Undoing
    /// the turn and the scale is what keeps the shape under the pointer.
    func unapplying(_ translation: CGSize) -> CGSize {
        let radians = -(rotate + rotateCenter) * .pi / 180
        let divisor = scale.isFinite && abs(scale) > InertiaToolHandles.minimumScale ? scale : 1

        return CGSize(
            width: (translation.width * cos(radians) - translation.height * sin(radians)) / divisor,
            height: (translation.width * sin(radians) + translation.height * cos(radians)) / divisor
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

/// A filled arrowhead pointing along one screen axis: right for the horizontal
/// one, up for the vertical one.
///
/// One head rather than two: both directions of an axis are draggable, and the
/// arrow only has to read as the axis it stands for.
private struct InertiaAxisArrow: Shape {
    let axis: InertiaTranslateAxis

    func path(in rect: CGRect) -> Path {
        Path { path in
            switch axis {
            case .horizontal:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .vertical:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            path.closeSubpath()
        }
    }
}

/// A transform something's handles are drawn inside of, rather than beside.
///
/// See ``InertiaToolHandles/outer``. The pair is what the actionable's animation
/// is to a shape drawn behind it: the values it is displayed with, and the box
/// those values turn and scale about.
public struct InertiaOuterTransform: Equatable {
    public let values: InertiaAnimationValues
    public let layoutFrame: CGRect

    public init(values: InertiaAnimationValues, layoutFrame: CGRect) {
        self.values = values
        self.layoutFrame = layoutFrame
    }

    public static let none = InertiaOuterTransform(values: .identity, layoutFrame: .zero)
}

/// The handles a selected actionable shows for the active tool.
///
/// Sits in the node's overlay, inside everything that transforms it, so the
/// chrome stays glued to the node as it turns and scales. The knobs themselves
/// are counter-scaled so they stay the same size on screen whatever the node has
/// been scaled to.
public struct InertiaToolHandles: View {
    /// A node scaled to nothing has no box left to grab, and a negative scale
    /// mirrors it. This is the smallest scale a handle will author.
    public static let minimumScale: CGFloat = 0.01

    let tool: InertiaTool
    /// The transform the node is drawn with right now, gesture included.
    let values: InertiaAnimationValues
    /// The transform a gesture is measured from and reports, when that is not
    /// the one the node is drawn with.
    ///
    /// Nil in the app under test, where they are the same thing: a node is drawn
    /// at the transform its schema puts it at, and a gesture edits that
    /// transform. The editor's canvas has the one case where the two part — a
    /// shape *placed* in its parent is drawn by baking the placement into its
    /// corners, so what the canvas is drawn with says nothing about where the
    /// shape has been placed, and a scale measured off it would be a ratio of
    /// the wrong number.
    ///
    /// Only what a gesture counts from, and what the readout names. Every
    /// measurement of the chrome itself stays on `values`, because that is what
    /// the node is actually the size and angle of on screen.
    var authored: InertiaAnimationValues? = nil
    /// The node's box as laid out, in the container's coordinate space.
    let layoutFrame: CGRect
    let containerSize: CGSize
    /// The container's named coordinate space, which the drags report their
    /// locations in. Without one there is nothing to measure an angle against,
    /// so the handles stay off.
    let containerSpace: String?
    /// The transform these handles sit *inside*, and the box it turns about.
    ///
    /// Nil for an actionable, whose handles sit directly in the container. A
    /// shape's do not: they are inside the actionable's own animation as well as
    /// the shape's, so the anchor a gesture turns or scales about has to be
    /// carried out through that second transform before it can be measured
    /// against a pointer reporting container coordinates.
    var outer: InertiaOuterTransform? = nil
    /// The edit the gesture has produced so far, replaced on every change.
    let onChange: (InertiaToolEdit) -> Void
    /// The gesture is over — fold what it produced into the node's position and
    /// tell the editor.
    let onEnded: () -> Void

    public init(
        tool: InertiaTool,
        values: InertiaAnimationValues,
        authored: InertiaAnimationValues? = nil,
        layoutFrame: CGRect,
        containerSize: CGSize,
        containerSpace: String?,
        outer: InertiaOuterTransform? = nil,
        onChange: @escaping (InertiaToolEdit) -> Void,
        onEnded: @escaping () -> Void
    ) {
        self.tool = tool
        self.values = values
        self.authored = authored
        self.layoutFrame = layoutFrame
        self.containerSize = containerSize
        self.containerSpace = containerSpace
        self.outer = outer
        self.onChange = onChange
        self.onEnded = onEnded
    }

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
        /// The transform the gesture is measured from, as it stood when the
        /// gesture began — see ``InertiaToolHandles/authored``.
        let values: InertiaAnimationValues
        /// The scale the node was *drawn* at then, which is what the chrome's
        /// own measurements are in. The same number as `values.scale` in the app
        /// under test, and not for a shape being placed on the editor's canvas.
        let drawnScale: CGFloat
    }

    /// The transform a gesture is measured from — the one the node is drawn with
    /// unless it has been told otherwise.
    private var editedValues: InertiaAnimationValues { authored ?? values }

    private var size: CGSize { layoutFrame.size }

    /// How far outside the node's box a knob sits, and how big it is drawn.
    /// Divided through by the scale the node is drawn at so the chrome keeps its
    /// size on screen.
    private var chromeScale: CGFloat {
        // Both transforms the chrome is drawn inside of, so a knob keeps its
        // size on screen however the shape *and* the actionable behind it have
        // been scaled.
        let scale = values.scale * (outer?.values.scale ?? 1)
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

    public var body: some View {
        if isValid {
            ZStack(alignment: .topLeading) {
                switch tool {
                case .translate:
                    // The whole node is the free handle — see
                    // `InertiaEditable`'s own drag gesture, which is live only
                    // for this tool. These two arrows are the same drag pinned
                    // to one axis.
                    translateAxisHandles
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

    /// The axis arrows' measurements, taken back into the node's own box: the
    /// chrome is counter-scaled, so what lands on screen is what
    /// `InertiaTranslateAxes` says — which is what a press is tested against.
    private var axisGap: CGFloat { InertiaTranslateAxes.gap * chromeScale }
    private var axisLength: CGFloat { InertiaTranslateAxes.length * chromeScale }
    private var axisHalfWidth: CGFloat { InertiaTranslateAxes.halfWidth * chromeScale }

    /// Where one arrow starts, out past the middle of the edge it points
    /// through. It runs from here to `axisLength` further out.
    private func axisTail(_ axis: InertiaTranslateAxis) -> CGPoint {
        switch axis {
        case .horizontal:
            return CGPoint(x: size.width + axisGap, y: size.height / 2)
        case .vertical:
            return CGPoint(x: size.width / 2, y: -axisGap)
        }
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

    /// The move tool's two arrows, one along each screen axis, each drawn from
    /// the node's center out past the edge it points through.
    ///
    /// Counter-rotated as a group, so they keep pointing along the screen's axes
    /// rather than the node's — which is what they pin a drag to. Undoing the sum
    /// of the rotations carried above these handles, about this group's own
    /// center, leaves that center exactly where the transforms put it — a
    /// rotation fixes its own anchor — and cancels the turn the arrows would
    /// otherwise inherit, since a uniform scale commutes with a rotation and the
    /// scale is all that is left.
    ///
    /// Both transforms, for the same reason `chromeScale` divides by both: a
    /// shape's handles sit inside the actionable's animation as well as the
    /// shape's own, and an arrow that inherited the actionable's turn would point
    /// somewhere `InertiaTranslateAxes` — which measures a press against the
    /// screen's axes — is not looking.
    ///
    /// Hittable and gestureless. A press has to land on *something* for the
    /// node's own drag to be offered it, and an arrow hangs outside the node's
    /// box — but which axis that press picked is decided by
    /// `InertiaTranslateAxes`, not by which view took it.
    @ViewBuilder
    private var translateAxisHandles: some View {
        ZStack(alignment: .topLeading) {
            ForEach(InertiaTranslateAxis.allCases, id: \.self) { axis in
                axisArrow(axis)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .rotationEffect(Angle(degrees: -drawnRotation))
    }

    /// Every degree of turn the chrome is drawn inside of: the node's own two
    /// rotations, and the outer transform's two for a shape.
    private var drawnRotation: CGFloat {
        values.rotate + values.rotateCenter
            + (outer?.values.rotate ?? 0) + (outer?.values.rotateCenter ?? 0)
    }

    @ViewBuilder
    private func axisArrow(_ axis: InertiaTranslateAxis) -> some View {
        let tail = axisTail(axis)

        Path { path in
            path.move(to: centerPoint)
            path.addLine(to: tail)
        }
        .stroke(Color.green.opacity(0.6), lineWidth: chromeLineWidth)
        .allowsHitTesting(false)

        InertiaAxisArrow(axis: axis)
            .fill(Color.green)
            .overlay { InertiaAxisArrow(axis: axis).stroke(Color.white, lineWidth: lineWidth) }
            .frame(
                width: axis == .horizontal ? axisLength : axisHalfWidth * 2,
                height: axis == .horizontal ? axisHalfWidth * 2 : axisLength
            )
            // The same circle `InertiaTranslateAxes.axis(at:)` tests a press
            // against — a `Circle` is inscribed in its frame, whose narrow side
            // is the arrow's width — so every press this view takes picks an axis
            // and every press that picks one lands on a view.
            .contentShape(
                Circle().inset(by: -(InertiaTranslateAxes.touchRadius - InertiaTranslateAxes.halfWidth) * chromeScale)
            )
            .offset(
                x: axis == .horizontal ? tail.x : tail.x - axisHalfWidth,
                y: axis == .horizontal ? tail.y - axisHalfWidth : tail.y - axisLength
            )
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
        // The opacity being *edited* rather than the one the node is drawn at:
        // the track a knob runs along is the value it authors.
        let filled = width * min(1, max(0, editedValues.opacity))

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
                let drawnWidth = max(self.size.width * start.drawnScale, 60)
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

    /// What the tool is authoring, which away from the app under test is not
    /// always what the node is drawn at — see ``authored``.
    private var readoutText: String? {
        let values = editedValues

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
        var drawnAnchor = values.drawnPoint(anchor, in: layoutFrame, containerSize: containerSize)
        if let outer {
            drawnAnchor = outer.values.drawnContainerPoint(
                drawnAnchor,
                in: outer.layoutFrame,
                containerSize: containerSize
            )
        }

        let start = GestureStart(
            anchor: drawnAnchor,
            reference: vector(from: drawnAnchor, to: location),
            values: editedValues,
            drawnScale: values.scale
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
