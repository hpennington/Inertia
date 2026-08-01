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

public protocol MetalCanvasNode {
    var id: InertiaID { get }
    var animationValues: InertiaAnimationValues { get }
    var vertices: [Vertex] { get }
    var zIndex: Int { get }
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
