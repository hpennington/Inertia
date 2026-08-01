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
    private let shapes: [InertiaShape]

    public init(vm: InertiaViewModel, shapes: [InertiaShape]) {
        self.vm = vm
        self.shapes = shapes
    }

    /// Every shape flattened into the one triangle list the renderer draws.
    private var vertices: [Vertex] {
        shapes.flatMap { $0.triangles }
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
struct InertiaShapesView: View {
    let vm: InertiaViewModel
    let shapes: [InertiaShape]
    /// The actionable's laid-out box: the unit the shapes' coordinates are
    /// multiples of, so a shape saying 1 is exactly this wide.
    let size: CGSize
    /// The container's box — what a translation of 1 crosses. The same measure
    /// an actionable's own animation is offset by, so a shape and the view it
    /// backs travel the same distance for the same authored number.
    let containerSize: CGSize
    /// Where a track has got to, asked of the actionable rather than worked out
    /// in here: playing, pausing and scrubbing are one read at the playhead,
    /// and the actionable is what holds the clock.
    let values: (InertiaAnimationSchema) -> InertiaAnimationValues

    var body: some View {
        if size.width > 0, size.height > 0 {
            // Top-left, because that corner is where the shapes' own box is
            // measured and offset from.
            ZStack(alignment: .topLeading) {
                canvas(for: shapes.filter { $0.animation == nil }, animatedBy: .identity)

                ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                    if let animation = shape.animation {
                        canvas(for: [shape], animatedBy: values(animation))
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
    /// rather than from the actionable's corner.
    ///
    /// Takes no hits: this is a backdrop, and would otherwise swallow taps meant
    /// for the views it overlaps.
    @ViewBuilder
    private func canvas(for shapes: [InertiaShape], animatedBy transform: InertiaAnimationValues) -> some View {
        if let bounds = shapes.bounds {
            InertiaCanvas(
                vm: vm,
                shapes: shapes.map { $0.normalized(to: bounds) }
            )
            .frame(width: bounds.width * size.width, height: bounds.height * size.height)
            .scaleEffect(transform.scale)
            .rotationEffect(Angle(degrees: transform.rotate), anchor: .topLeading)
            .rotationEffect(Angle(degrees: transform.rotateCenter), anchor: .center)
            .offset(
                x: bounds.minX * size.width + transform.translate.width * containerSize.width,
                y: bounds.minY * size.height + transform.translate.height * containerSize.height
            )
            .opacity(transform.opacity)
            .allowsHitTesting(false)
        }
    }
}

public struct MetalCanvasNode: Equatable, Codable {
    public let id: InertiaID
    public let vertices: [Vertex]
    public let zIndex: Int
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
