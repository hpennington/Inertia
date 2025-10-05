//
// Inertia SwiftUI animation library
// Created by Hayden Pennington
//
// Copyright (c) 2024 Vector Studio. All rights reserved.
//

import SwiftUI

public typealias InertiaID = String

public class Node: Identifiable, Hashable, Codable, Equatable, CustomStringConvertible {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public let id: String
    public weak var parent: Node?
    public var children: [Node]? = []
    public weak var tree: Tree? = nil
    
    init(id: String, parentId: String? = nil) {
        self.id = id
        self.parentId = parentId
    }
    
    func addChild(_ child: Node) {
        child.parent = self
        child.parentId = self.id
        children?.append(child)
    }
    
    public var description: String {
"""
{"id": \(id), "parentId": \(parentId), "children": \(children?.map {$0.id})}
"""
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case parentId = "parentId"
        case children
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        children = try container.decodeIfPresent([Node].self, forKey: .children)
    }
    
    private var parentId: String? = nil
    
    public func link() {
        if let parentId {
            self.parent = tree!.nodeMap[parentId]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(parentId, forKey: .parentId) // Encode only the parent's ID
        try container.encode(children, forKey: .children)
    }
}

public class Tree: Identifiable, Hashable, Codable, CustomStringConvertible, Equatable {
    public static func == (lhs: Tree, rhs: Tree) -> Bool {
        return lhs.rootNode == rhs.rootNode
    }
    
    required public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.nodeMap = try container.decode([String : Node].self, forKey: .nodeMap)
        self.rootNode = try container.decodeIfPresent(Node.self, forKey: .rootNode)
    }
    
    enum CodingKeys: CodingKey {
        case id
        case nodeMap
        case rootNode
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.nodeMap, forKey: .nodeMap)
        try container.encodeIfPresent(self.rootNode, forKey: .rootNode)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(nodeMap)
    }
    
    public let id: String
    
    init(id: String) {
        self.id = id
    }
    
    public var nodeMap: [String: Node] = [:]
    public var rootNode: Node?

    func addRelationship(id: String, parentId: String?, parentIsContainer: Bool) {
        // Get or create the current node
        let currentNode = nodeMap[id] ?? {
            let newNode = Node(id: id, parentId: parentId)
            nodeMap[id] = newNode
            return newNode
        }()

        if let parentId = parentId {
            // Get or create the parent node
            let parentNode = nodeMap[parentId] ?? {
                let newNode = Node(id: parentId)
                nodeMap[parentId] = newNode
                return newNode
            }()

            if parentIsContainer {
                // If explicitly marked as root, set it as the root node
                // Establish parent-child relationship
                parentNode.addChild(currentNode)
                rootNode = parentNode
            } else {
                parentNode.addChild(currentNode)
                if rootNode == nil && parentNode.parent == nil {
                    rootNode = parentNode
                }
            }
        }
    }
    
    public var description: String {
"""
{"treeId": \(id), "root": \(rootNode)}
"""
    }
}


private struct InertiaDataModelKey: EnvironmentKey {
    static let defaultValue: InertiaDataModel? = nil
}

private struct InertiaParentIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct InertiaContainerIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct IsInertiaContainerKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var inertiaDataModel: InertiaDataModel? {
        get { self[InertiaDataModelKey.self] }
        set { self[InertiaDataModelKey.self] = newValue }
    }
    
    var inertiaParentID: String? {
        get {
            self[InertiaParentIDKey.self]
        }
        set {
            self[InertiaParentIDKey.self] = newValue
        }
    }
    
    var inertiaContainerId: String? {
        get {
            self[InertiaContainerIdKey.self]
        }
        set {
            self[InertiaContainerIdKey.self] = newValue
        }
    }
    
    var isInertiaContainer: Bool {
        get {
            self[IsInertiaContainerKey.self]
        }
        set {
            self[IsInertiaContainerKey.self] = newValue
        }
    }
}

//public protocol InertiaDataModel: Equatable {
//    public var objects: [InertiaID: InertiaShape] { get set }
//    public var states: [InertiaID: InertiaAnimationState] { get set }
//}

public final class InertiaViewModel: ObservableObject {
//    public let id: InertiaID
    @Published public var device: MTLDevice = MTLCreateSystemDefaultDevice()!
    public var layerOwner: [Int: InertiaID] = [:]
    
    public init() {
    }
    
    public func updateState(id: InertiaID, isCancelled: Bool? = nil, trigger: Bool? = nil) {
//        if let currentState = self.dataModel.states[id] {
//            if let isCancelled, let trigger {
//                self.dataModel.states.updateValue(InertiaAnimationState(id: currentState.id, trigger: trigger, isCancelled: isCancelled), forKey: currentState.id)
//            } else if let isCancelled {
//                self.dataModel.states.updateValue(InertiaAnimationState(id: currentState.id, trigger: currentState.trigger, isCancelled: isCancelled), forKey: currentState.id)
//            } else if let trigger {
//                self.dataModel.states.updateValue(InertiaAnimationState(id: currentState.id, trigger: trigger, isCancelled: currentState.isCancelled), forKey: currentState.id)
//            }
//        }
    }
    
