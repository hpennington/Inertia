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
    /// The playhead was moved by hand; hold the animation at this many seconds
    /// into the loop.
    case seek(CGFloat)
    /// The editor's play button. Carries on from where `pause` or `seek` left
    /// off, and starts anything not running yet — including a `trigger`
    /// animation, which the app would otherwise have to start itself. Nothing
    /// but the editor sends signals, so this does not make a `trigger` animation
    /// self-starting in the app.
    case resume
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

    // Playback lives on `InertiaDataModel`, which is what `\.inertiaDataModel`
    // hands the app. This type used to carry `trigger`/`cancel`/`restart` of its
    // own against a data model it does not hold, so they did nothing at all.
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
    /// The selected node's center in the container's coordinate space, including
    /// the drag in progress. Guides are drawn from this, so it has to be an
    /// absolute position rather than a translation — a node need not be laid out
    /// at the container's center.
    var selectedNodeCenter: CGPoint = .zero
    var selectedNodeSize: CGSize = .zero
    var isActionable: Bool = false
    var isRunning:Bool = false

    /// The `sequence` of the last `MessageSignal` this runtime has applied.
    /// Echoed back on every `MessagePlaybackProgress` so the editor can tell
    /// a report caused by a signal it sent from one still in flight from
    /// before it, without racing a timeout.
    public internal(set) var lastProcessedSignalSequence: Int = 0

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

    /// Where the editor has parked the playhead, while it is parked there.
    ///
    /// Non-nil means the animation is being scrubbed rather than played: every
    /// actionable holds the values its track interpolates to at this time, so
    /// dragging the playhead walks the animation frame by frame. Playing again
    /// clears it and hands the screen back to the animators.
    public private(set) var seekTime: CGFloat? = nil

    // MARK: - App-facing controls

    /// Starts an animation that was waiting on its `trigger` invoke type.
    ///
    /// A trigger arriving while the animation is already running joins the run in
    /// progress rather than cutting it short — `restart(_:)` is the one that
    /// starts over. Cancelled animations are left where they are: stopping one is
    /// the app's call, and picking it back up is `restart(_:)`'s.
    public func trigger(_ id: InertiaID) {
        let state = states[id]
        guard state?.isCancelled != true, state?.trigger != true else { return }

        start(id)
    }

    /// Stops an animation and returns it to its initial values, where it stays
    /// until `restart(_:)`.
    ///
    /// The clock stops with the last animation running off it, since a playhead
    /// with nothing left to follow is one the editor should see parked.
    public func cancel(_ id: InertiaID) {
        states[id] = InertiaAnimationState(id: id, trigger: false, isCancelled: true)

        guard !states.values.contains(where: { $0.trigger == true }) else { return }

        isRunning = false
        clock?.cancel()
        clock = nil
        report(isRunning: false)
    }

    /// Clears a cancellation and plays from the top of the timeline.
    ///
    /// Every actionable in a container is drawn from the one clock, so this
    /// rewinds the playhead for all of them rather than for this animation alone
    /// — the same shared clock that makes a trigger mid-run join the run in
    /// progress instead of restarting it.
    public func restart(_ id: InertiaID) {
        clock?.cancel()
        clock = nil
        playheadTime = .zero

        start(id)
    }

    public func isCancelled(_ id: InertiaID) -> Bool {
        states[id]?.isCancelled == true
    }

    private func start(_ id: InertiaID) {
        states[id] = InertiaAnimationState(id: id, trigger: true, isCancelled: false)
        seekTime = nil
        isRunning = true
        startClock()
    }

    /// Starts every animation the app does not have to start itself.
    ///
    /// `invokeType` says who owns the start: a `trigger` animation waits for the
    /// app to call `trigger(_:)`, an `auto` one runs as soon as the runtime holds
    /// its schema — which is why this runs both when an actionable registers and
    /// when the editor sends a schema, whichever of the two arrives last.
    ///
    /// Cancelled animations are left where they are: stopping one is the app's
    /// call, and picking it back up is `restart(_:)`'s.
    func startAutoAnimations() {
        guard markTriggered(where: { $0.invokeType == .auto }) else { return }

        // A parked playhead means the editor is scrubbing, and starting the clock
        // would pull the run out from under whoever is dragging it.
        guard seekTime == nil else { return }

        isRunning = true
        startClock()
    }

    /// Marks every animation whose schema `matches` as started, and says whether
    /// any of them was not already. Cancelled ones are skipped.
    @discardableResult
    private func markTriggered(where matches: (InertiaAnimationSchema) -> Bool) -> Bool {
        var didStart = false

        for (prefix, schema) in inertiaSchemas where matches(schema) {
            if states[prefix] == nil {
                states[prefix] = InertiaAnimationState(id: prefix, trigger: false, isCancelled: false)
            }

            guard let state = states[prefix], !state.isCancelled, state.trigger != true else { continue }

            states[prefix]?.trigger = true
            didStart = true
        }

        return didStart
    }

    /// Stops the run and reports where it stopped, so a paused playhead sits
    /// exactly where the animation froze.
    ///
    /// Pausing parks the playhead where it is, which holds the frame on screen
    /// and is what playing again picks up from.
    func pausePlayback() {
        isRunning = false
        clock?.cancel()
        clock = nil
        seekTime = playheadTime
        report(isRunning: false)
    }

    /// The editor's play button: runs every animation, whatever its
    /// `invokeType`, picking a paused or scrubbed run back up where it was left.
    ///
    /// `auto` animations are already going by the time this arrives —
    /// `startAutoAnimations` starts those as soon as the runtime holds their
    /// schema. A `trigger` animation is waiting on the app to call `trigger(_:)`,
    /// which is not something the app does while its animation is being authored,
    /// so the editor stands in for the app and starts it here. Signals only ever
    /// come from the editor, so the same animation running without the editor
    /// attached still waits for its trigger, which is the whole point of the
    /// `trigger` invoke type.
    ///
    /// Cancelled animations are left where they are: stopping one is the app's
    /// call, and picking it back up is `restart(_:)`'s.
    func resumePlayback() {
        markTriggered(where: { _ in true })

        guard states.values.contains(where: { $0.trigger == true }) else { return }

        seekTime = nil
        isRunning = true
        startClock()
    }

    /// Freezes the animation at `time`.
    ///
    /// The editor is the one moving the playhead here, so this does not report
    /// back: the position it would send is the one it just asked for.
    func seek(to time: CGFloat) {
        isRunning = false
        clock?.cancel()
        clock = nil

        let time = time.clamped(to: 0...playbackDuration)
        seekTime = time
        playheadTime = time
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
    ///
    /// Playing picks up from wherever the playhead was left — scrubbed to, or
    /// paused at — rather than from the top. Only a playhead parked at the very
    /// end of the loop starts over, since there is nothing left to play.
    private func startClock() {
        guard clock == nil else { return }

        // Nothing loaded yet: there is no animation for the playhead to follow.
        guard !inertiaSchemas.isEmpty else { return }

        let offset = playheadTime < playbackDuration ? playheadTime : .zero
        playheadTime = offset
        report(isRunning: true)

        let start = ContinuousClock.now
        var tickCount = 0
        var lastDriftLogElapsed: Double = 0
        clock = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.clockInterval)
                guard !Task.isCancelled, let self, self.isRunning else { return }

                // Read each tick: the timeline can be resized mid-run.
                let duration = self.playbackDuration
                let elapsed = offset + (ContinuousClock.now - start).inSeconds

                // Diagnostic: how far real elapsed time has drifted from what
                // `tickCount` ticks at `clockInterval` should have taken. If
                // this grows over a run, the main actor in THIS process (the
                // app under test) is falling behind — i.e. the app itself is
                // CPU-starved, not just something in the editor's mirroring
                // path. Logged at most once every ~2s of playback.
                tickCount += 1
                let expectedElapsed = offset + Double(tickCount) * Self.clockInterval.inSeconds
                let driftMs = (elapsed - expectedElapsed) * 1000
                if elapsed - lastDriftLogElapsed >= 2 {
                    lastDriftLogElapsed = elapsed
                    InertiaLog.debug(String(format: "[diag] clock drift: %.0fms after %.1fs (tick #%d)", driftMs, elapsed, tickCount))
                }

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
                isRunning: isRunning,
                lastProcessedSequence: lastProcessedSignalSequence
            )
        )
    }

    public func registerHierarchyIdPrefix(_ prefix: String) {
        registeredHierarchyIdPrefixes.insert(prefix)
        // Initialize state for this prefix if it doesn't exist
        if states[prefix] == nil {
            states[prefix] = InertiaAnimationState(id: prefix, trigger: false, isCancelled: false)
        }

        // Schemas loaded off disk are already here by the time an actionable
        // appears, so this is where an `auto` animation gets going.
        startAutoAnimations()
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
                    InertiaLog.info("InertiaDataModel instantiated for container: \(id)")
                    let schemaMap = schemas.reduce(into: [String: InertiaAnimationSchema]()) { $0[$1.id] = $1 }
                    self._inertiaDataModel = State(
                        wrappedValue: InertiaDataModel(containerId: id, inertiaSchemas: schemaMap, tree: Tree(id: id), actionableIdPairs: Set())
                    )
                } else {
                    InertiaLog.error("Failed to decode the inertia schemas")
                    fatalError()
                }
            } else {
                InertiaLog.error("Failed to parse the inertia file")
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
    /// `selectedNodeCenter` is already in this container's coordinate space, so the
    /// guides land on the node wherever it happens to be laid out.
    @ViewBuilder
    private func dragAlignmentGuides(in size: CGSize) -> some View {
        let center = inertiaDataModel.selectedNodeCenter
        let selectedSize = inertiaDataModel.selectedNodeSize
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollDisabled(self.inertiaDataModel.isActionable)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Anchored to the filled container frame — the same frame the guide
            // canvas draws in — so positions measured in this space and points
            // drawn in the canvas share an origin.
            .coordinateSpace(.named(hierarchyId))
            .overlay {
                if inertiaDataModel.showGrid {
                    ZStack {
                        dragGrid
                        dragAlignmentGuides(in: proxy.size)
                    }
                }
            }
            // The editor channel is a development facility, so the container —
            // the one place that knows whether this is a dev build — decides
            // whether the runtime may dial the editor at all. Without this the
            // channel stays shut and the editable views' `start()` calls only
            // record that a connection was wanted.
            .onAppear { manager.setEnabled(dev) }
            .onChange(of: dev) { _, isDev in
                manager.setEnabled(isDev)
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

let manager = InertiaWebSocketClient.shared

struct InertiaCanvasSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    var inertiaContainerSize: CGSize {
        get { self[InertiaCanvasSizeKey.self] }
        set { self[InertiaCanvasSizeKey.self] = newValue }
    }
}

/// The animation schema behind an actionable — found through the editor's
/// actionable-to-animation mapping, or, for schemas loaded straight off disk,
/// under the prefix itself.
///
/// Deliberately free of playback state: the schema is what an actionable *has*,
/// not what it is doing. The values on screen are gated on the animation
/// running, but the shapes drawn behind it are not.
@MainActor
private func inertiaSchema(
    hierarchyId: String?,
    hierarchyIdPrefix: String,
    in model: InertiaDataModel?
) -> InertiaAnimationSchema? {
    guard let model, let hierarchyId else { return nil }

    guard let animationId = model.actionableIdToAnimationIdMap[hierarchyId] else {
        InertiaLog.debug("no mapping for hierarchyId: \(hierarchyId), trying hierarchyIdPrefix: \(hierarchyIdPrefix)")
        return model.inertiaSchemas[hierarchyIdPrefix]
    }

    return model.inertiaSchemas[animationId]
}

struct InertiaActionable<Content: View>: View {
    @State private var animation: InertiaAnimationSchema? = nil
    @State private var contentSize: CGSize = .zero
    @State private var vm = InertiaViewModel()
    @State private var hierarchyId: String? = nil
    /// This actionable's box in the container's space, as laid out — measured
    /// outside the animation, which is the only place it can be read honestly.
    /// The shapes are projected from it.
    @State private var layoutFrame: CGRect = .zero

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
    @Environment(\.inertiaEditor) var inertiaEditor
    
    var wrappedContent: some View {
        ZStack(alignment: .center) {
            content
        }
        // Inside the animated content, so the scale, rotation, offset and
        // opacity applied in `body` carry the shapes with them: the canvas is
        // the actionable's own graphics, not a backdrop it moves across.
        //
        // Aligned to the top-left rather than centred, because that corner is
        // where `containerCanvas` starts measuring from.
        .background(alignment: .topLeading) { containerCanvas }
    }

    /// The shapes authored against this actionable, if it has any. Read off the
    /// schema rather than the running animation so the backdrop is there
    /// whether or not the animation is playing.
    private var shapes: [InertiaShape] {
        inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel)?.shapes ?? []
    }

    /// The actionable's canvas: its shapes, drawn in Metal, behind its content.
    ///
    /// Sized and placed by the box the shapes themselves occupy — `size` is the
    /// actionable, and the shapes are multiples of it — so one reaching past the
    /// view it belongs to grows the canvas rather than being cut at any edge.
    /// The container is not in this: a canvas fitted to it stopped a shape at
    /// the window, and turned into a straight edge sweeping through the artwork
    /// as the view rotated.
    ///
    /// Takes no hits: it is a backdrop, and would otherwise swallow taps meant
    /// for the views it overlaps. Left out entirely when there is nothing to
    /// draw — this is one `MTKView` per actionable, and most have no shapes at
    /// all.
    @ViewBuilder
    private func backgroundView(for size: CGSize) -> some View {
        let shapes = self.shapes
        if let bounds = shapes.bounds, size.width > 0, size.height > 0 {
            InertiaCanvas(
                vm: vm,
                shapes: shapes.map { $0.normalized(to: bounds) }
            )
            .frame(width: bounds.width * size.width, height: bounds.height * size.height)
            .offset(x: bounds.minX * size.width, y: bounds.minY * size.height)
            .allowsHitTesting(false)
        }
    }

    /// The canvas behind this actionable, measured against the size layout gave
    /// it and anchored to its top-left corner — which is where the shapes'
    /// own box is offset from.
    ///
    /// The size is the measured layout frame's rather than a `GeometryReader`'s
    /// of its own. One inside here would be reading from within the animation:
    /// `frame(in:)` under a rotation reports the *bounding box* of the rotated
    /// view, which swells and shrinks as the angle turns, and re-measuring
    /// against it made the shapes pulse in step with the spin.
    @ViewBuilder
    private var containerCanvas: some View {
        backgroundView(for: layoutFrame.size)
    }

    /// The track the animator plays: held out to the full loop when repeating,
    /// so the animation and the editor's playhead share one period.
    func track(for animation: InertiaAnimationSchema) -> [InertiaAnimationKeyframe] {
        guard inertiaDataModel?.isRepeating ?? true else { return animation.playableKeyframes }

        return animation.keyframes(filling: inertiaDataModel?.playbackDuration ?? InertiaPlayback.defaultLoopDuration)
    }

    /// The same track as a timeline that can be evaluated at any point in it,
    /// which is what scrubbing needs and `keyframeAnimator` — a play button with
    /// no seek bar — cannot give.
    func timeline(for animation: InertiaAnimationSchema) -> KeyframeTimeline<InertiaAnimationValues> {
        KeyframeTimeline(initialValue: animation.initialValues.sanitized) {
            KeyframeTrack {
                for keyframe in track(for: animation) {
                    CubicKeyframe(keyframe.values, duration: keyframe.duration)
                }
            }
        }
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
    
    /// What to show right now, or nil when the animation is neither playing nor
    /// parked somewhere by the editor.
    ///
    /// Read off the runtime's own clock rather than handed to a
    /// `keyframeAnimator`, which is what this used to do. The runtime already
    /// runs a wall clock in every mode — it is what `playheadTime` counts, and
    /// what `startAutoAnimations` gets going the moment an actionable registers
    /// — so an animator kept a second, independent clock beside it that nothing
    /// started, synchronised or stopped. With the editor attached that went
    /// unnoticed, because `InertiaEditable` draws from the playhead and never
    /// builds an animator at all; a standalone build (`dev: false`) had only the
    /// animator, and showed nothing moving even while the runtime clock ticked.
    ///
    /// Sampling the track at the playhead is the same operation for playing,
    /// pausing and scrubbing, and it is what the editor's own view does — so an
    /// app in the field now draws frame for frame what was authored.
    func displayValues(for animation: InertiaAnimationSchema) -> InertiaAnimationValues? {
        guard let inertiaDataModel,
              inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil else { return nil }

        // A parked playhead holds there; a running one advances. Same read.
        let time = inertiaDataModel.seekTime ?? inertiaDataModel.playheadTime
        return timeline(for: animation).value(time: time).sanitized
    }

    var body: some View {
        //        GeometryReader { rootProxy in
        Group {
            if let animation = animation ?? getAnimation, let values = displayValues(for: animation) {
                wrappedContent
                    .scaleEffect(values.scale)
                    .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
                    .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                    .offset(x: values.translate.width * inertiaContainerSize.width, y: values.translate.height * inertiaContainerSize.height)
                    .opacity(values.opacity)
            } else {
                wrappedContent
            }
        }
    //            .frame(minWidth: contentSize.width, minHeight: contentSize.height)

        // One level out from every rendering effect above, so what the shapes
        // are projected from is where this view was laid out — not where the
        // animation has currently drawn it.
        .measuringLayoutFrame(in: inertiaContainerId) { frame in
            layoutFrame = frame
        }
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

    func handleMessageSignal(_ signal: AnimationSignal, sequence: Int) {
        inertiaDataModel?.lastProcessedSignalSequence = sequence
        switch signal {
        case .pause:
            inertiaDataModel?.pausePlayback()
        case .setLoopDuration(let duration):
            inertiaDataModel?.loopDuration = InertiaPlayback.clampLoopDuration(duration)
        case .seek(let time):
            inertiaDataModel?.seek(to: time)
        case .resume:
            inertiaDataModel?.resumePlayback()
        }
    }
    
    var getAnimation: InertiaAnimationSchema? {
        guard let inertiaDataModel else {
            InertiaLog.debug("inertiaDataModel is nil")
            return nil
        }

        guard let hierarchyId else {
            InertiaLog.debug("hierarchyId is nil")
            return nil
        }

        // Scrubbing shows the animation without running it.
        guard inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil else {
            return nil
        }

        guard inertiaDataModel.states[hierarchyIdPrefix]?.trigger == true else {
            return nil
        }

        InertiaLog.verbose("[InertiaActionable.getAnimation] hierarchyId: \(hierarchyId), hierarchyIdPrefix: \(hierarchyIdPrefix)")
        InertiaLog.verbose("[InertiaActionable.getAnimation] actionableIdToAnimationIdMap: \(inertiaDataModel.actionableIdToAnimationIdMap)")
        InertiaLog.verbose("[InertiaActionable.getAnimation] available schema IDs: \(Array(inertiaDataModel.inertiaSchemas.keys))")

        guard let animation = inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel) else {
            InertiaLog.debug("animation not found for hierarchyId: \(hierarchyId) or hierarchyIdPrefix: \(hierarchyIdPrefix)")
            return nil
        }

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

private extension View {
    /// Reports this view's layout frame in the named coordinate space, ignoring
    /// any `.offset` applied inside it. The wrapping container is what makes that
    /// true: an offset is layout-neutral, so the parent's frame stays where the
    /// child was laid out even as the child draws elsewhere.
    /// Does nothing without a container id: there is no space to measure against,
    /// and reporting a frame from some other space would put the guides somewhere
    /// arbitrary rather than leaving them off.
    @ViewBuilder
    func measuringLayoutFrame(
        in space: String?,
        _ report: @escaping (CGRect) -> Void
    ) -> some View {
        if let space {
            ZStack { self }
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(space))
                        Color.clear
                            .onAppear { report(frame) }
                            .onChange(of: frame) { _, newFrame in report(newFrame) }
                    }
                )
        } else {
            self
        }
    }
}

struct InertiaEditable<Content: View>: View {
    @State private var dragOffset: CGSize = .zero
    @State private var animation: InertiaAnimationSchema? = nil
    @State private var contentSize: CGSize = .zero
    @State private var vm = InertiaViewModel()
    @State private var hierarchyId: String? = nil
    @State private var selectedSize: CGSize = .zero
    /// The node's laid-out center in the container's coordinate space, before any
    /// drag offset. Measured outside `.offset` so it stays the layout position.
    @State private var baseCenter: CGPoint = .zero
    /// Where the node sat before the current gesture began. `DragGesture`
    /// reports translation relative to its own start, so without carrying the
    /// accumulated offset every drag after the first snaps back to the origin.
    @State private var startOffset: CGSize = .zero
    /// This node's box in the container's space, as laid out — measured outside
    /// both the animation and the drag. The shapes are projected from it.
    @State private var layoutFrame: CGRect = .zero

    /// The node's position in the container: everything before this gesture
    /// plus what this gesture has moved so far.
    private var totalOffset: CGSize {
        CGSize(
            width: startOffset.width + dragOffset.width,
            height: startOffset.height + dragOffset.height
        )
    }

    /// Where the node's center currently sits in the container, i.e. its layout
    /// position moved by the accumulated drag.
    private var currentCenter: CGPoint {
        CGPoint(
            x: baseCenter.x + totalOffset.width,
            y: baseCenter.y + totalOffset.height
        )
    }

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
    
    /// Whether this node is one of the editor's current selection. A node with
    /// no hierarchy id yet is never selected: `hierarchyId` is assigned on
    /// appear, and a pair always carries a concrete one.
    var isSelected: Bool {
        guard let hierarchyId else { return false }
        return inertiaDataModel?.actionableIdPairs.contains(where: { $0.hierarchyId == hierarchyId }) ?? false
    }

    var showSelectedBorder: Bool {
        InertiaLog.verbose("\(String(describing: hierarchyId)) \(hierarchyIdPrefix)")
        return isSelected
    }

    /// Only a selected node moves. Dragging is how the editor edits the
    /// selection, and `onEnded` sends the translation against *all* selected
    /// pairs — so letting an unselected node drag both moves something the user
    /// never picked and attributes its translation to the wrong nodes.
    private var isDraggable: Bool {
        (inertiaDataModel?.isActionable ?? false) && isSelected
    }

    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if isDraggable {
                    dragOffset = value.translation
                    inertiaDataModel?.showGrid = true
                    inertiaDataModel?.selectedNodeCenter = currentCenter
                    inertiaDataModel?.selectedNodeSize = selectedSize
                    manager.sendMessage(
                        InertiaMessage.MessageSelectedNodeProperties(
                            positionX: totalOffset.width,
                            positionY: totalOffset.height,
                            sizeX: selectedSize.width,
                            sizeY: selectedSize.height
                        )
                    )
                }
            }
            .onEnded { value in
                if isDraggable {
                    dragOffset = value.translation
                    // Fold this gesture into the accumulated position so the
                    // next one starts from where the node actually is.
                    let settled = totalOffset
                    startOffset = settled
                    dragOffset = .zero
                    inertiaDataModel?.showGrid = false
                    if let actionableIdPairs = inertiaDataModel?.actionableIdPairs {
                        manager.sendMessage(
                            InertiaMessage.MessageTranslation(
                                translationX: (settled.width) / (inertiaContainerSize.width),
                                translationY: (settled.height) / (inertiaContainerSize.height),
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
        // Behind the content and inside everything that moves it — the drag
        // below as well as the animation in `body` — so the shapes stay with
        // the node they belong to. See `InertiaActionable.wrappedContent`.
        .background(alignment: .topLeading) { containerCanvas }
        .onTapGesture {
            InertiaLog.debug("tapped \(content)")
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
            
            InertiaLog.info("Tapped: Starting to send data...")

            let tree = inertiaDataModel.tree
            let actionableIds = inertiaDataModel.actionableIdPairs
            let message = InertiaMessage.MessageActionables(tree: tree, actionableIds: actionableIds)
            manager.sendMessage(message)
        }
        .overlay {
            if showSelectedBorder && inertiaDataModel?.isActionable ?? false {
                Rectangle()
                    .stroke(Color.green)
            }
        }
        .offset(totalOffset)
        // Masked off rather than merely inert when this node isn't selected: an
        // attached DragGesture claims the drag even when its handlers do
        // nothing, which would stop a selected ancestor from being dragged. The
        // tap that selects lives on the subviews, so `.subviews` keeps it live.
        .gesture(dragGesture, including: isDraggable ? .all : .subviews)
        // Measured one level out: `.offset` is a geometry effect that carries the
        // view's own background and overlays with it, so anything attached inside
        // this wrapper reports the *dragged* position. The enclosing ZStack keeps
        // the layout frame, which is what `currentCenter` adds the drag to.
        .measuringLayoutFrame(in: inertiaContainerId) { frame in
            selectedSize = frame.size
            baseCenter = CGPoint(x: frame.midX, y: frame.midY)
        }
    }
    
    /// The shapes authored against this actionable, if it has any. Read off the
    /// schema rather than the running animation, so the editor shows the
    /// backdrop while the timeline is parked as well as while it plays.
    private var shapes: [InertiaShape] {
        inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel)?.shapes ?? []
    }

    /// The same canvas the shipped runtime draws behind an actionable, so what
    /// is authored here is what the app renders. See `InertiaActionable`.
    @ViewBuilder
    private func backgroundView(for size: CGSize) -> some View {
        let shapes = self.shapes
        if let bounds = shapes.bounds, size.width > 0, size.height > 0 {
            InertiaCanvas(
                vm: vm,
                shapes: shapes.map { $0.normalized(to: bounds) }
            )
            .frame(width: bounds.width * size.width, height: bounds.height * size.height)
            .offset(x: bounds.minX * size.width, y: bounds.minY * size.height)
            .allowsHitTesting(false)
        }
    }

    /// The canvas fitted to the shapes' own box. Sized and anchored exactly as
    /// the shipped runtime does it — see `InertiaActionable.containerCanvas`,
    /// which also has the reason both of them measure from a measured layout
    /// frame instead of a `GeometryReader` in here — so a shape sits where the
    /// editor shows it sitting.
    @ViewBuilder
    private var containerCanvas: some View {
        backgroundView(for: layoutFrame.size)
    }

    /// The track the animator plays: held out to the full loop when repeating,
    /// so the animation and the editor's playhead share one period.
    func track(for animation: InertiaAnimationSchema) -> [InertiaAnimationKeyframe] {
        guard inertiaDataModel?.isRepeating ?? true else { return animation.playableKeyframes }

        return animation.keyframes(filling: inertiaDataModel?.playbackDuration ?? InertiaPlayback.defaultLoopDuration)
    }

    /// The same track as a timeline that can be evaluated at any point in it,
    /// which is what scrubbing needs and `keyframeAnimator` — a play button with
    /// no seek bar — cannot give.
    func timeline(for animation: InertiaAnimationSchema) -> KeyframeTimeline<InertiaAnimationValues> {
        KeyframeTimeline(initialValue: animation.initialValues.sanitized) {
            KeyframeTrack {
                for keyframe in track(for: animation) {
                    CubicKeyframe(keyframe.values, duration: keyframe.duration)
                }
            }
        }
    }

    /// What to show right now, or nil when the animation is neither playing nor
    /// parked somewhere by the editor.
    ///
    /// The editor's copy of an animation is drawn from the runtime's own clock
    /// rather than handed to a `keyframeAnimator`, so playing, pausing and
    /// scrubbing are all the same thing: read the track at the playhead. It is
    /// also the only way play can pick up mid-loop — an animator can only ever
    /// start a track at its beginning.
    func displayValues(for animation: InertiaAnimationSchema) -> InertiaAnimationValues? {
        guard let inertiaDataModel,
              inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil else { return nil }

        return timeline(for: animation).value(time: inertiaDataModel.playheadTime).sanitized
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
            if let animation = animation ?? getAnimation, let values = displayValues(for: animation) {
                wrappedContent
                    .scaleEffect(values.scale)
                    .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
                    .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                    .offset(x: values.translate.width * inertiaContainerSize.width, y: values.translate.height * inertiaContainerSize.height)
                    .opacity(values.opacity)
                    .onAppear {
                        self.startOffset = CGSize(
                            width: animation.initialValues.translate.width * inertiaContainerSize.width,
                            height: animation.initialValues.translate.height * inertiaContainerSize.height
                        )
                        self.dragOffset = .zero
                    }
            } else {
                wrappedContent
            }
        }
    //            .frame(minWidth: contentSize.width, minHeight: contentSize.height)

        // Outside the animation and outside the drag, so the shapes are
        // projected from where this node was laid out rather than from wherever
        // it has been drawn or dragged to. Both of those then move the canvas
        // as rendering effects, which is what keeps it stuck to the node.
        .measuringLayoutFrame(in: inertiaContainerId) { frame in
            layoutFrame = frame
        }
        .environment(\.inertiaParentID, hierarchyId)
        .environment(\.isInertiaContainer, false)
        .buttonStyle(.plain)
        .onAppear {
            updateHierarchyId()

            InertiaLog.info("Connecting to the editor (setup)...")
            manager.start()

            manager.messageReceived = handleMessage
            manager.messageReceivedSchema = handleMessageSchema
            manager.messageReceivedIsActionable = handleMessageActionable
            manager.messageReceivedSignal = handleMessageSignal(_:sequence:)
        }
        .onChange(of: manager.isConnected, { oldValue, newValue in
            // An editor just attached — push the current hierarchy so it can
            // render the tree without waiting for the next change.
            guard newValue, let inertiaDataModel else {
                return
            }

            InertiaLog.info("Editor attached, sending current tree...")
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
            InertiaLog.debug("onAppear: \(String(describing: hierarchyId))")
            if oldValue != nil {
                return
            }

            guard let hierarchyId else {
                return
            }

            InertiaLog.debug("adding relationship: hierarchyId: \(hierarchyId) inertiaParentID: \(String(describing: inertiaParentID)), isInertiaContainer: \(isInertiaContainer)")
            inertiaDataModel?.tree.addRelationship(id: hierarchyId, parentId: inertiaParentID, parentIsContainer: isInertiaContainer)
            if let tree = inertiaDataModel?.tree {
                for node in tree.nodeMap.values {
                    node.tree = tree
                    node.link()
                }
            }

            InertiaLog.debug("Starting to send data 2...")
            manager.start()

            if let tree = inertiaDataModel?.tree {
                InertiaLog.verbose("tree \(tree)")
                if let actionableIdPairs = inertiaDataModel?.actionableIdPairs {
                    InertiaLog.verbose("tree \(actionableIdPairs)")
                    let message = InertiaMessage.MessageActionables(tree: tree, actionableIds: actionableIdPairs)
                    InertiaLog.verbose("\(message)")
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
            InertiaLog.debug("inertiaDataModel is nil")
            return nil
        }

        guard let hierarchyId else {
            InertiaLog.debug("hierarchyId is nil")
            return nil
        }

        guard inertiaDataModel.states[hierarchyIdPrefix]?.trigger == true else {
            return nil
        }

        InertiaLog.verbose("[InertiaEditable.getAnimation] hierarchyId: \(hierarchyId), hierarchyIdPrefix: \(hierarchyIdPrefix)")
        InertiaLog.verbose("[InertiaEditable.getAnimation] actionableIdToAnimationIdMap: \(inertiaDataModel.actionableIdToAnimationIdMap)")
        InertiaLog.verbose("[InertiaEditable.getAnimation] available schema IDs: \(Array(inertiaDataModel.inertiaSchemas.keys))")

        guard let animation = inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel) else {
            InertiaLog.debug("animation not found for hierarchyId: \(hierarchyId) or hierarchyIdPrefix: \(hierarchyIdPrefix)")
            return nil
        }

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
        InertiaLog.debug("Received handleMessage with \(msg.count) IDs")
        var newPairs = Set(msg)

        InertiaLog.debug("✅ Updating actionableIdPairs from WS: \(newPairs)")

        if var model = inertiaDataModel {
            model.actionableIdPairs = newPairs
        }
    }
    
    func handleMessageSignal(_ signal: AnimationSignal, sequence: Int) {
        inertiaDataModel?.lastProcessedSignalSequence = sequence
        switch signal {
        case .pause:
            inertiaDataModel?.pausePlayback()
        case .setLoopDuration(let duration):
            inertiaDataModel?.loopDuration = InertiaPlayback.clampLoopDuration(duration)
        case .seek(let time):
            inertiaDataModel?.seek(to: time)
        case .resume:
            inertiaDataModel?.resumePlayback()
        }
    }

    func handleMessageSchema(schemaWrappers: [InertiaSchemaWrapper]) {
        InertiaLog.debug("[handleMessageSchema] received \(schemaWrappers.count) schema wrappers")
        for schemaWrapper in schemaWrappers {
            InertiaLog.verbose("[handleMessageSchema] wrapper - containerId: \(schemaWrapper.container.containerId), actionableId: \(schemaWrapper.actionableId), animationId: \(schemaWrapper.animationId)")
            InertiaLog.verbose("[handleMessageSchema] my containerId: \(inertiaDataModel?.containerId ?? "nil")")

            if schemaWrapper.container.containerId == inertiaDataModel?.containerId {
                // Store the mapping from actionable ID to animation ID
                inertiaDataModel?.actionableIdToAnimationIdMap[schemaWrapper.actionableId] = schemaWrapper.animationId
                // Store the schema by its animation ID
                inertiaDataModel?.inertiaSchemas[schemaWrapper.animationId] = schemaWrapper.schema
                InertiaLog.info("✅ stored schema - animationId: \(schemaWrapper.animationId) actionableId: \(schemaWrapper.actionableId)")
                InertiaLog.verbose("map now: \(inertiaDataModel?.actionableIdToAnimationIdMap ?? [:])")
            } else {
                InertiaLog.warning("❌ skipped - container mismatch")
            }
        }

        // Schemas arriving from the editor are the other order round: the
        // actionables are already on screen, and this is the moment the runtime
        // learns which of them start on their own.
        inertiaDataModel?.startAutoAnimations()
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
{"id": \(id), "initialValues": \(initialValues), "invokeType": \(invokeType), "keyframes": \(keyframes), shapes: \(shapes)}
"""
    }

    public let id: InertiaID
    public let initialValues: InertiaAnimationValues
    public let invokeType: InertiaAnimationInvokeType
    public let keyframes: [InertiaAnimationKeyframe]
    /// What the actionable's canvas draws behind it. Optional to author, so an
    /// animation recorded before shapes existed — or one that simply wants
    /// none — still decodes.
    public let shapes: [InertiaShape]

    public init(id: InertiaID, initialValues: InertiaAnimationValues, invokeType: InertiaAnimationInvokeType, keyframes: [InertiaAnimationKeyframe], shapes: [InertiaShape] = []) {
        self.id = id
        self.initialValues = initialValues
        self.invokeType = invokeType
        self.keyframes = keyframes
        self.shapes = shapes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(InertiaID.self, forKey: .id)
        self.initialValues = try container.decode(InertiaAnimationValues.self, forKey: .initialValues)
        self.invokeType = try container.decode(InertiaAnimationInvokeType.self, forKey: .invokeType)
        self.keyframes = try container.decode([InertiaAnimationKeyframe].self, forKey: .keyframes)
        self.shapes = try container.decodeIfPresent([InertiaShape].self, forKey: .shapes) ?? []
    }
}

// Helper to create an empty schema for dev mode
func InertiaSchemaAnimation() -> InertiaAnimationSchema {
    InertiaAnimationSchema(
        id: "",
        initialValues: .zero,
        invokeType: .auto,
        keyframes: [],
        shapes: []
    )
}

func decodeInertiaSchemas(json: Data) -> [InertiaAnimationSchema]? {
    do {
        let schemas = try JSONDecoder().decode([InertiaAnimationSchema].self, from: json)
        return schemas
    } catch {
        InertiaLog.error("Failed to decode JSON: \(error.localizedDescription)")
        return nil
    }
}
