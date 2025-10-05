////
////  InertiaCanvas.swift
////
////
////  Created by Hayden Pennington on 7/5/24.
////
//
//import SwiftUI
//
//#if os(macOS)
//typealias ViewRepresentable = NSViewRepresentable
//#elseif os(iOS)
//typealias ViewRepresentable = UIViewRepresentable
//#endif
//
//public struct InertiaCanvas: ViewRepresentable {
//    
//    @Environment(\.inertiaDataModel) var inertiaDataModel
//    #if os(macOS)
//    public typealias NSViewType = NSView
//    
//    public func makeNSView(context: Context) -> NSViewType {
//        let frame = CGRect(origin: .zero, size: self.size)
//        let rootView = NSViewType(frame: frame)
////        rootView.backgroundColor = .clear
////        rootView.isOpaque = false
////        rootView.isUserInteractionEnabled = true
////        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.hitTest(sender:)))
////        rootView.addGestureRecognizer(tapGesture)
//        
//        var topViewVertices: [Vertex] = []
//        
//        guard let inertiaDataModel else {
//            return rootView
//        }
//        
//        for object in inertiaDataModel.inertiaSchema.objects {
//            if object.objectType == .shape {
//                let maxZIndex = inertiaDataModel.inertiaSchema.objects.map {
//                    $0.zIndex
//                }.max() ?? .zero
//                
//                if object.zIndex == maxZIndex && object.shape == "triangle" {
//                    let shape = TriangleNode(
//                        id: object.id,
//                        animationValues: .zero,
//                        zIndex: object.zIndex,
//                        size: object.width,
//                        center: CGPoint(x: object.position.x * object.width, y: object.position.y * object.height),
//                        color: CGColor(red: object.color[0], green: object.color[1], blue: object.color[2], alpha: object.color[3])
//                    )
//                    topViewVertices.append(contentsOf: shape.vertices)
//                }
//            }
//        }
//        
//        let wrappedSwiftUIView = TouchForwardingComponent(interactive: true, component: {view}, frame: frame)
//        let topVertexRenderer = VertexRenderer(
//            frame: frame,
//            device: vm.device,
//            vertices: topViewVertices
//        )
//        
//        context.coordinator.topVertexRenderer = topVertexRenderer
//        
//        rootView.addSubview(wrappedSwiftUIView)
//        rootView.addSubview(topVertexRenderer)
//        
//        wrappedSwiftUIView.translatesAutoresizingMaskIntoConstraints = false
//        topVertexRenderer.translatesAutoresizingMaskIntoConstraints = false
//        
//        NSLayoutConstraint.activate([
//            wrappedSwiftUIView.topAnchor.constraint(equalTo: rootView.topAnchor),
//            wrappedSwiftUIView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
//            wrappedSwiftUIView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
//            wrappedSwiftUIView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
//        ])
//        
//        NSLayoutConstraint.activate([
//            topVertexRenderer.topAnchor.constraint(equalTo: rootView.topAnchor),
//            topVertexRenderer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
//            topVertexRenderer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
//            topVertexRenderer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
//        ])
//                
//        return rootView
//    }
//    
//    public func updateNSView(_ nsView: NSViewType, context: Context) {
//        let frame = CGRect(origin: .zero, size: self.size)
//        
//        guard let inertiaDataModel else {
//            return
//        }
//        
//        var topViewVertices: [Vertex] = []
//        for object in inertiaDataModel.inertiaSchema.objects {
//            if object.objectType == .shape {
//                let maxZIndex = inertiaDataModel.inertiaSchema.objects.map {
//                    $0.zIndex
//                }.max() ?? .zero
//                
//                if object.zIndex == maxZIndex && object.shape == "triangle" {
//                    let shape = TriangleNode(
//                        id: object.id,
//                        animationValues: .zero,
//                        zIndex: object.zIndex,
//                        size: object.width,
//                        center: CGPoint(x: object.position.x * object.width, y: object.position.y * object.height),
//                        color: CGColor(red: object.color[0], green: object.color[1], blue: object.color[2], alpha: object.color[3])
//                    )
//                    topViewVertices.append(contentsOf: shape.vertices)
//                }
//            }
//        }
//        
//        context.coordinator.topVertexRenderer?.vertices = topViewVertices
//    }
//    #elseif os(iOS)
//    public typealias UIViewType = UIView
//    
//    public func makeUIView(context: Context) -> UIViewType {
//        let frame = CGRect(origin: .zero, size: self.size)
//        let rootView = UIViewType(frame: frame)
//        rootView.backgroundColor = .clear
//        rootView.isOpaque = false
//        rootView.isUserInteractionEnabled = true
//        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.hitTest(sender:)))
//        rootView.addGestureRecognizer(tapGesture)
//        
//        guard let inertiaDataModel else {
//            return rootView
//        }
//        
//        var topViewVertices: [Vertex] = []
//        for object in inertiaDataModel.inertiaSchema.objects {
//            if object.objectType == .shape {
//                let maxZIndex = inertiaDataModel.inertiaSchema.objects.map {
//                    $0.zIndex
//                }.max() ?? .zero
//                
//                if object.zIndex == maxZIndex && object.shape == "triangle" {
//                    let shape = TriangleNode(
//                        id: object.id,
//                        animationValues: .zero,
//                        zIndex: object.zIndex,
//                        size: object.width,
//                        center: CGPoint(x: object.position.x * object.width, y: object.position.y * object.height),
//                        color: CGColor(red: object.color[0], green: object.color[1], blue: object.color[2], alpha: object.color[3])
//                    )
//                    topViewVertices.append(contentsOf: shape.vertices)
//                }
//            }
//        }
//        
//        let wrappedSwiftUIView = TouchForwardingComponent(interactive: true, component: {view}, frame: frame)
//        let topVertexRenderer = VertexRenderer(
//            frame: frame,
//            device: vm.device,
//            vertices: topViewVertices
//        )
//        
//        context.coordinator.topVertexRenderer = topVertexRenderer
//        
//        rootView.addSubview(wrappedSwiftUIView)
//        rootView.addSubview(topVertexRenderer)
//        
//        wrappedSwiftUIView.translatesAutoresizingMaskIntoConstraints = false
//        topVertexRenderer.translatesAutoresizingMaskIntoConstraints = false
//        
//        NSLayoutConstraint.activate([
//            wrappedSwiftUIView.topAnchor.constraint(equalTo: rootView.topAnchor),
//            wrappedSwiftUIView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
//            wrappedSwiftUIView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
//            wrappedSwiftUIView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
//        ])
//        
//        NSLayoutConstraint.activate([
//            topVertexRenderer.topAnchor.constraint(equalTo: rootView.topAnchor),
//            topVertexRenderer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
//            topVertexRenderer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
//            topVertexRenderer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
//        ])
//                
//        return rootView
//    }
//    
//    public func updateUIView(_ uiView: UIViewType, context: Context) {
//        let frame = CGRect(origin: .zero, size: self.size)
//        
//        guard let inertiaDataModel else {
//            return
//        }
//        
//        var topViewVertices: [Vertex] = []
//        for object in inertiaDataModel.inertiaSchema.objects {
//            if object.objectType == .shape {
//                let maxZIndex = inertiaDataModel.inertiaSchema.objects.map {
//                    $0.zIndex
//                }.max() ?? .zero
//                
//                if object.zIndex == maxZIndex && object.shape == "triangle" {
//                    let shape = TriangleNode(
//                        id: object.id,
//                        animationValues: .zero,
//                        zIndex: object.zIndex,
//                        size: object.width,
//                        center: CGPoint(x: object.position.x * object.width, y: object.position.y * object.height),
//                        color: CGColor(red: object.color[0], green: object.color[1], blue: object.color[2], alpha: object.color[3])
//                    )
//                    topViewVertices.append(contentsOf: shape.vertices)
//                }
//            }
//        }
//        
//        context.coordinator.topVertexRenderer?.vertices = topViewVertices
//    }
//    #endif
//    
//    private let size: CGSize
//    private let vm: InertiaViewModel
//    private let view: AnyView
//    private let commandQueue: MTLCommandQueue
//    
//    public init(size: CGSize, vm: InertiaViewModel, view: AnyView) {
//        self.size = size
//        self.vm = vm
//        self.view = view
//        self.commandQueue = vm.device.makeCommandQueue()!
//    }
//    
//    public func makeCoordinator() -> Coordinator {
//        Coordinator()
//    }
//    
//    private func collateZIndices() -> [Int] {
//        guard let inertiaDataModel else {
//            return []
//        }
//        
//        return Set(inertiaDataModel.inertiaSchema.objects.map({$0.zIndex})).sorted(by: <)
//    }
//    
//    public class Coordinator: NSObject {
//        public var topVertexRenderer: VertexRenderer? = nil
//                
//        #if os(macOS)
////        @objc public func hitTest(sender: NSTapGestureRecognizer) {
////            print(sender)
////        }
//        #elseif os(iOS)
//        @objc public func hitTest(sender: UITapGestureRecognizer) {
//            print(sender)
//        }
//        #endif
//    }
//}
//
//public protocol MetalCanvasNode {
//    var id: InertiaID { get }
//    var animationValues: InertiaAnimationValues { get }
//    var vertices: [Vertex] { get }
//    var zIndex: Int { get }
//}
//
//#if os(macOS)
//public typealias NativeView = NSView
//public typealias HostingController = NSHostingController
//#elseif os(iOS)
//public typealias NativeView = UIView
//public typealias HostingController = UIHostingController
//#endif
//
//public class TouchForwardingComponent<Component: View>: NativeView {
//    let interactive: Bool
//    let component: Component
//    private let hostingController: HostingController<Component>
//
//    public init(interactive: Bool, component: () -> Component, frame: CGRect? = nil) {
//        self.interactive = interactive
//        self.component = component()
//        hostingController = HostingController(rootView: self.component)
//        #if os(macOS)
//
//        #elseif os(iOS)
//        hostingController.view.backgroundColor = .clear
//        hostingController.view.isOpaque = false
//        hostingController.view.isUserInteractionEnabled = interactive
//        #endif
//        
//        super.init(frame: frame ?? hostingController.view.frame)
//        setup()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//    
//    #if os(macOS)
//    private func setup() {
//        let swiftUIView = hostingController.view
//        swiftUIView.translatesAutoresizingMaskIntoConstraints = false
//        addSubview(swiftUIView)
//
//        NSLayoutConstraint.activate([
//            swiftUIView.topAnchor.constraint(equalTo: topAnchor),
//            swiftUIView.bottomAnchor.constraint(equalTo: bottomAnchor),
//            swiftUIView.leadingAnchor.constraint(equalTo: leadingAnchor),
//            swiftUIView.trailingAnchor.constraint(equalTo: trailingAnchor)
//        ])
//        
////        self.backgroundColor = .clear
////        self.isOpaque = false
////        self.isUserInteractionEnabled = self.interactive
//    }
//    #elseif os(iOS)
//    private func setup() {
//        guard let swiftUIView = hostingController.view else { return }
//        swiftUIView.translatesAutoresizingMaskIntoConstraints = false
//        addSubview(swiftUIView)
//
//        NSLayoutConstraint.activate([
//            swiftUIView.topAnchor.constraint(equalTo: topAnchor),
//            swiftUIView.bottomAnchor.constraint(equalTo: bottomAnchor),
//            swiftUIView.leadingAnchor.constraint(equalTo: leadingAnchor),
//            swiftUIView.trailingAnchor.constraint(equalTo: trailingAnchor)
//        ])
//        
//        self.backgroundColor = .clear
//        self.isOpaque = false
//        self.isUserInteractionEnabled = self.interactive
//    }
//    
//    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> NativeView? {
//        // Forward the touch to the SwiftUI view if it's within bounds
//        let view = super.hitTest(point, with: event)
//        if view == self {
//            return hostingController.view?.hitTest(point, with: event)
//        }
//        return view
//    }
//    #endif
//
//
//}
