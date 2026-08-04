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

    /// The border and handles a selected shape grows: the same green box an
    /// actionable shows, and the same chrome for whichever tool is active.
    ///
    /// Only a shape the editor has already picked grows any of this, and picking
    /// happens in the hierarchy panel rather than out here — a shape is drawn
    /// behind the app's own views, and it stays behind them.
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

            InertiaToolHandles(
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
                // A free move, dragged by the shape itself. The drag is reported
                // in the container's space and the offset it feeds lands inside
                // the actionable's transform, so it is carried back through that
                // before being applied — see `InertiaAnimationValues.unapplying`.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .named(editing.containerSpace ?? ""))
                            .onChanged { value in
                                editing.onChange(
                                    shape,
                                    InertiaToolEdit(translate: editing.outer.values.unapplying(value.translation))
                                )
                            }
                            .onEnded { value in
                                editing.onChange(
                                    shape,
                                    InertiaToolEdit(translate: editing.outer.values.unapplying(value.translation))
                                )
                                editing.onEnded(shape)
                            }
                    )
            }
        }
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
