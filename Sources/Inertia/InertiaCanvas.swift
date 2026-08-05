//
//  InertiaCanvas.swift
//
//
//  Created by Hayden Pennington on 7/5/24.
//

import SwiftUI

#if os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#elseif os(iOS)
typealias ViewRepresentable = UIViewRepresentable
#endif

/// The Metal layer an actionable draws on: the shapes authored alongside its
/// animation, rendered behind its content.
///
/// Shapes are held in the normalized space of whatever frame the canvas fills —
/// the container's, as the actionables lay it out — so the same authored shape
/// holds its place at every size that frame takes, and nothing here has to be
/// told how big it is. The canvas takes no touches; it is a backdrop, and the
/// views it covers stay hit-testable through it.
public struct InertiaCanvas: ViewRepresentable {
    private let vm: InertiaViewModel

    /// Every shape on this canvas already flattened into the one triangle list
    /// the renderer draws, in the canvas's own normalized space — fills and
    /// strokes both, in the order they are to be drawn.
    private let vertices: [Vertex]

    public init(vm: InertiaViewModel, vertices: [Vertex]) {
        self.vm = vm
        self.vertices = vertices
    }

    private func makeRenderer() -> InertiaVertexRenderer {
        InertiaVertexRenderer(frame: .zero, device: vm.device, vertices: vertices)
    }

    #if os(macOS)
    public typealias NSViewType = InertiaVertexRenderer

    public func makeNSView(context: Context) -> NSViewType {
        makeRenderer()
    }

    public func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.vertices = vertices
    }
    #elseif os(iOS)
    public typealias UIViewType = InertiaVertexRenderer

    public func makeUIView(context: Context) -> UIViewType {
        makeRenderer()
    }

    public func updateUIView(_ uiView: UIViewType, context: Context) {
        uiView.vertices = vertices
    }
    #endif
}

/// Everything an actionable draws behind itself: its shapes, laid out on as
/// many canvases as they need.
///
/// A shape with no animation of its own is backdrop — it belongs to the
/// actionable, moves only as the actionable moves, and shares one canvas with
/// every other shape like it, fitted to the box they occupy together. A shape
/// that *was* given an animation is a drawing in its own right: it gets a
/// canvas of its own, fitted to itself, so its track can scale, turn, move and
/// fade it without disturbing the actionable or any of the other shapes.
///
/// The animated ones are drawn over the backdrop, in the order they were
/// authored — the shapes have no z-index of their own, and the file's order is
/// the only ordering anyone has expressed.

/// What a shape needs in order to be picked and dragged in the editor, over and
/// above being drawn.
///
/// Nil in a shipped build and whenever the editor has the viewport out of
/// actionable mode — a shape is then a backdrop and nothing more, which is what
/// `InertiaShapesView` draws without any of this.
struct InertiaShapeEditing {
    /// Whether this shape is one the editor has picked. Selected by the shape's
    /// own id, which is what a selection carries — see `InertiaShape.id`.
    let isSelected: (InertiaShape) -> Bool
    /// Which property a gesture on a selected shape authors, as picked in the
    /// editor's toolbar. The same tool the actionables are edited with: there is
    /// one palette, and a shape is edited through it exactly as a view is.
    let tool: InertiaTool
    /// The container's named coordinate space, which the drags report in.
    let containerSpace: String?
    /// The actionable's own transform and box, which the shapes are drawn
    /// inside of. See `InertiaToolHandles.outer`.
    let outer: InertiaOuterTransform
    /// What the gesture on this shape has produced so far, held by the
    /// actionable so it survives the canvas being rebuilt mid-drag.
    let edit: (InertiaShape) -> InertiaToolEdit
    let onChange: (InertiaShape, InertiaToolEdit) -> Void
    let onEnded: (InertiaShape) -> Void
    /// Picks the shape a press landed on up, or puts it down again — the same
    /// toggle a tap on an actionable runs, on the same selection.
    let onTap: (InertiaShape) -> Void
}

struct InertiaShapesView: View {
    let vm: InertiaViewModel
    let shapes: [InertiaShape]
    /// The actionable's laid-out box. What a shape's coordinates are multiples
    /// of is the shorter of its two sides — see `unit`.
    let size: CGSize
    /// The container's box — what a translation of 1 crosses. The same measure
    /// an actionable's own animation is offset by, so a shape and the view it
    /// backs travel the same distance for the same authored number.
    let containerSize: CGSize
    /// Where a track has got to, asked of the actionable rather than worked out
    /// in here: playing, pausing and scrubbing are one read at the playhead,
    /// and the actionable is what holds the clock.
    let values: (InertiaAnimationSchema) -> InertiaAnimationValues
    /// Present only in the editor, and only while the viewport is in actionable
    /// mode. See `InertiaShapeEditing`.
    var editing: InertiaShapeEditing? = nil