    public func trigger(_ id: InertiaID) {
        self.updateState(id: id, trigger: true)
    }

    public func cancel(_ id: InertiaID) {
        self.updateState(id: id, isCancelled: true)
    }

    public func restart(_ id: InertiaID) {
        self.updateState(id: id, isCancelled: false)
    }
}

#if os(iOS)
import UIKit
public struct InertiaViewRepresentable: UIViewRepresentable {
    public typealias UIViewType = UIView
    
    let view: () -> UIViewType
    
    public func makeUIView(context: Context) -> UIViewType {
        let view = view()
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        
    }
}
#else
import AppKit
public struct InertiaViewRepresentable: NSViewRepresentable {
    public typealias NSViewType = NSView
    
    let view: () -> NSViewType
    
    public func makeNSView(context: Context) -> NSViewType {
        let view = view()
//        view.isOpaque = false
//        view.backgroundColor = .clear
        return view
    }
    
    public func updateNSView(_ uiView: NSViewType, context: Context) {
        
    }
}
#endif

@Observable
public final class InertiaDataModel{
    public let containerId: InertiaID
    public var inertiaSchema: InertiaAnimationSchema
    public var tree: Tree
    public var actionableIds: Set<String>
    public var states: [InertiaID: InertiaAnimationState]
    public var actionableIdToAnimationIdMap: [String: String] = [:]
    
    public var isActionable: Bool = false
    
    public init(containerId: InertiaID, inertiaSchema: InertiaAnimationSchema, tree: Tree, actionableIds: Set<String>) {
        self.containerId = containerId
        self.inertiaSchema = inertiaSchema
        self.tree = tree
        self.actionableIds = actionableIds
        self.states = [:]
    }
}

struct InertiaEditorEnvironment: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var inertiaEditor: Bool {
        get { self[InertiaEditorEnvironment.self] }
        set { self[InertiaEditorEnvironment.self] = newValue }
    }
}

extension View {
    public func inertiaEditor(_ isEditor: Bool) -> some View {
        environment(\.inertiaEditor, isEditor)
    }
}

public struct InertiaContainer<Content: View>: View {
    let bundle: Bundle
    let dev: Bool
    let id: InertiaID
    let hierarchyId: String
    @State private var inertiaDataModel: InertiaDataModel
    @ViewBuilder let content: () -> Content
    
