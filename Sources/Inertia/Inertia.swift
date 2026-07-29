//
// Inertia SwiftUI animation library
// Created by Hayden Pennington
//
// Copyright (c) 2024 Vector Studio. All rights reserved.
//

import SwiftUI

public typealias InertiaID = String

public enum AnimationSignal: Codable {
    case pause
    /// The editor's timeline was resized; play one loop over this many seconds.
    case setLoopDuration(CGFloat)
}

public enum InertiaPlayback {
    /// How long one loop lasts until the editor says otherwise.
    ///
    /// A loop lasts as long as the timeline the animation was authored on, not
    /// as long as its last keyframe: a track that stops moving after half a
    /// second holds there until the loop comes round again. Every track is
    /// padded to the loop, so actionables of different lengths restart together
    /// and the editor's playhead — which draws exactly this span — stays with
    /// them.
    public static let defaultLoopDuration: CGFloat = 3.0

    /// The range the timeline can be resized to. A loop shorter than this can't
    /// hold a keyframe apart from its neighbours; longer is past the point of
    /// being able to see the whole thing at once.
    public static let loopDurationRange: ClosedRange<CGFloat> = 0.1...60.0

    /// Brings a loop length the user typed, or a peer sent, into range.
    public static func clampLoopDuration(_ seconds: CGFloat) -> CGFloat {
        guard seconds.isFinite else { return defaultLoopDuration }
        return seconds.clamped(to: loopDurationRange)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

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
    public var inertiaDataModel: InertiaDataModel? {
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

public struct ActionableIdPair: Codable, Hashable {
    public let hierarchyIdPrefix: String
    public let hierarchyId: String

    public init(hierarchyIdPrefix: String, hierarchyId: String) {
        self.hierarchyIdPrefix = hierarchyIdPrefix
        self.hierarchyId = hierarchyId
    }
}

private extension Duration {
    /// Seconds as a fraction, for arithmetic against keyframe durations.
    var inSeconds: CGFloat {
        CGFloat(components.seconds) + CGFloat(components.attoseconds) / 1e18
    }
}

@MainActor
@Observable
public final class InertiaDataModel{
    let containerId: InertiaID
    var inertiaSchemas: [InertiaID: InertiaAnimationSchema]
    var tree: Tree
    var actionableIdPairs: Set<ActionableIdPair>
    var states: [InertiaID: InertiaAnimationState]
    var actionableIdToAnimationIdMap: [String: String] = [:]
    var registeredHierarchyIdPrefixes: Set<String> = []
    var showGrid: Bool = false
    var selectedNodePosition: CGSize = .zero
    var selectedNodeSize: CGSize = .zero
    var isActionable: Bool = false
    var isRunning:Bool = false

    /// How far into the run currently on screen we are, in seconds.
    ///
    /// SwiftUI's `keyframeAnimator` keeps its own clock and does not publish it,
    /// so the runtime runs a wall clock alongside it — started and stopped by the
    /// same things that start and stop the animation — and reports it to the
    /// editor, whose playhead has no other way to know where the animation is.
    public private(set) var playheadTime: CGFloat = .zero

    /// Whether the keyframe animators repeat their tracks once they reach the
    /// end. Passed straight to `keyframeAnimator(initialValue:repeating:…)`, so
    /// the playhead's clock and the animation on screen loop or stop together.
    public var isRepeating: Bool = true

    /// How long one loop lasts, as set on the editor's timeline. Applies from
    /// the next tick of the clock, so resizing the timeline mid-run stretches
    /// the loop rather than waiting for it to be restarted.
    public var loopDuration: CGFloat = InertiaPlayback.defaultLoopDuration

    /// One turn of the timeline: where a run ends, and where a repeating one
    /// wraps back to the start.
    ///
    /// The full loop, not the last keyframe — tracks are padded out to it — so
    /// the playhead crosses the whole timeline however early the animation
    /// settles. Anything recorded past the end of the loop stretches it, which
    /// keeps every track the same length as every other.
    var playbackDuration: CGFloat {
        let longestTrack = inertiaSchemas.values
            .map { schema in schema.playableKeyframes.reduce(CGFloat.zero) { $0 + $1.duration } }
            .max() ?? .zero

        return max(loopDuration, longestTrack)
    }

    private var clock: Task<Void, Never>? = nil

    /// Roughly one message per display frame. Fine enough for the editor to
    /// interpolate a smooth playhead without flooding the socket.
    private static let clockInterval: Duration = .milliseconds(16)

    public func trigger(_ id: InertiaID) {
        isRunning = true
        states[id]?.trigger = true
        startClock()
    }

    /// Stops the run and reports where it stopped, so a paused playhead sits
    /// exactly where the animation froze.
    func pausePlayback() {
        isRunning = false
        clock?.cancel()
        clock = nil
        report(isRunning: false)
    }

    /// Times the run that just started.
    ///
    /// Actionables trigger one at a time, so a trigger arriving while the clock
    /// is already running joins the run in progress rather than restarting it —
    /// otherwise the playhead would jump back to zero on every actionable after
    /// the first.
    ///
    /// A repeating run has no end: the clock wraps at `playbackDuration` the way
    /// the animators restart their tracks, and only a pause stops it.
    private func startClock() {
        guard clock == nil else { return }

        // Nothing loaded yet: there is no animation for the playhead to follow.
        guard !inertiaSchemas.isEmpty else { return }

        playheadTime = .zero
        report(isRunning: true)

        let start = ContinuousClock.now
        clock = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.clockInterval)
                guard !Task.isCancelled, let self, self.isRunning else { return }

                // Read each tick: the timeline can be resized mid-run.
                let duration = self.playbackDuration
                let elapsed = (ContinuousClock.now - start).inSeconds

                if self.isRepeating {
                    self.playheadTime = elapsed.truncatingRemainder(dividingBy: duration)
                    self.report(isRunning: true)
                    continue
                }

                if elapsed >= duration {
                    self.playheadTime = duration
                    self.clock = nil
                    self.report(isRunning: false)
                    return
                }

                self.playheadTime = elapsed
                self.report(isRunning: true)
            }
        }
    }