    /// What a move on a shape was opened on.
    private struct ShapeDrag {
        /// The axis the arrow the press landed on pins this move to, or `nil` for
        /// a press on the shape's own box, which is free in both.
        let axis: InertiaTranslateAxis?
    }

    /// The move in progress, or nil between them. One slot rather than one per
    /// shape: a drag is a pointer, and there is only ever the one.
    @State private var shapeDrag: ShapeDrag? = nil

    /// The length a shape's coordinates are multiples of, across and down
    /// alike: the shorter side of the actionable's box.
    ///
    /// One length rather than two is what keeps a described vector the shape it
    /// was described as. Scaling x by the view's width and y by its height puts
    /// a shape in a square space that is then stretched to fit the view, so a
    /// circle of size 1 came out an oval on every view that was not itself
    /// square, and the taller or wider the view the further from round it got.
    /// Measured against one side, a circle is round, a square is square, and a
    /// shape keeps its proportions at every size that view takes.
    ///
    /// The shorter side rather than the longer one, so a shape authored at 1
    /// still fits inside the view it backs in both directions.
    private var unit: CGFloat { min(size.width, size.height) }

    /// Whether a shape is drawn on a canvas of its own rather than sharing the
    /// backdrop.
    ///
    /// A track is one reason — it has to be able to move without dragging every
    /// other shape with it — and being selected is another: the border and the
    /// handles are fitted to one shape's box, and a shape sharing a canvas has
    /// no box of its own to fit them to.
    ///
    /// The third is simply having been asked for, at insert — see
    /// `InertiaShape.ownCanvas`.
    private func isDrawnAlone(_ shape: InertiaShape) -> Bool {
        shape.animation != nil || shape.ownCanvas || editing?.isSelected(shape) == true
    }

    /// The canvases this view stacks, back to front: the shapes in the order
    /// their z-indexes put them in, cut into runs wherever one of them has to be
    /// drawn on a canvas of its own.
    ///
    /// A shape drawn alone is a layer by itself; the shapes between two of those
    /// share one canvas, the way every shape here used to. Cutting the run at
    /// those points is what makes a z-index mean the same thing for a moving
    /// shape as for a still one: canvases are views, views stack in the order
    /// they are declared, so an animated shape can sit *behind* a plain one
    /// rather than always floating over the whole backdrop.
    private var layers: [[InertiaShape]] {
        var layers: [[InertiaShape]] = []
        var isSharedRunOpen = false

        for shape in shapes.stacked {
            if isDrawnAlone(shape) {
                layers.append([shape])
                isSharedRunOpen = false
            } else if isSharedRunOpen {
                layers[layers.count - 1].append(shape)
            } else {
                layers.append([shape])
                isSharedRunOpen = true
            }
        }

        return layers
    }