    public init(
        bundle: Bundle = Bundle.main,
        dev: Bool,
        id: InertiaID,
        hierarchyId: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.bundle = bundle
        self.dev = dev
        self.id = id
        self.hierarchyId = hierarchyId
        self.content = content
        
        // TODO: - Solve error handling when file is missing or schema is wrong
        if dev {
            self._inertiaDataModel = State(
                wrappedValue: InertiaDataModel(containerId: id, inertiaSchema: InertiaSchemaAnimation(), tree: Tree(id: id), actionableIds: Set())
            )
        } else {
            if let url = bundle.url(forResource: id, withExtension: "json") {
                let schemaText = try! String(contentsOf: url, encoding: .utf8)
                if let data = schemaText.data(using: .utf8),
                   let schema = decodeInertiaSchema(json: data) {
                    NSLog("[INERTIA_LOG]: InertiaDataModel instantiated for container: \(id)")
                    self._inertiaDataModel = State(
                        wrappedValue: InertiaDataModel(containerId: id, inertiaSchema: schema, tree: Tree(id: id), actionableIds: Set())
                    )
                } else {
                    NSLog("[INERTIA_LOG]:  Failed to decode the inertia schema")
                    fatalError()
                }
            } else {
                NSLog("[INERTIA_LOG]:  Failed to parse the inertia file")
                fatalError()
            }
        }
    }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .center) {
                content()
                    .environment(\.inertiaParentID, hierarchyId)
                    .environment(\.inertiaDataModel, self.inertiaDataModel)
                    .environment(\.isInertiaContainer, true)
                    .environment(\.inertiaContainerSize, proxy.size)
                    .environment(\.inertiaContainerId, hierarchyId)
                    .environment(\.inertiaEditor, dev)
                    .coordinateSpace(.named(hierarchyId))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollDisabled(self.inertiaDataModel.isActionable)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

public class WebSocketClient {
    var task: URLSessionWebSocketTask? = nil
    var isConnected: Bool = false
    public var messageReceived: ((_ selectedIds: Set<String>) -> Void)? = nil
    public var messageReceivedSchema: ((_ schemas: [InertiaSchemaWrapper]) -> Void)? = nil
    public var messageReceivedIsActionable: ((_ isActionable: Bool) -> Void)? = nil
    static let shared = WebSocketClient()

    init() {

    }
    
    func connect(uri: URL) {
        self.task = URLSession.shared.webSocketTask(with: uri)
        self.task?.resume()
        isConnected = self.task?.state == .completed || self.task?.state == .running || self.task?.state == .suspended
    }
    
    public enum MessageType: String, Codable {
        case actionable
        case actionables
//        case selected
        case translationEnded
        case schema
    }

    public struct MessageWrapper: Codable {
        public let type: MessageType
        public let payload: Data
        
        public init(type: MessageType, payload: Data) {
            self.type = type
            self.payload = payload
        }
    }
    
    public struct MessageActionables: Codable {
        public let tree: Tree
        public let actionableIds: Set<String>
        
        public init(tree: Tree, actionableIds: Set<String>) {
            self.tree = tree
            self.actionableIds = actionableIds
        }
    }
    
    public struct MessageTranslation: Codable {
        public let translationX: CGFloat
        public let translationY: CGFloat
        public let actionableIds: Set<String>
        
        public init(translationX: CGFloat, translationY: CGFloat, actionableIds: Set<String>) {
            self.translationX = translationX
            self.translationY = translationY
            self.actionableIds = actionableIds
        }
    }
    
    public struct MessageActionable: Codable {
        public let isActionable: Bool
        
        public init(isActionable: Bool) {
            self.isActionable = isActionable
        }
    }
    
    public struct MessageSchema: Codable {
        public let schemaWrappers: [InertiaSchemaWrapper]
        
        public init(schemaWrappers: [InertiaSchemaWrapper]) {
            self.schemaWrappers = schemaWrappers
        }
    }
    
    func sendMessage(_ message: MessageActionables) {
        do {
            guard let jsonData = try? JSONEncoder().encode(message) else {
                print("Error: Could not encode JSON to data")
                 return
            }
            
            let messageWrapper = MessageWrapper(type: .actionables, payload: jsonData)
            let messageWrapperData = try JSONEncoder().encode(messageWrapper)

            let messageData = URLSessionWebSocketTask.Message.data(messageWrapperData)
            task?.send(messageData) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                } else {
                    print("Message sent: \(messageData)")
                }
                
                // Begin receiving responses
                if let task = self.task {
                    self.receiveMessage(task: task)
                }
            }
            
        } catch {
            print("Error encoding data: \(error)")
        }
    }
    
    func sendMessage(_ message: MessageSchema) {
        do {
            guard let jsonData = try? JSONEncoder().encode(message) else {
                print("Error: Could not encode JSON to data")
                 return
            }
            
            let messageWrapper = MessageWrapper(type: .schema, payload: jsonData)
            guard let messageWrapperData = try? JSONEncoder().encode(messageWrapper) else {
                return
            }

            let messageData = URLSessionWebSocketTask.Message.data(messageWrapperData)
            task?.send(messageData) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                } else {
                    print("Message sent: \(messageData)")
                }
                
                // Begin receiving responses
                if let task = self.task {
                    self.receiveMessage(task: task)
                }
            }
            
        } catch {
            print("Error encoding data: \(error)")
        }
    }
    
    func sendMessage(_ message: MessageTranslation) {
        do {
            guard let jsonData = try? JSONEncoder().encode(message) else {
                print("Error: Could not encode JSON to data")
                return
            }
            
            let messageWrapper = MessageWrapper(type: .translationEnded, payload: jsonData)
            guard let messageWrapperData = try? JSONEncoder().encode(messageWrapper) else {
                return
            }
            
            let messageData = URLSessionWebSocketTask.Message.data(messageWrapperData)
            task?.send(messageData) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                } else {
                    print("Message sent: \(messageData)")
                }
                
                // Begin receiving responses
                if let task = self.task {
                    self.receiveMessage(task: task)
                }
            }
            
        } catch {
            print("Error encoding data: \(error)")
        }
    }
    
    func receiveMessage(task: URLSessionWebSocketTask) {
        task.receive { result in
            switch result {
            case .failure(let error):
                print("Error receiving message: \(error)")
                task.cancel(with: .normalClosure, reason: nil)
            case .success(let message):
                switch message {
                case .data(let data):
                    guard let messageWrapper = try? JSONDecoder().decode(WebSocketClient.MessageWrapper.self, from: data) else {
                        return
                    }
                    
                    switch messageWrapper.type {
                    case .actionable:
                        guard let actionableMessage = try? JSONDecoder().decode(WebSocketClient.MessageActionable.self, from: messageWrapper.payload) else {
                            return
                        }
                        
                        NSLog("[INERTIA_LOG]:  Received message (data): \(actionableMessage)")
                        self.messageReceivedIsActionable?(actionableMessage.isActionable)
                    case .actionables:
                        let msg = try! JSONDecoder().decode(WebSocketClient.MessageActionables.self, from: messageWrapper.payload)
                        self.messageReceived?(msg.actionableIds)
//                        fatalError()
                        break
                    case .schema:
                        guard let schemaMessage = try? JSONDecoder().decode(WebSocketClient.MessageSchema.self, from: messageWrapper.payload) else {
                            return
                        }
                        
                        NSLog("[INERTIA_LOG]:  Received message (data): \(schemaMessage)")
                        self.messageReceivedSchema?(schemaMessage.schemaWrappers)
                    case .translationEnded:
                        fatalError()
//                        guard let schemaMessage = try? JSONDecoder().decode(WebSocketClient.MessageSchema.self, from: messageWrapper.payload) else {
//                            return
//                        }
                        
//                        NSLog("[INERTIA_LOG]:  Received message (data): \(schemaMessage)")
//                        self.messageReceivedSchema?(schemaMessage.schemaWrappers)
                    }
                case .string(let text):
                    fatalError()
                    print("Received message (text): \(text)")
                @unknown default:
                    print("Received an unknown message type.")
                }
            }
            
            self.receiveMessage(task: task)
        }
    }
}