    private func report(isRunning: Bool) {
        manager.sendMessage(
            InertiaMessage.MessagePlaybackProgress(
                time: playheadTime,
                duration: playbackDuration,
                isRunning: isRunning
            )
        )
    }

    public func registerHierarchyIdPrefix(_ prefix: String) {
        registeredHierarchyIdPrefixes.insert(prefix)
        // Initialize state for this prefix if it doesn't exist
        if states[prefix] == nil {
            states[prefix] = InertiaAnimationState(id: prefix, trigger: false, isCancelled: false)
        }
    }

    public init(containerId: InertiaID, inertiaSchemas: [InertiaID: InertiaAnimationSchema], tree: Tree, actionableIdPairs: Set<ActionableIdPair>) {
        self.containerId = containerId
        self.inertiaSchemas = inertiaSchemas
        self.tree = tree
        self.actionableIdPairs = actionableIdPairs
        // Initialize from schema keys
        self.registeredHierarchyIdPrefixes = Set(inertiaSchemas.keys)
        // Initialize states for all schema keys
        self.states = inertiaSchemas.keys.reduce(into: [:]) { result, key in
            result[key] = InertiaAnimationState(id: key, trigger: false, isCancelled: false)
        }
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
                wrappedValue: InertiaDataModel(containerId: id, inertiaSchemas: [:], tree: Tree(id: id), actionableIdPairs: Set())
            )
        } else {
            if let url = bundle.url(forResource: id, withExtension: "json") {
                let schemaText = try! String(contentsOf: url, encoding: .utf8)
                if let data = schemaText.data(using: .utf8),
                   let schemas = decodeInertiaSchemas(json: data) {
                    NSLog("[INERTIA_LOG]: InertiaDataModel instantiated for container: \(id)")
                    let schemaMap = schemas.reduce(into: [String: InertiaAnimationSchema]()) { $0[$1.id] = $1 }
                    self._inertiaDataModel = State(
                        wrappedValue: InertiaDataModel(containerId: id, inertiaSchemas: schemaMap, tree: Tree(id: id), actionableIdPairs: Set())
                    )
                } else {
                    NSLog("[INERTIA_LOG]:  Failed to decode the inertia schemas")
                    fatalError()
                }
            } else {
                NSLog("[INERTIA_LOG]:  Failed to parse the inertia file")
                fatalError()
            }
        }
    }
    
    private var dragGrid: some View {
        ZStack {
            Rectangle()
                .fill(.red)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            
            Rectangle()
                .fill(.red)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
    }
    
    /// Dashed guides that track the selected node's edges and center within the container.
    /// The node's untransformed origin is the container center, so its current center is
    /// the container center offset by `selectedNodePosition`.
    @ViewBuilder
    private func dragAlignmentGuides(in size: CGSize) -> some View {
        let position = inertiaDataModel.selectedNodePosition
        let selectedSize = inertiaDataModel.selectedNodeSize
        let center = CGPoint(
            x: size.width / 2 + position.width,
            y: size.height / 2 + position.height
        )
        // SwiftUI traps on non-finite geometry, and any of these can be NaN before
        // the first layout pass or while a drag is being set up.
        let isValid = size.width.isFinite && size.height.isFinite
            && selectedSize.width.isFinite && selectedSize.height.isFinite
            && center.x.isFinite && center.y.isFinite
            && selectedSize.width > 0 && selectedSize.height > 0

        if isValid {
            Canvas { context, canvasSize in
                let xs = [center.x - selectedSize.width / 2, center.x, center.x + selectedSize.width / 2]
                let ys = [center.y - selectedSize.height / 2, center.y, center.y + selectedSize.height / 2]

                for (index, x) in xs.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(path, with: .color(.cyan.opacity(index == 1 ? 1.0 : 0.5)), style: guideStyle(isCenter: index == 1))
                }

                for (index, y) in ys.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(path, with: .color(.cyan.opacity(index == 1 ? 1.0 : 0.5)), style: guideStyle(isCenter: index == 1))
                }

                let bounds = CGRect(
                    x: center.x - selectedSize.width / 2,
                    y: center.y - selectedSize.height / 2,
                    width: selectedSize.width,
                    height: selectedSize.height
                )
                context.stroke(Path(bounds), with: .color(.cyan), style: guideStyle(isCenter: false))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    private func guideStyle(isCenter: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: 1, dash: isCenter ? [] : [4, 4])
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
            .background {
                if inertiaDataModel.showGrid {
                    ZStack {
                        dragGrid
                        dragAlignmentGuides(in: proxy.size)
                    }
                }
            }
        }
    }
}