    var body: some View {
        if size.width > 0, size.height > 0 {
            // Centred, because the centre of the actionable is where a shape's
            // own coordinates are measured from: a described vector's outline is
            // drawn about the origin, so a shape half the size of its view sits
            // in the middle of it rather than hanging off a corner.
            ZStack(alignment: .center) {
                ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                    if layer.count == 1, let alone = layer.first, isDrawnAlone(alone) {
                        canvas(
                            for: layer,
                            animatedBy: alone.animation.map { values($0) } ?? .identity,
                            editedBy: alone
                        )
                    } else {
                        canvas(for: layer, animatedBy: .identity)
                    }
                }
            }
        }
    }

    /// One canvas holding `shapes`, sized and placed by the box they occupy and
    /// then moved by `transform`.
    ///
    /// The box is what the canvas is fitted to — see `Collection.bounds` — so a
    /// shape reaching past the actionable grows the canvas rather than being cut
    /// at any edge. The transform is stacked in the same order an actionable's
    /// own animation is applied in, and the box's offset is folded into the
    /// track's translation so the shape is moved from where it was authored
    /// rather than from the actionable's centre.
    ///
    /// That offset is the box's *middle* rather than its near corner, because
    /// the canvas is placed by its centre: where the shapes sit relative to the
    /// origin they were drawn about is exactly where the canvas sits relative to
    /// the middle of the view.
    ///
    /// The drawing itself takes no hits: this is a backdrop, and would otherwise
    /// swallow taps meant for the views it overlaps. The selection chrome, which
    /// is the one thing here that is not backdrop, stays hittable.
    @ViewBuilder
    private func canvas(
        for shapes: [InertiaShape],
        animatedBy transform: InertiaAnimationValues,
        editedBy shape: InertiaShape? = nil
    ) -> some View {
        if let bounds = shapes.bounds {
            // The gesture in progress folded in, so the shape and its chrome
            // travel with the pointer rather than waiting for the editor to
            // write the take back. Mirrors `InertiaEditable.displayedValues`.
            let edit = shape.map { editing?.edit($0) ?? .none } ?? .none
            let values = transform.applying(edit, containerSize: containerSize)
            let box = CGSize(width: bounds.width * unit, height: bounds.height * unit)

            InertiaCanvas(
                vm: vm,
                vertices: shapes.flatMap { $0.triangles(normalizedTo: bounds) }
            )
            .allowsHitTesting(false)
            .frame(width: box.width, height: box.height)
            // Under the chrome, so a knob or the move tool's own body sitting
            // over a shape is what a press there grabs. Inside the transforms
            // below for the same reason the chrome is: SwiftUI carries a press
            // back out through them, so what arrives here is already in the
            // space the artwork was drawn in.
            .overlay { pickArea(for: shapes, bounds: bounds) }
            // Inside every transform below, so the chrome stays glued to the
            // shape as it turns and scales — exactly where an actionable's sits
            // relative to its own.
            .overlay { selectionChrome(for: shape, bounds: bounds, box: box, values: values) }
            .scaleEffect(values.scale)
            .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
            .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
            .offset(
                x: bounds.midX * unit + values.translate.width * containerSize.width,
                y: bounds.midY * unit + values.translate.height * containerSize.height
            )
            .opacity(values.opacity)
        }
    }

    /// What listens for a press on one canvas, so a shape can be picked by
    /// touching it rather than only by finding its row in the editor's
    /// hierarchy.
    ///
    /// Nothing at all outside the editor: a shape is backdrop in a shipped
    /// build, and a backdrop that took touches would swallow the taps meant for
    /// the views it sits behind.
    ///
    /// The hit region is the artwork rather than the canvas's box — see
    /// `InertiaShapesHitArea` — which is what lets a press land on a shape at
    /// all. A canvas is fitted to the box its shapes occupy together, and that
    /// box is mostly *not* shape: a press in the corner beside a circle, or in
    /// the margin beside a triangle's slope, has to go on through to the view
    /// underneath exactly as it did before any of this existed.
    ///
    /// One layer for the whole canvas rather than one per shape, because the
    /// shapes sharing it share a vertex buffer and have no boxes of their own to
    /// hang a gesture off. Which of them was pressed is answered by testing the
    /// point, which is also the only way to answer it for a *nested* shape —
    /// drawn into its parent's buffer, and a row of its own in the hierarchy all
    /// the same.
    @ViewBuilder
    private func pickArea(for shapes: [InertiaShape], bounds: CGRect) -> some View {
        if let editing {
            Color.clear
                .contentShape(
                    InertiaShapesHitArea(
                        triangles: shapes.flatMap { $0.triangles(normalizedTo: bounds) }
                    )
                )
                .onTapGesture { location in
                    // Back into the units the shapes are authored in: the canvas
                    // is `unit` points to the shape's 1, and its own top-left
                    // corner is wherever the box they occupy together begins.
                    guard unit > 0 else { return }

                    let point = InertiaPoint(
                        x: bounds.minX + location.x / unit,
                        y: bounds.minY + location.y / unit
                    )

                    guard let shape = shapes.hitTest(point) else { return }
                    editing.onTap(shape)
                }
        }
    }

    /// The border and handles a selected shape grows: the same green box an
    /// actionable shows, and the same chrome for whichever tool is active.
    ///
    /// A shape is picked either by pressing it — see `pickArea(for:bounds:)` —
    /// or by finding its row in the editor's hierarchy panel; both write the
    /// same selection, and only a shape already in it grows any of this.
    ///
    /// The move tool has no chrome of its own beyond its two axis arrows, so the
    /// shape's own box is what a free move is dragged by — the way an
    /// actionable's body is. Every other tool edits through a knob.
    @ViewBuilder
    private func selectionChrome(
        for shape: InertiaShape?,
        bounds: CGRect,
        box: CGSize,
        values: InertiaAnimationValues
    ) -> some View {
        if let shape, let editing, editing.isSelected(shape) {
            // The shape's box in the container's space, as laid out: where the
            // actionable was laid out, plus where in it the shape sits. Measured
            // outside both transforms, which is the frame the handles turn about.
            //
            // Where in it is measured from the middle, because that is the
            // origin a shape's coordinates are drawn about — the same half-view
            // step the canvas itself is placed by.
            let layoutFrame = CGRect(
                x: editing.outer.layoutFrame.minX + size.width / 2 + bounds.minX * unit,
                y: editing.outer.layoutFrame.minY + size.height / 2 + bounds.minY * unit,
                width: box.width,
                height: box.height
            )

            Rectangle()
                .strokeBorder(Color.green, lineWidth: 2)
                .allowsHitTesting(false)

            let handles = InertiaToolHandles(
                tool: editing.tool,
                values: values,
                layoutFrame: layoutFrame,
                containerSize: containerSize,
                containerSpace: editing.containerSpace,
                outer: editing.outer,
                onChange: { editing.onChange(shape, $0) },
                onEnded: { editing.onEnded(shape) }
            )

            if editing.tool == .translate {
                // The move tool's chrome carries no gesture of its own — see
                // `InertiaTranslateAxes` — so the drag that runs it has to be
                // above the arrows rather than beside them: a press on an arrow
                // hangs outside the shape's box, finds no gesture there, and is
                // offered to this one. The shape's own box is under them, which
                // is the free move.
                //
                // The arrows over the clear body rather than beneath it, so a
                // press near an edge grabs the arrow it landed on rather than
                // the box behind it.
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                    handles
                }
                .gesture(translateGesture(for: shape, editing: editing, layoutFrame: layoutFrame, values: values))
                // The body this move is dragged by covers the shape, and it is
                // above the layer a press would otherwise be picked off — so
                // without this there is no way to put a picked shape back down
                // while the move tool is up. No contest with the drag: a
                // `DragGesture` does not open until the press has travelled its
                // minimum distance, and a tap by definition has not.
                .onTapGesture { editing.onTap(shape) }
            } else {
                handles
            }
        }
    }

    /// A move on a selected shape, free or pinned to one of the move tool's two
    /// axis arrows.
    ///
    /// The drag is reported in the container's space, which is where the arrows
    /// are placed and so the only space a press can be tested against. What it
    /// authors is an offset stacked *inside* the actionable's transform, so the
    /// screen-space drag is pinned to its axis first and only then carried back
    /// through that transform — see `InertiaAnimationValues.unapplying`. Pinning
    /// after would pin it to an axis of the actionable's rather than the
    /// screen's.
    private func translateGesture(
        for shape: InertiaShape,
        editing: InertiaShapeEditing,
        layoutFrame: CGRect,
        values: InertiaAnimationValues
    ) -> some Gesture {
        func translate(_ drag: ShapeDrag, by translation: CGSize) -> InertiaToolEdit {
            InertiaToolEdit(
                translate: editing.outer.values.unapplying(drag.axis?.constrain(translation) ?? translation)
            )
        }

        return DragGesture(coordinateSpace: .named(editing.containerSpace ?? ""))
            .onChanged { value in
                let drag = shapeDrag ?? beginDrag(at: value.startLocation, editing: editing, layoutFrame: layoutFrame, values: values)
                editing.onChange(shape, translate(drag, by: value.translation))
            }
            .onEnded { value in
                let drag = shapeDrag ?? beginDrag(at: value.startLocation, editing: editing, layoutFrame: layoutFrame, values: values)
                editing.onChange(shape, translate(drag, by: value.translation))
                shapeDrag = nil
                editing.onEnded(shape)
            }
    }

    /// Opens a move, keyed off the axis arrow the press landed on — if any — as
    /// the arrows are drawn right now, before this gesture has moved anything.
    ///
    /// Taken once rather than tested per event, because this gesture is what
    /// carries the arrow away from the press that grabbed it. Assigned during
    /// `onChanged`, which is what makes the first event of a gesture the one that
    /// opens it. Mirrors `InertiaEditable.beginBodyDrag(at:)`.
    private func beginDrag(
        at location: CGPoint,
        editing: InertiaShapeEditing,
        layoutFrame: CGRect,
        values: InertiaAnimationValues
    ) -> ShapeDrag {
        // Where the shape's box is drawn in the container, and how big: carried
        // out through both the transforms it sits inside, its own and then the
        // actionable's, the way `InertiaToolHandles` carries a gesture's anchor
        // out. That drawn box is what the arrows are placed around.
        let center = editing.outer.values.drawnContainerPoint(
            values.drawnPoint(
                CGPoint(x: layoutFrame.width / 2, y: layoutFrame.height / 2),
                in: layoutFrame,
                containerSize: containerSize
            ),
            in: editing.outer.layoutFrame,
            containerSize: containerSize
        )
        let scale = values.scale * editing.outer.values.scale

        let drag = ShapeDrag(
            axis: InertiaTranslateAxes.axis(
                at: location,
                drawnCenter: center,
                drawnSize: CGSize(width: layoutFrame.width * scale, height: layoutFrame.height * scale)
            )
        )

        shapeDrag = drag
        return drag
    }
}