func getHostIPAddressFromResolvConf() -> String? {
    guard let resolvContents = try? String(contentsOfFile: "/etc/resolv.conf") else {
        print("Failed to read /etc/resolv.conf")
        return nil
    }
    
    let lines = resolvContents.components(separatedBy: "\n")
    var potentialIPs = [String]()
    
    for line in lines {
        if line.starts(with: "nameserver") {
            let components = line.components(separatedBy: " ")
            if components.count > 1 {
                let ipAddress = components[1].trimmingCharacters(in: .whitespaces)
                
                // Simple IP address validation
                if isValidIPAddress(ipAddress) {
                    potentialIPs.append(ipAddress)
                }
            }
        }
    }
    
    if let firstValidIP = potentialIPs.first {
        print("firstValidIP: \(firstValidIP)")
        return firstValidIP
    } else {
        print("No valid IP addresses found in /etc/resolv.conf")
        return nil
    }
}

// Helper function to validate an IPv4 address format
func isValidIPAddress(_ ipAddress: String) -> Bool {
    let parts = ipAddress.split(separator: ".").map { Int($0) }
    guard parts.count == 4, parts.allSatisfy({ $0 != nil && $0! >= 0 && $0! <= 255 }) else {
        return false
    }
    return true
}

struct ParentPath: PreferenceKey {
    static var defaultValue: [String]? = nil
    
    static func reduce(value: inout [String]?, nextValue: () -> [String]?) {
        value? += nextValue() ?? []
    }
}

let manager = WebSocketClient.shared

struct InertiaCanvasSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    var inertiaContainerSize: CGSize {
        get { self[InertiaCanvasSizeKey.self] }
        set { self[InertiaCanvasSizeKey.self] = newValue }
    }
}

struct InertiaActionable<Content: View>: View {
    @State private var animation: InertiaAnimationSchema? = nil
    @State private var contentSize: CGSize = .zero
    @State private var vm = InertiaViewModel()
    @State private var hierarchyId: String? = nil
    
    private weak var indexManager = SharedIndexManager.shared
    let hierarchyIdPrefix: String
    let content: Content
    
    init(hierarchyIdPrefix: String, content: Content) {
        self.hierarchyIdPrefix = hierarchyIdPrefix
        self.content = content
    }
    
    @Environment(\.inertiaDataModel) var inertiaDataModel
    @Environment(\.inertiaParentID) var inertiaParentID
    @Environment(\.inertiaContainerId) var inertiaContainerId
    @Environment(\.isInertiaContainer) var isInertiaContainer
    @Environment(\.inertiaContainerSize) var inertiaContainerSize: CGSize
    
    var wrappedContent: some View {
        ZStack(alignment: .center) {
            content
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        // Background view disabled for new schema structure
        // The new schema only contains animation data, no shape objects
        NSLog("[INERTIA_LOG]:  backgroundView - new schema doesn't support shapes")
        return AnyView(EmptyView())
    }
    
    @MainActor
    func updateHierarchyId() {
        if let indexValue = indexManager?.indexMap[hierarchyIdPrefix] {
            hierarchyId = "\(hierarchyIdPrefix)--\(indexValue)"
            indexManager?.indexMap[hierarchyIdPrefix] = indexValue + 1
        } else {
            hierarchyId = "\(hierarchyIdPrefix)--\(Int.zero)"
            indexManager?.indexMap[hierarchyIdPrefix] = 1
        }
    }
    
    var body: some View {
        //        GeometryReader { rootProxy in
        Group {
            if let animation = animation ?? getAnimation {
                wrappedContent
                    .keyframeAnimator(initialValue: animation.initialValues, content: { contentView, values in
                        contentView
                            .scaleEffect(values.scale)
//                            .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
                            .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                            .offset(x: values.translate.width * inertiaContainerSize.width, y: values.translate.height * inertiaContainerSize.height)
                            .opacity(values.opacity)
                    }, keyframes: { _ in
                        KeyframeTrack {
                            for keyframe in animation.keyframes {
                                CubicKeyframe(keyframe.values, duration: keyframe.duration)
                            }
                        }
                    })
            } else {
                wrappedContent
            }
        }
    //            .frame(minWidth: contentSize.width, minHeight: contentSize.height)

        .background(
            GeometryReader { proxy in
                backgroundView
                    .frame(width: inertiaContainerSize.width, height: inertiaContainerSize.height)
                    .offset(x: -proxy.frame(in: .named(inertiaContainerId)).origin.x, y: -proxy.frame(in: .named(inertiaContainerId)).origin.y)
            }
        )
        .environment(\.inertiaParentID, hierarchyId)
        .environment(\.isInertiaContainer, false)
        .buttonStyle(.plain)
        .task {
            updateHierarchyId()
        }
        .onChange(of: hierarchyId) { _, hierarchyId in
            guard let hierarchyId else {
                return
            }
            
            inertiaDataModel?.actionableIdToAnimationIdMap[hierarchyId] = hierarchyIdPrefix
        }
        .onDisappear {
            // Cleanup disabled for new schema - no shape objects with zIndex
        }
    }
    
    var getAnimation: InertiaAnimationSchema? {
        guard let inertiaDataModel else {
            NSLog("[INERTIA_LOG]:  inertiaDataModel is nil")
            return nil
        }
        
        guard let hierarchyId else {
            return nil
        }

        guard let animationId = inertiaDataModel.actionableIdToAnimationIdMap[hierarchyId] else {
            NSLog("[INERTIA_LOG]:  animationId is nil")
            return nil
        }
        NSLog("[INERTIA_LOG]:  hierarchyId: \(hierarchyId) animationId: \(animationId)")
        let animation = inertiaDataModel.inertiaSchema
    
        return animation
        
    }
}

final class SharedIndexManager {
    static let shared = SharedIndexManager()
        