struct ParentPath: PreferenceKey {
    static var defaultValue: [String]? = nil
    
    static func reduce(value: inout [String]?, nextValue: () -> [String]?) {
        value? += nextValue() ?? []
    }
}

let manager = InertiaWebSocketServer.shared

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
    
    /// The track the animator plays: held out to the full loop when repeating,
    /// so the animation and the editor's playhead share one period.
    func track(for animation: InertiaAnimationSchema) -> [InertiaAnimationKeyframe] {
        guard inertiaDataModel?.isRepeating ?? true else { return animation.playableKeyframes }

        return animation.keyframes(filling: inertiaDataModel?.playbackDuration ?? InertiaPlayback.defaultLoopDuration)
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
        // Register this prefix with the data model
        inertiaDataModel?.registerHierarchyIdPrefix(hierarchyIdPrefix)
    }
    
    var body: some View {
        //        GeometryReader { rootProxy in
        Group {
            if let animation = animation ?? getAnimation, inertiaDataModel?.isRunning == true {
                wrappedContent
                    .keyframeAnimator(
                        initialValue: animation.initialValues.sanitized,
                        repeating: inertiaDataModel?.isRepeating ?? true,
                        content: { contentView, rawValues in
                        let values = rawValues.sanitized
                        contentView
                            .scaleEffect(values.scale)
//                            .rotationEffect(Angle (degrees: values.rotate), anchor: .topLeading)
                            .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                            .offset(x: values.translate.width * inertiaContainerSize.width, y: values.translate.height * inertiaContainerSize.height)
                            .opacity(values.opacity)
                    }, keyframes: { _ in
                        KeyframeTrack {
                            for keyframe in track(for: animation) {
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
        .onAppear {
            manager.messageReceivedSignal = handleMessageSignal

        }
        .task {
            updateHierarchyId()
        }
        .onDisappear {
            // Cleanup disabled for new schema - no shape objects with zIndex
        }
        
        
    }
    
    func handleMessageSignal(_ signal: AnimationSignal) {
        switch signal {
        case .pause:
            inertiaDataModel?.pausePlayback()
        case .setLoopDuration(let duration):
            inertiaDataModel?.loopDuration = InertiaPlayback.clampLoopDuration(duration)
        }
    }
    
    var getAnimation: InertiaAnimationSchema? {
        guard let inertiaDataModel else {
            NSLog("[INERTIA_LOG]:  inertiaDataModel is nil")
            return nil
        }

        guard let hierarchyId else {
            NSLog("[INERTIA_LOG]:  hierarchyId is nil")
            return nil
        }
        
        guard inertiaDataModel.isRunning == true else {
            return nil
        }
        
        guard inertiaDataModel.states[hierarchyIdPrefix]?.trigger == true else {
            return nil
        }

        NSLog("[INERTIA_LOG]: [InertiaActionable.getAnimation] hierarchyId: \(hierarchyId), hierarchyIdPrefix: \(hierarchyIdPrefix)")
        NSLog("[INERTIA_LOG]: [InertiaActionable.getAnimation] actionableIdToAnimationIdMap: \(inertiaDataModel.actionableIdToAnimationIdMap)")
        NSLog("[INERTIA_LOG]: [InertiaActionable.getAnimation] available schema IDs: \(Array(inertiaDataModel.inertiaSchemas.keys))")

        // First try to get the animation ID from the map
        guard let animationId = inertiaDataModel.actionableIdToAnimationIdMap[hierarchyId] else {
            NSLog("[INERTIA_LOG]:  no mapping for hierarchyId: \(hierarchyId), trying hierarchyIdPrefix: \(hierarchyIdPrefix)")
            // If not in the map, try using hierarchyIdPrefix directly (fallback)
            guard let animation = inertiaDataModel.inertiaSchemas[hierarchyIdPrefix] else {
                NSLog("[INERTIA_LOG]:  animation not found for hierarchyId: \(hierarchyId) or hierarchyIdPrefix: \(hierarchyIdPrefix)")
                return nil
            }
            NSLog("[INERTIA_LOG]:  using hierarchyIdPrefix fallback: \(hierarchyIdPrefix)")
            return animation
        }

        // Look up the animation using the mapped animation ID
        guard let animation = inertiaDataModel.inertiaSchemas[animationId] else {
            NSLog("[INERTIA_LOG]:  animation not found for animationId: \(animationId)")
            return nil
        }
        NSLog("[INERTIA_LOG]:  found animation - hierarchyId: \(hierarchyId) -> animationId: \(animationId)")

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
    @State private var selectedSize: CGSize = .zero
    
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
        print("[INERTIA_LOG]: \(hierarchyId) \(hierarchyIdPrefix)")
        return inertiaDataModel!.actionableIdPairs.contains(where: { $0.hierarchyId == hierarchyId })
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if inertiaDataModel?.isActionable == true {
                    dragOffset = value.translation
                    inertiaDataModel?.showGrid = true
                    inertiaDataModel?.selectedNodePosition = dragOffset
                    inertiaDataModel?.selectedNodeSize = selectedSize
                    manager.sendMessage(
                        InertiaMessage.MessageSelectedNodeProperties(
                            positionX: dragOffset.width,
                            positionY: dragOffset.height,
                            sizeX: selectedSize.width,
                            sizeY: selectedSize.height
                        )
                    )
                }
            }
            .onEnded { value in
                if inertiaDataModel?.isActionable == true {
                    dragOffset = value.translation
                    inertiaDataModel?.showGrid = false
                    if let actionableIdPairs = inertiaDataModel?.actionableIdPairs {
                        manager.sendMessage(
                            InertiaMessage.MessageTranslation(
                                translationX: (dragOffset.width) / (inertiaContainerSize.width),
                                translationY: (dragOffset.height) / (inertiaContainerSize.height),
                                actionableIds: actionableIdPairs
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
            
            let pair = ActionableIdPair(hierarchyIdPrefix: hierarchyIdPrefix, hierarchyId: hierarchyId)
            if inertiaDataModel.actionableIdPairs.contains(pair) {
                inertiaDataModel.actionableIdPairs.remove(pair)
            } else {
                inertiaDataModel.actionableIdPairs.insert(pair)
            }
            
            NSLog("[INERTIA_LOG]: Tapped: Starting to send data...")

            let tree = inertiaDataModel.tree
            let actionableIds = inertiaDataModel.actionableIdPairs
            let message = InertiaMessage.MessageActionables(tree: tree, actionableIds: actionableIds)
            manager.sendMessage(message)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear {
                    selectedSize = proxy.size
                }
                .onChange(of: proxy.size) { oldValue, newValue in
                    selectedSize = newValue
                }
            }
        )
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
    
    /// The track the animator plays: held out to the full loop when repeating,
    /// so the animation and the editor's playhead share one period.
    func track(for animation: InertiaAnimationSchema) -> [InertiaAnimationKeyframe] {
        guard inertiaDataModel?.isRepeating ?? true else { return animation.playableKeyframes }

        return animation.keyframes(filling: inertiaDataModel?.playbackDuration ?? InertiaPlayback.defaultLoopDuration)
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
        // Register this prefix with the data model
        inertiaDataModel?.registerHierarchyIdPrefix(hierarchyIdPrefix)
    }
    
    var body: some View {
        //        GeometryReader { rootProxy in
        Group {
            if let animation = animation ?? getAnimation, inertiaDataModel?.isRunning == true {
                wrappedContent
                    .keyframeAnimator(
                        initialValue: animation.initialValues.sanitized,
                        repeating: inertiaDataModel?.isRepeating ?? true,
                        content: { contentView, rawValues in
                        let values = rawValues.sanitized
                        contentView
                            .scaleEffect(values.scale)
                            .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
                            .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                            .offset(x: values.translate.width * inertiaContainerSize.width, y: values.translate.height * inertiaContainerSize.height)
                            .opacity(values.opacity)
                    }, keyframes: { _ in
                        KeyframeTrack {
                            for keyframe in track(for: animation) {
                                CubicKeyframe(keyframe.values, duration: keyframe.duration)
                            }
                        }
                    })
                    .onAppear {
                        self.dragOffset = CGSize(
                            width: animation.initialValues.translate.width * inertiaContainerSize.width,
                            height: animation.initialValues.translate.height * inertiaContainerSize.height
                        )
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
        .onAppear {
            updateHierarchyId()

            NSLog("[INERTIA_LOG]: Starting websocket server (setup)...")
            manager.start()

            manager.messageReceived = handleMessage
            manager.messageReceivedSchema = handleMessageSchema
            manager.messageReceivedIsActionable = handleMessageActionable
            manager.messageReceivedSignal = handleMessageSignal(_:)
        }
        .onChange(of: manager.isConnected, { oldValue, newValue in
            // An editor just attached — push the current hierarchy so it can
            // render the tree without waiting for the next change.
            guard newValue, let inertiaDataModel else {
                return
            }

            NSLog("[INERTIA_LOG]: Editor attached, sending current tree...")
            let message = InertiaMessage.MessageActionables(
                tree: inertiaDataModel.tree,
                actionableIds: inertiaDataModel.actionableIdPairs
            )
            manager.sendMessage(message)
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
            print("[INERTIA_LOG]: onAppear: \(hierarchyId)")
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
            
            NSLog("[INERTIA_LOG]: Starting to send data 2...")
            manager.start()

            if let tree = inertiaDataModel?.tree {
                NSLog("[INERTIA_LOG]: tree \(tree)")
                if let actionableIdPairs = inertiaDataModel?.actionableIdPairs {
                    NSLog("[INERTIA_LOG]: tree \(actionableIdPairs)")
                    let message = InertiaMessage.MessageActionables(tree: tree, actionableIds: actionableIdPairs)
                    NSLog("[INERTIA_LOG]: \(message)")
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
            NSLog("[INERTIA_LOG]:  hierarchyId is nil")
            return nil
        }
        
        guard inertiaDataModel.states[hierarchyIdPrefix]?.trigger == true else {
            return nil
        }

        NSLog("[INERTIA_LOG]: [InertiaEditable.getAnimation] hierarchyId: \(hierarchyId), hierarchyIdPrefix: \(hierarchyIdPrefix)")
        NSLog("[INERTIA_LOG]: [InertiaEditable.getAnimation] actionableIdToAnimationIdMap: \(inertiaDataModel.actionableIdToAnimationIdMap)")
        NSLog("[INERTIA_LOG]: [InertiaEditable.getAnimation] available schema IDs: \(Array(inertiaDataModel.inertiaSchemas.keys))")

        // First try to get the animation ID from the map
        guard let animationId = inertiaDataModel.actionableIdToAnimationIdMap[hierarchyId] else {
            NSLog("[INERTIA_LOG]:  no mapping for hierarchyId: \(hierarchyId), trying hierarchyIdPrefix: \(hierarchyIdPrefix)")
            // If not in the map, try using hierarchyIdPrefix directly (fallback)
            guard let animation = inertiaDataModel.inertiaSchemas[hierarchyIdPrefix] else {
                NSLog("[INERTIA_LOG]:  animation not found for hierarchyId: \(hierarchyId) or hierarchyIdPrefix: \(hierarchyIdPrefix)")
                return nil
            }
            NSLog("[INERTIA_LOG]:  using hierarchyIdPrefix fallback: \(hierarchyIdPrefix)")
            return animation
        }

        // Look up the animation using the mapped animation ID
        guard let animation = inertiaDataModel.inertiaSchemas[animationId] else {
            NSLog("[INERTIA_LOG]:  animation not found for animationId: \(animationId)")
            return nil
        }
        NSLog("[INERTIA_LOG]:  found animation - hierarchyId: \(hierarchyId) -> animationId: \(animationId)")

        return animation
    }

//    func handleMessage(selectedIds: Set<ActionableIdPair>) {
//        NSLog("[INERTIA_LOG]: Az(selectedIds) \(selectedIds)")
//        // Update actionableIdPairs based on selectedIds
//        // Keep existing pairs that match selectedIds, remove others
//        inertiaDataModel?.actionableIdPairs = inertiaDataModel?.actionableIdPairs.filter { pair in
//            selectedIds.contains(pair)
//        } ?? Set()
////        inertiaDataModel?.actionableIdPairs
//    }
    
    func handleMessage(_ msg: Set<ActionableIdPair>) {
        NSLog("[INERTIA_LOG]: Received handleMessage with \(msg.count) IDs")
        var newPairs = Set(msg)

        NSLog("[INERTIA_LOG]: ✅ Updating actionableIdPairs from WS: \(newPairs)")
        
        if var model = inertiaDataModel {
            model.actionableIdPairs = newPairs
        }
    }
    
    func handleMessageSignal(_ signal: AnimationSignal) {
        switch signal {
        case .pause:
            inertiaDataModel?.pausePlayback()
        case .setLoopDuration(let duration):
            inertiaDataModel?.loopDuration = InertiaPlayback.clampLoopDuration(duration)
        }
    }
    
    func handleMessageSchema(schemaWrappers: [InertiaSchemaWrapper]) {
        NSLog("[INERTIA_LOG]: [handleMessageSchema] received \(schemaWrappers.count) schema wrappers")
        for schemaWrapper in schemaWrappers {
            NSLog("[INERTIA_LOG]: [handleMessageSchema] wrapper - containerId: \(schemaWrapper.container.containerId), actionableId: \(schemaWrapper.actionableId), animationId: \(schemaWrapper.animationId)")
            NSLog("[INERTIA_LOG]: [handleMessageSchema] my containerId: \(inertiaDataModel?.containerId ?? "nil")")

            if schemaWrapper.container.containerId == inertiaDataModel?.containerId {
                // Store the mapping from actionable ID to animation ID
                inertiaDataModel?.actionableIdToAnimationIdMap[schemaWrapper.actionableId] = schemaWrapper.animationId
                // Store the schema by its animation ID
                inertiaDataModel?.inertiaSchemas[schemaWrapper.animationId] = schemaWrapper.schema
                NSLog("[INERTIA_LOG]:  ✅ stored schema - animationId: \(schemaWrapper.animationId) actionableId: \(schemaWrapper.actionableId)")
                NSLog("[INERTIA_LOG]:  map now: \(inertiaDataModel?.actionableIdToAnimationIdMap ?? [:])")
            } else {
                NSLog("[INERTIA_LOG]:  ❌ skipped - container mismatch")
            }
        }
    }
    
    func handleMessageActionable(isActionable: Bool) {
        inertiaDataModel?.isActionable = isActionable
    }
}

public struct InertiaAnimationState: Identifiable, Equatable, Codable {
    public let id: InertiaID
    public var trigger: Bool?
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

public struct InertiaAnimationValues: VectorArithmetic, Animatable, Equatable, CustomStringConvertible {
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

extension InertiaAnimationValues {
    var isFinite: Bool {
        scale.isFinite && translate.width.isFinite && translate.height.isFinite
            && rotate.isFinite && rotateCenter.isFinite && opacity.isFinite
    }

    /// Falls back to the identity transform so a NaN slipping out of interpolation
    /// can't reach a geometry modifier, which traps.
    var sanitized: InertiaAnimationValues {
        isFinite ? self : InertiaAnimationValues(scale: 1, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1)
    }
}

extension InertiaAnimationSchema {
    /// `CubicKeyframe` divides by the keyframe duration when solving its spline, so a
    /// zero or negative duration produces NaN for every interpolated value. The editor
    /// records `playheadTime - previousTime`, which is zero for two keyframes captured
    /// at the same playhead position.
    var playableKeyframes: [InertiaAnimationKeyframe] {
        keyframes.compactMap { keyframe in
            guard keyframe.values.isFinite else { return nil }
            guard keyframe.duration.isFinite, keyframe.duration > 0 else {
                return InertiaAnimationKeyframe(id: keyframe.id, values: keyframe.values, duration: 0.001)
            }
            return keyframe
        }
    }

    /// The playable track held at its final values until `duration` is up.
    ///
    /// `keyframeAnimator` repeats a track at the track's own length, so a track
    /// that ends after one second restarts three times while a three-second one
    /// runs once — and the playhead, which follows the loop rather than any one
    /// actionable, would agree with neither. Padding gives every track the same
    /// period.
    func keyframes(filling duration: CGFloat) -> [InertiaAnimationKeyframe] {
        let track = playableKeyframes
        guard let last = track.last else { return track }

        let elapsed = track.reduce(CGFloat.zero) { $0 + $1.duration }
        let remainder = duration - elapsed
        guard remainder > 0.001 else { return track }

        return track + [
            InertiaAnimationKeyframe(id: "\(last.id)--hold", values: last.values, duration: remainder)
        ]
    }
}

// MARK: - Codable conformance for InertiaAnimationValues
extension InertiaAnimationValues: Codable {
    enum CodingKeys: String, CodingKey {
        case scale, translate, rotate, rotateCenter, opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scale = try container.decode(CGFloat.self, forKey: .scale)
        rotate = try container.decode(CGFloat.self, forKey: .rotate)
        rotateCenter = try container.decode(CGFloat.self, forKey: .rotateCenter)
        opacity = try container.decode(CGFloat.self, forKey: .opacity)

        // Decode translate as array [x, y]
        let translateArray = try container.decode([CGFloat].self, forKey: .translate)
        translate = CGSize(width: translateArray[0], height: translateArray[1])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotate, forKey: .rotate)
        try container.encode(rotateCenter, forKey: .rotateCenter)
        try container.encode(opacity, forKey: .opacity)

        // Encode translate as array [x, y]
        try container.encode([translate.width, translate.height], forKey: .translate)
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

func decodeInertiaSchemas(json: Data) -> [InertiaAnimationSchema]? {
    do {
        let schemas = try JSONDecoder().decode([InertiaAnimationSchema].self, from: json)
        return schemas
    } catch {
        print("Failed to decode JSON: \(error.localizedDescription)")
        return nil
    }
}