/// One canvas's artwork as a path, which is what a press on it is tested
/// against.
///
/// The same triangles the renderer draws, read three corners at a time and in
/// the same 0...1 space, so the region that answers a press is exactly the
/// region that was painted — holes in it and all. A shape drawn as its outline
/// alone encloses nothing in the middle, and a press through there falls to
/// whatever is behind rather than to the ring around it.
///
/// Wound as the shapes were authored and filled by the non-zero rule, so
/// triangles overlapping — a stroke lying over the fill it encloses — add up
/// rather than cancelling out.
///
/// Public because the editor draws the same canvases on a stage of its own and
/// picks shapes off them the same way — see `ShapeCanvasView`.
public struct InertiaShapesHitArea: Shape {
    /// Every shape on the canvas already flattened into the one triangle list
    /// it draws, in the canvas's own normalized space.
    public let triangles: [Vertex]

    public init(triangles: [Vertex]) {
        self.triangles = triangles
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // A trailing corner or two is dropped rather than closed into a triangle
        // of its own, which is what the renderer does with it as well.
        for index in stride(from: 0, to: triangles.count - triangles.count % 3, by: 3) {
            let corner = { (offset: Int) in
                CGPoint(
                    x: rect.minX + triangles[index + offset].position.x * rect.width,
                    y: rect.minY + triangles[index + offset].position.y * rect.height
                )
            }

            path.move(to: corner(0))
            path.addLine(to: corner(1))
            path.addLine(to: corner(2))
            path.closeSubpath()
        }

        return path
    }
}