    private init() {

    }
    
    var indexMap: [String: Int] = [:]
    var objectIndexMap: [String: Int] = [:]
    var objectIdSet: Set<String> = []
}

struct InertiaEditable<Content: View>: View {
    @State private var dragOffset: CGSize = .zero
    @State private var animation: InertiaAnimationSchema? = nil
    @State private var contentSize: CGSize = .zero
    @State private var vm = InertiaViewModel()
    @State private var hierarchyId: String? = nil
    
    private weak var indexManager = SharedIndexManager.shared
    let hierarchyIdPrefix: String
    let content: Content
    
    init(hierarchyIdPrefix: String, content: Content) {
        self.hierarchyIdPrefix = hierarchyIdPrefix
        self.content = content
    }
    
    @Environment(\.inertiaDataModel) var inertiaDataModel
    @Environment(\.inertiaParentID) var inertiaParentID
    @Environment(\.inertiaContainerId) var inertiaContainerId
    @Environment(\.isInertiaContainer) var isInertiaContainer
    @Environment(\.inertiaContainerSize) var inertiaContainerSize: CGSize
    
    var showSelectedBorder: Bool {
        guard let inertiaDataModel else {
            return false
        }
        
        guard let hierarchyId else {
            return false
        }
        
        return inertiaDataModel.actionableIds.contains(hierarchyId)
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if inertiaDataModel?.isActionable == true {
                    dragOffset = value.translation
                }
                
            }
            .onEnded { value in
                if inertiaDataModel?.isActionable == true {
                    dragOffset = value.translation
                    if let actionableIds = inertiaDataModel?.actionableIds {
                        manager.sendMessage(
                            WebSocketClient.MessageTranslation(
                                translationX: (dragOffset.width) / (inertiaContainerSize.width / 2),
                                translationY: (dragOffset.height) / (inertiaContainerSize.height / 2),
                                actionableIds: actionableIds
                            )
                        )
                    }
                    
                }
            }
    }
    
    var wrappedContent: some View {
        ZStack(alignment: .center) {
            content
                .disabled(inertiaDataModel?.isActionable ?? false)
//                .modifier(BindableSize(size: $contentSize))
        }
        
        .onTapGesture {
            print("tapped \(content)")
            guard let inertiaDataModel else {
                return
            }
            
            guard inertiaDataModel.isActionable else {
                return
            }
            
            guard let hierarchyId else {
                return
            }

            if inertiaDataModel.actionableIds.contains(hierarchyId) {
                inertiaDataModel.actionableIds.remove(hierarchyId)
            } else {
                inertiaDataModel.actionableIds.insert(hierarchyId)
            }
            
            if let ip = getHostIPAddressFromResolvConf() {
                let uri = URL(string: "ws://\(ip):8060")!
//                    let data: [String: Tree?] = ["tree": inertiaDataModel?.tree]
                
                NSLog("[INERTIA_LOG]: Tapped: Starting to send data...")
                
                if !manager.isConnected {
                    manager.connect(uri: uri)
                }
                
                let tree = inertiaDataModel.tree
                let actionableIds = inertiaDataModel.actionableIds
                let message = WebSocketClient.MessageActionables(tree: tree, actionableIds: actionableIds)
                manager.sendMessage(message)
            }
        }
        .overlay {
            if showSelectedBorder && inertiaDataModel?.isActionable ?? false {
                Rectangle()
                    .stroke(Color.green)
            }
        }
        .offset(dragOffset)
        .gesture(dragGesture)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        // Background view disabled for new schema structure
        // The new schema only contains animation data, no shape objects
        NSLog("[INERTIA_LOG]:  backgroundView - new schema doesn't support shapes")
        return AnyView(EmptyView())
    }
    
    @MainActor
    func updateHierarchyId() {
        if let indexValue = indexManager?.indexMap[hierarchyIdPrefix] {
            hierarchyId = "\(hierarchyIdPrefix)--\(indexValue)"
            indexManager?.indexMap[hierarchyIdPrefix] = indexValue + 1
        } else {
            hierarchyId = "\(hierarchyIdPrefix)--\(Int.zero)"
            indexManager?.indexMap[hierarchyIdPrefix] = 1
        }
    }
    
    var body: some View {
        //        GeometryReader { rootProxy in
        Group {
            if let animation = animation ?? getAnimation {
                wrappedContent
                    .keyframeAnimator(initialValue: animation.initialValues, content: { contentView, values in
                        contentView
                            .scaleEffect(values.scale)
                            .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
                            .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                            .offset(x: values.translate.width * inertiaContainerSize.width / 2, y: values.translate.height * inertiaContainerSize.height / 2)
                            .opacity(values.opacity)
                    }, keyframes: { _ in
                        KeyframeTrack {
                            for keyframe in animation.keyframes {
                                CubicKeyframe(keyframe.values, duration: keyframe.duration)
                            }
                        }
                    })
                    .onAppear {
                        self.dragOffset = animation.initialValues.translate
                    }
            } else {
                wrappedContent                    
            }
        }
    //            .frame(minWidth: contentSize.width, minHeight: contentSize.height)

        .background(
            GeometryReader { proxy in
                backgroundView
                    .frame(width: inertiaContainerSize.width, height: inertiaContainerSize.height)
                    .offset(x: -proxy.frame(in: .named(inertiaContainerId)).origin.x, y: -proxy.frame(in: .named(inertiaContainerId)).origin.y)
            }
        )
        .environment(\.inertiaParentID, hierarchyId)
        .environment(\.isInertiaContainer, false)
        .buttonStyle(.plain)
        .task {
            updateHierarchyId()
        }
        .onAppear {
            if !manager.isConnected {
                if let ip = getHostIPAddressFromResolvConf() {
                    let uri = URL(string: "ws://\(ip):8060")!
                    NSLog("[INERTIA_LOG]: Starting to send data 2 (setup)...")
                    manager.connect(uri: uri)

                    manager.messageReceived = handleMessage
                    manager.messageReceivedSchema = handleMessageSchema
                    manager.messageReceivedIsActionable = handleMessageActionable
                }
            }
        }
        .onChange(of: manager.isConnected, { oldValue, newValue in
            if !newValue {
                if let ip = getHostIPAddressFromResolvConf() {
                    let uri = URL(string: "ws://\(ip):8060")!
                    NSLog("[INERTIA_LOG]: Starting to send data 2 (setup)...")
                    manager.connect(uri: uri)

                    manager.messageReceived = handleMessage
                    manager.messageReceivedSchema = handleMessageSchema
                    manager.messageReceivedIsActionable = handleMessageActionable
                }
            }
        })
        .onChange(of: inertiaDataModel?.tree, { oldValue, newValue in
            if let tree = newValue {
                for node in tree.nodeMap.values {
                    node.tree = tree
                    node.link()
                }
            }
        })
        .onChange(of: hierarchyId) { oldValue, hierarchyId in
            print("onAppear: \(hierarchyId)")
            if oldValue != nil {
                return
            }
            
            guard let hierarchyId else {
                return
            }
            NSLog("[INERTIA_LOG]:  adding relationship: hierarchyId: \(hierarchyId) inertiaParentID: \(inertiaParentID), isInertiaContainer: \(isInertiaContainer)")
            inertiaDataModel?.tree.addRelationship(id: hierarchyId, parentId: inertiaParentID, parentIsContainer: isInertiaContainer)
            if let tree = inertiaDataModel?.tree {
                for node in tree.nodeMap.values {
                    node.tree = tree
                    node.link()
                }
            }
            
            if let ip = getHostIPAddressFromResolvConf() {
                let uri = URL(string: "ws://\(ip):8060")!                
                NSLog("[INERTIA_LOG]: Starting to send data 2...")
                
                if !manager.isConnected {
                    manager.connect(uri: uri)
                }
                
                if let tree = inertiaDataModel?.tree, let actionableIds = inertiaDataModel?.actionableIds {
                    let message = WebSocketClient.MessageActionables(tree: tree, actionableIds: actionableIds)
                    manager.sendMessage(message)
                }
            }
        }
        .onDisappear {
            // Cleanup disabled for new schema - no shape objects with zIndex
        }
    }
    
    var getAnimation: InertiaAnimationSchema? {
        guard let inertiaDataModel else {
            NSLog("[INERTIA_LOG]:  inertiaDataModel is nil")
            return nil
        }

        guard let hierarchyId else {
            return nil
        }

        guard let animationId = inertiaDataModel.actionableIdToAnimationIdMap[hierarchyId] else {
            NSLog("[INERTIA_LOG]:  animationId is nil")
            return nil
        }
        NSLog("[INERTIA_LOG]:  hierarchyId: \(hierarchyId) animationId: \(animationId)")
        // In the new schema, inertiaSchema is directly the animation
        let animation = inertiaDataModel.inertiaSchema

        if animation.id == animationId {
            return animation
        } else {
            NSLog("[INERTIA_LOG]:  animation id mismatch - expected: \(animationId), got: \(animation.id)")
            return nil
        }
    }
    