#if os(macOS)
public typealias NativeView = NSView
public typealias HostingController = NSHostingController
#elseif os(iOS)
public typealias NativeView = UIView
public typealias HostingController = UIHostingController
#endif

public class TouchForwardingComponent<Component: View>: NativeView {
    let interactive: Bool
    let component: Component
    private let hostingController: HostingController<Component>

    public init(interactive: Bool, component: () -> Component, frame: CGRect? = nil) {
        self.interactive = interactive
        self.component = component()
        hostingController = HostingController(rootView: self.component)
        #if os(macOS)

        #elseif os(iOS)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.isUserInteractionEnabled = interactive
        #endif

        super.init(frame: frame ?? hostingController.view.frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if os(macOS)
    private func setup() {
        let swiftUIView = hostingController.view
        swiftUIView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swiftUIView)

        NSLayoutConstraint.activate([
            swiftUIView.topAnchor.constraint(equalTo: topAnchor),
            swiftUIView.bottomAnchor.constraint(equalTo: bottomAnchor),
            swiftUIView.leadingAnchor.constraint(equalTo: leadingAnchor),
            swiftUIView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

//        self.backgroundColor = .clear
//        self.isOpaque = false
//        self.isUserInteractionEnabled = self.interactive
    }
    #elseif os(iOS)
    private func setup() {
        guard let swiftUIView = hostingController.view else { return }
        swiftUIView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swiftUIView)

        NSLayoutConstraint.activate([
            swiftUIView.topAnchor.constraint(equalTo: topAnchor),
            swiftUIView.bottomAnchor.constraint(equalTo: bottomAnchor),
            swiftUIView.leadingAnchor.constraint(equalTo: leadingAnchor),
            swiftUIView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        self.backgroundColor = .clear
        self.isOpaque = false
        self.isUserInteractionEnabled = self.interactive
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> NativeView? {
        // Forward the touch to the SwiftUI view if it's within bounds
        let view = super.hitTest(point, with: event)
        if view == self {
            return hostingController.view?.hitTest(point, with: event)
        }
        return view
    }
    #endif


}