    func handleMessage(selectedIds: Set<String>) {
        NSLog("[INERTIA_LOG]: handleMessage(selectedIds) \(selectedIds)")
        inertiaDataModel?.actionableIds = selectedIds
    }
    
    func handleMessageSchema(schemaWrappers: [InertiaSchemaWrapper]) {
        for schemaWrapper in schemaWrappers {
            if schemaWrapper.container.containerId == inertiaDataModel?.containerId {
                
                inertiaDataModel?.actionableIdToAnimationIdMap[schemaWrapper.actionableId] = schemaWrapper.animationId
                inertiaDataModel?.inertiaSchema = schemaWrapper.schema
                NSLog("[INERTIA_LOG]:  animationId: \(schemaWrapper.animationId) actionableId: \(schemaWrapper.actionableId)")
            }
        }
    }
    
    func handleMessageActionable(isActionable: Bool) {
        inertiaDataModel?.isActionable = isActionable
    }
}

public struct InertiaAnimationState: Identifiable, Equatable, Codable {
    public let id: InertiaID
    public let trigger: Bool?
    public let isCancelled: Bool
    
    public init(id: InertiaID, trigger: Bool? = nil, isCancelled: Bool = false) {
        self.id = id
        self.trigger = trigger
        self.isCancelled = isCancelled
    }
}

public struct AnimationContainer: Codable, Hashable {
    public let actionableId: String
    public let containerId: String
    
    public init(actionableId: String, containerId: String) {
        self.actionableId = actionableId
        self.containerId = containerId
    }
}

public struct InertiaAnimation: Codable, Hashable {
    public let actionableId: String
    public let containerId: String
    public let containerActionableId: String
    public let animationId: String
    
    public init(actionableId: String, containerId: String, containerActionableId: String, animationId: String) {
        self.actionableId = actionableId
        self.containerId = containerId
        self.containerActionableId = containerActionableId
        self.animationId = animationId
    }
}

public struct InertiaSchemaWrapper: Codable {
    public let schema: InertiaAnimationSchema
    public let actionableId: String
    public let container: AnimationContainer
    public let animationId: String
    
    public init(schema: InertiaAnimationSchema, actionableId: String, container: AnimationContainer, animationId: String) {
        self.schema = schema
        self.actionableId = actionableId
        self.container = container
        self.animationId = animationId
    }
}

struct InertiaDecider<Content: View>: View {
    @Environment(\.inertiaEditor) private var isEditor
    
    let hierarchyId: String
    let content: Content
    
    var body: some View {
        if isEditor {
            InertiaEditable(hierarchyIdPrefix: hierarchyId, content: content)
        } else {
            InertiaActionable(hierarchyIdPrefix: hierarchyId, content: content)
        }
    }
}

extension View {
    public func inertia(_ hierarchyId: String) -> some View {
        InertiaDecider(hierarchyId: hierarchyId, content: self)
    }
    
    public func inertiaContainer(dev: Bool, id: InertiaID, hierarchyId: String) -> some View {
        InertiaContainer(dev: dev, id: id, hierarchyId: hierarchyId) {
            self
        }
    }
}

public struct InertiaAnimationValues: VectorArithmetic, Animatable, Codable, Equatable, CustomStringConvertible {
    public var description: String {
"""
{"scale": \(scale), "translate": \(translate), "rotate": \(rotate), "rotateCenter": \(rotateCenter), "opacity": \(opacity)}
"""
    }
    
    public static var zero = InertiaAnimationValues(scale: .zero, translate: .zero, rotate: .zero, rotateCenter: .zero, opacity: .zero)
    
    public init(scale: CGFloat, translate: CGSize, rotate: CGFloat, rotateCenter: CGFloat, opacity: CGFloat) {
        self.scale = scale
        self.translate = translate
        self.rotate = rotate
        self.rotateCenter = rotateCenter
        self.opacity = opacity
    }
    
    public var scale: CGFloat
    public var translate: CGSize
    public var rotate: CGFloat
    public var rotateCenter: CGFloat
    public var opacity: CGFloat

    public var magnitudeSquared: Double {
        let translateMagnitude = Double(translate.width * translate.width + translate.height * translate.height)
        return Double(scale * scale) + translateMagnitude + Double(rotate * rotate) + Double(rotateCenter * rotateCenter) + Double(opacity * opacity)
    }

    public mutating func scale(by rhs: Double) {
        scale *= CGFloat(rhs)
        translate.width *= CGFloat(rhs)
        translate.height *= CGFloat(rhs)
        rotate *= CGFloat(rhs)
        rotateCenter *= CGFloat(rhs)
        opacity *= CGFloat(rhs)
    }

    public static func += (lhs: inout InertiaAnimationValues, rhs: InertiaAnimationValues) {
        lhs.scale += rhs.scale
        lhs.translate.width += rhs.translate.width
        lhs.translate.height += rhs.translate.height
        lhs.rotate += rhs.rotate
        lhs.rotateCenter += rhs.rotateCenter
        lhs.opacity += rhs.opacity
    }

    public static func -= (lhs: inout InertiaAnimationValues, rhs: InertiaAnimationValues) {
        lhs.scale -= rhs.scale
        lhs.translate.width -= rhs.translate.width
        lhs.translate.height -= rhs.translate.height
        lhs.rotate -= rhs.rotate
        lhs.rotateCenter -= rhs.rotateCenter
        lhs.opacity -= rhs.opacity
    }

    public static func * (lhs: InertiaAnimationValues, rhs: Double) -> InertiaAnimationValues {
        var result = lhs
        result.scale(by: rhs)
        return result
    }

    public static func + (lhs: InertiaAnimationValues, rhs: InertiaAnimationValues) -> InertiaAnimationValues {
        var result = lhs
        result += rhs
        return result
    }

    public static func - (lhs: InertiaAnimationValues, rhs: InertiaAnimationValues) -> InertiaAnimationValues {
        var result = lhs
        result -= rhs
        return result
    }
}

public struct InertiaAnimationKeyframe: Identifiable, Codable, Equatable, CustomStringConvertible {
    public var description: String {
"""
{"id": \(id), "values": \(values), "duration": \(duration)}
"""
    }
    
    public let id: InertiaID
    public let values: InertiaAnimationValues
    public let duration: CGFloat
    
    public init(id: InertiaID, values: InertiaAnimationValues, duration: CGFloat) {
        self.id = id
        self.values = values
        self.duration = duration
    }
    
    public static func == (lhs: InertiaAnimationKeyframe, rhs: InertiaAnimationKeyframe) -> Bool {
        lhs.id == rhs.id &&
        lhs.values == rhs.values &&
        lhs.duration == rhs.duration
    }
}

//public enum InertiaObjectType: String, Codable, Equatable, CustomStringConvertible {
//    public var description: String {
//        "\(self.rawValue)"
//    }
//    
//    case shape, animation
//}
//
//public struct InertiaShape: Codable, Identifiable, Equatable, CustomStringConvertible {
//    public var description: String {
//"""
//{"id": "\(id)", "containerId": "\(containerId.description)", "width": \(width.description), "height": \(height.description), "position": \(position.debugDescription), "color": \(color.description), "shape": \(shape.description), "objectType": \(objectType.description), "zIndex": \(zIndex), "animation": \(animation.description)}
//"""
//    }
//    
//    public let id: InertiaID
//    public let containerId: InertiaID
//    public let width: CGFloat
//    public let height: CGFloat
//    public let position: CGPoint
//    public let color: [CGFloat]
//    public let shape: String
//    public let objectType: InertiaObjectType
//    public let zIndex: Int
//    public let animation: InertiaAnimationSchema
//    
//    public init(id: InertiaID, containerId: InertiaID, width: CGFloat, height: CGFloat, position: CGPoint, color: [CGFloat], shape: String, objectType: InertiaObjectType, zIndex: Int, animation: InertiaAnimationSchema) {
//        self.id = id
//        self.containerId = containerId
//        self.width = width
//        self.height = height
//        self.position = position
//        self.color = color
//        self.shape = shape
//        self.objectType = objectType
//        self.zIndex = zIndex
//        self.animation = animation
//    }
//}

//public struct InertiaSchema: Codable, Equatable, CustomStringConvertible {
//    public var description: String {
//"""
//{"id": "\(id)", objects: \(objects)}
//"""
//    }
//    
//    public let id: InertiaID
//    public let objects: [InertiaShape]
//    
//    public init(id: InertiaID, objects: [InertiaShape]) {
//        self.id = id
//        self.objects = objects
//    }
//}

public enum InertiaAnimationInvokeType: String, Codable, CustomStringConvertible {
    public var description: String {
        "\(self.rawValue)"
    }
    
    case trigger, auto
}

public struct InertiaAnimationSchema: Codable, Identifiable, Equatable, CustomStringConvertible {
    public var description: String {
"""
{"id": \(id), "initialValues": \(initialValues), "invokeType": \(invokeType), "keyframes": \(keyframes)}
"""
    }

    public let id: InertiaID
    public let initialValues: InertiaAnimationValues
    public let invokeType: InertiaAnimationInvokeType
    public let keyframes: [InertiaAnimationKeyframe]

    public init(id: InertiaID, initialValues: InertiaAnimationValues, invokeType: InertiaAnimationInvokeType, keyframes: [InertiaAnimationKeyframe]) {
        self.id = id
        self.initialValues = initialValues
        self.invokeType = invokeType
        self.keyframes = keyframes
    }
}

// Helper to create an empty schema for dev mode
func InertiaSchemaAnimation() -> InertiaAnimationSchema {
    InertiaAnimationSchema(
        id: "",
        initialValues: .zero,
        invokeType: .auto,
        keyframes: []
    )
}

func decodeInertiaSchema(json: Data) -> InertiaAnimationSchema? {
    do {
        let schema = try JSONDecoder().decode(InertiaAnimationSchema.self, from: json)
        return schema
    } catch {
        print("Failed to decode JSON: \(error.localizedDescription)")
        return nil
    }
}
