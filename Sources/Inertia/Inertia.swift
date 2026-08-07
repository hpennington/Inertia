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
    /// off, and starts the animations that start themselves — the `auto` ones.
    /// A `trigger` animation is the app's to start and goes on waiting, exactly
    /// as it would with no editor attached.
    case resume
    /// The editor's Trigger action on the named animation, standing in for the
    /// `trigger(_:)` call the app would make. Its own signal rather than
    /// something `resume` does on the side, so the play button means the same
    /// thing in the editor as arriving on the screen does in the app.
    case trigger(InertiaID)
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

    /// Files a node under its parent, and is safe to call again for a node this
    /// tree already holds.
    ///
    /// Idempotent because a view registers itself whenever its hierarchy id
    /// lands, and a view that goes off screen and comes back — a tab switch is
    /// one — lands the same id a second time. Appending blindly gave the parent
    /// two children with one id, so the hierarchy the editor drew listed the
    /// node twice while only one of the rows answered to the selection.
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

            if parentNode.children?.contains(where: { $0.id == id }) != true {
                parentNode.addChild(currentNode)
            }

            if parentIsContainer {
                // If explicitly marked as root, set it as the root node
                rootNode = parentNode
            } else if rootNode == nil && parentNode.parent == nil {
                rootNode = parentNode
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
    /// One hierarchy per container instance, keyed by the container's
    /// `hierarchyId` — which is also the id of the tree filed under it.
    ///
    /// Keyed rather than held singly because a container's `hierarchyId` is what
    /// tells its instances apart, and one app can have several on screen or
    /// swap between them: the demo's `animation_\(selectedTab)` is a different
    /// container per tab, drawing a different set of nodes. A `Tree` has one
    /// `rootNode`, so a shared one could only ever describe whichever container
    /// registered last — every message the runtime sent afterwards carried that
    /// container's hierarchy no matter which one the user was acting in, and the
    /// editor merged the selection into the wrong panel.
    var trees: [String: Tree] = [:]
    /// What is picked in each container, keyed the same way as `trees`.
    ///
    /// Split for the reason the trees are: a `MessageActionables` is a tree and
    /// the selection made *in* it, so sending one container's tree with every
    /// container's selection tells the editor that nodes it cannot see in that
    /// hierarchy are picked in it.
    var actionableIdPairsByContainer: [String: Set<ActionableIdPair>] = [:]
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
    /// Which property a gesture on a selected node edits, as picked in the
    /// editor's toolbar. `.translate` until the editor says otherwise, which is
    /// also what a runtime that reconnects mid-session falls back to until the
    /// editor resends.
    var activeTool: InertiaTool = .translate
    var isRunning: Bool = false

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

    /// How long one loop lasts.
    ///
    /// Seeded from the schemas — the loop is part of what was authored, so a
    /// shipped build loops over the span its animation was drawn against
    /// without anything having to tell it — and moved from there by the
    /// editor's timeline. Applies from the next tick of the clock, so resizing
    /// the timeline mid-run stretches the loop rather than waiting for it to be
    /// restarted.
    public var loopDuration: CGFloat = InertiaPlayback.defaultLoopDuration

    /// The loop `schemas` were authored against.
    ///
    /// The longest, where a hand-edited file disagrees with itself: the loop is
    /// what every track is padded out to, and the shorter answer would cut the
    /// track that asked for more off at the knees.
    static func authoredLoopDuration(of schemas: [InertiaID: InertiaAnimationSchema]) -> CGFloat? {
        schemas.values.map(\.loopDuration).max()
    }

    /// Takes the loop length from the schemas now loaded.
    ///
    /// Called wherever `inertiaSchemas` is replaced or added to. An empty set
    /// leaves the current loop alone rather than snapping back to the default —
    /// the editor clears schemas between sends, and the timeline is not asking
    /// for a different length when it does.
    func adoptLoopDurationFromSchemas() {
        guard let authored = Self.authoredLoopDuration(of: inertiaSchemas) else { return }

        loopDuration = InertiaPlayback.clampLoopDuration(authored)
    }

    /// Takes the project the editor is holding, in place of the one this
    /// container was drawing.
    ///
    /// Everything an animation carries — its track, its shapes, the keypoints on
    /// them — travels inside its schema, so replacing the map is what makes an
    /// edit of any kind visible, deletions included. What is no longer sent is
    /// no longer part of the project: the actionable it was authored against
    /// goes back to being an ordinary view, and the shapes it drew go with it.
    ///
    /// A deleted animation's playback state goes too, rather than being left
    /// behind marked as running. Nothing is lost by it — a state for an id no
    /// one holds a schema for reads exactly as one that has not been triggered
    /// — and an animation authored again under the same name starts from a
    /// state that agrees it has not run yet.
    func replaceSchemas(
        _ schemas: [InertiaID: InertiaAnimationSchema],
        actionableIdToAnimationIdMap: [String: String]
    ) {
        let removed = Set(inertiaSchemas.keys).subtracting(schemas.keys)

        inertiaSchemas = schemas
        self.actionableIdToAnimationIdMap = actionableIdToAnimationIdMap

        for id in removed {
            states.removeValue(forKey: id)
        }
    }

    /// One turn of the timeline: where a run ends, and where a repeating one
    /// wraps back to the start.
    ///
    /// The full loop, not the last keyframe — tracks are padded out to it — so
    /// the playhead crosses the whole timeline however early the animation
    /// settles. Anything recorded past the end of the loop stretches it, which
    /// keeps every track the same length as every other.
    var playbackDuration: CGFloat {
        InertiaPlayback.duration(loop: loopDuration, of: inertiaSchemas.values)
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

        // The playhead is back at zero, which ends the pass of anything else
        // that was triggered — the same rule as everywhere else, so a restart
        // does not quietly carry another animation's run over the boundary.
        retireTriggeredAnimations(holdingAt: .zero)

        start(id)
    }
    
    /// Rewinds the playhead and plays this container's `auto` animations from
    /// the top.
    ///
    /// What a container reaches for when it is handed a new `hierarchyId`: the
    /// screen just navigated to plays its animations again rather than holding
    /// the final frame of the run they finished the first time round.
    ///
    /// `invokeType` decides who plays, here as everywhere else. Arriving on a
    /// screen is the app deciding to show what is on it — it is not the
    /// `trigger(_:)` call a `trigger` animation is still waiting for, and
    /// starting one here played animations the app had said it would start
    /// itself. Those are returned to their initial values instead, so the screen
    /// offers them from the top when the app does trigger them — the editor's
    /// Trigger action included, which is a `trigger(_:)` call like any other.
    public func restartAll() {
        clock?.cancel()
        clock = nil
        playheadTime = .zero

        startAll()
    }


    public func isCancelled(_ id: InertiaID) -> Bool {
        states[id]?.isCancelled == true
    }

    /// Where to read `prefix`'s track, or nil when its run is not on screen at
    /// all and the animation is drawn at the values it starts from.
    ///
    /// The one answer to both halves of that question, so that whether a track
    /// shows and where it has got to can never disagree — which they did once a
    /// finished pass started holding a frame of its own rather than the
    /// playhead's.
    ///
    /// Three states in it: a run on screen — playing, or parked in the track by
    /// the editor — reads at the playhead; a triggered run that has had its pass
    /// holds the frame it ended on, whatever the playhead does afterwards, until
    /// it is triggered again; anything else is not drawn from its track.
    func trackTime(for prefix: InertiaID) -> CGFloat? {
        guard let state = states[prefix], !state.isCancelled else { return nil }

        if let heldTime = state.heldTime { return heldTime }

        // Scrubbing shows the animation without running it.
        guard isRunning || seekTime != nil, state.trigger == true else { return nil }

        return seekTime ?? playheadTime
    }

    private func start(_ id: InertiaID) {
        states[id] = InertiaAnimationState(id: id, trigger: true, isCancelled: false)
        seekTime = nil
        isRunning = true
        startClock()
    }
    
    /// Puts every animation in this container back to the state it is in when
    /// the screen it is on has just appeared: `auto` ones running from the top,
    /// `trigger` ones waiting at their initial values.
    ///
    /// Every schema as well as every state, since an animation that has never
    /// run has no state to rewind and is exactly the one this has to start. A
    /// cancellation goes with the screen that was cancelled on: the app's next
    /// `trigger(_:)` on this one is answered rather than dropped.
    private func startAll() {
        var didStart = false

        for id in Set(states.keys).union(inertiaSchemas.keys) {
            let isAuto = inertiaSchemas[id]?.invokeType == .auto
            states[id] = InertiaAnimationState(id: id, trigger: isAuto, isCancelled: false)
            didStart = didStart || isAuto
        }

        seekTime = nil

        // A screen of nothing but `trigger` animations has no run to follow, and
        // a clock started for it would report a playhead crossing a timeline
        // nothing is drawn from.
        guard didStart else {
            isRunning = false
            report(isRunning: false)
            return
        }

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
    /// The same set with the editor attached as without, which is what settles
    /// the race between a `resume` and the schemas it was sent alongside: an
    /// `auto` animation whose schema lands after the play button starts itself
    /// here rather than waiting to be told, and a `trigger` one was never the
    /// play button's to start.
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
            // Playing again is what lets go of the frame a finished pass was
            // left holding.
            states[prefix]?.heldTime = nil
            didStart = true
        }

        return didStart
    }

    /// Puts the `trigger` animations that have played their pass back to
    /// waiting, holding each where `time` leaves it.
    ///
    /// A trigger is answered once. The run it asked for ends when the playhead
    /// goes back to zero, and the animation has to be asked for again — the
    /// first trigger of a repeating container's life would otherwise leave it
    /// playing for as long as the app was on screen, and a second call would
    /// have nothing to do. An `auto` animation is not answering anything, so it
    /// simply plays the next pass.
    ///
    /// The end of a pass is the end of the *loop* rather than the end of the
    /// track, which is not the same instant: a track that stops moving half a
    /// second into a three-second loop is padded out to it like every other, and
    /// ending its pass where it settled would cut short a pass it is meant to be
    /// holding through. The transport ends one too — play, pause, or the
    /// playhead dragged back to the start — since each is a request about the
    /// timeline rather than the answer to a trigger.
    ///
    /// What ends is the run, not what is on screen: `heldTime` is the frame the
    /// animation was showing at that moment, and it stays on it until the next
    /// trigger replays it. Every caller passes the playhead the node is drawn
    /// at, so nothing moves at the instant a pass ends.
    ///
    /// The clock goes down with the last thing running off it, the same as a
    /// cancellation: a playhead with nothing left to follow is one the editor
    /// should see parked. Reporting that is left to the caller, each of which is
    /// about to say something about the run anyway.
    private func retireTriggeredAnimations(holdingAt time: CGFloat) {
        for (prefix, schema) in inertiaSchemas where schema.invokeType == .trigger {
            guard states[prefix]?.trigger == true else { continue }

            states[prefix]?.trigger = false
            states[prefix]?.heldTime = time
        }

        guard !states.values.contains(where: { $0.trigger == true }) else { return }

        isRunning = false
        clock?.cancel()
        clock = nil
    }

    /// Stops the run and reports where it stopped, so a paused playhead sits
    /// exactly where the animation froze.
    ///
    /// Pausing parks the playhead where it is, which holds the frame on screen
    /// and is what playing again picks up from — for the `auto` animations. A
    /// triggered one has had its pass ended by the transport being touched at
    /// all, so it is back at its initial values waiting to be asked again.
    func pausePlayback() {
        retireTriggeredAnimations(holdingAt: playheadTime)

        isRunning = false
        clock?.cancel()
        clock = nil
        seekTime = playheadTime
        report(isRunning: false)
    }

    /// The editor's play button: picks a paused or scrubbed run back up where it
    /// was left, and starts the animations that start themselves.
    ///
    /// The `auto` ones, which are the same set `startAutoAnimations` plays and
    /// has usually played already — what is left for this to start is one whose
    /// schema arrived while the playhead was parked, where starting the clock
    /// would have pulled the run out from under whoever was scrubbing.
    ///
    /// A `trigger` animation goes on waiting for the app's `trigger(_:)` call —
    /// and one that was mid-pass is put back to waiting, since pressing play is
    /// asking for the run the timeline describes rather than for the one a
    /// trigger asked for. Playing is not that call either: the play button asks
    /// the runtime to run the animation it would be running anyway, so what the
    /// editor shows is what the app will do. Standing in for the app is the
    /// Trigger action's job, and it arrives as `AnimationSignal.trigger` rather
    /// than riding along with this.
    ///
    /// Cancelled animations are left where they are: stopping one is the app's
    /// call, and picking it back up is `restart(_:)`'s.
    func resumePlayback() {
        let wasRunning = isRunning

        // Unparked before the bail-out below, not after: a play following a
        // pause has to release the playhead even when the schemas it applies to
        // have not arrived yet, or `startAutoAnimations` finds it still parked
        // and declines to start the run they were meant to join.
        seekTime = nil

        retireTriggeredAnimations(holdingAt: playheadTime)
        markTriggered(where: { $0.invokeType == .auto })

        // Nothing to play, either because the schemas this request arrived ahead
        // of are still on their way — they start themselves in
        // `startAutoAnimations` when they land, and reporting a stop against
        // that would flip the transport back and forth for the round trip — or
        // because everything here is waiting on a trigger this is not, which is
        // worth saying if it means a run just ended.
        guard states.values.contains(where: { $0.trigger == true }) else {
            if wasRunning {
                report(isRunning: false)
            }
            return
        }

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

        // Back at the start of the timeline, which is where a pass ends however
        // the playhead got there — see `retireTriggeredAnimations`.
        if time == .zero {
            retireTriggeredAnimations(holdingAt: .zero)
        }

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
                    let wrapped = elapsed.truncatingRemainder(dividingBy: duration)

                    // The timeline has come round, so whatever was triggered has
                    // had the pass it was triggered for. Held at the end of the
                    // loop, which is the frame it is on as it comes round.
                    if wrapped < self.playheadTime {
                        self.retireTriggeredAnimations(holdingAt: duration)

                        guard self.isRunning else {
                            self.playheadTime = wrapped
                            self.report(isRunning: false)
                            return
                        }
                    }

                    self.playheadTime = wrapped
                    self.report(isRunning: true)
                    continue
                }

                // A run that plays once holds its final frame instead: nothing
                // retires here, because the playhead stops at the end of the
                // loop rather than coming back round to the start of it.
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

    /// The hierarchy a container is building, made the first time it is asked
    /// for. The tree is named after the container instance, so the editor —
    /// which files what it is told by `tree.id` — keeps one panel per container
    /// rather than one per app.
    ///
    /// Mutating, so it belongs in `onAppear`/`onChange` rather than anywhere a
    /// view body reaches: making a tree while SwiftUI is reading this object is
    /// a write during view update. `tree(reading:)` is the read-only view of it.
    func tree(for containerId: String) -> Tree {
        if let tree = trees[containerId] { return tree }

        let tree = Tree(id: containerId)
        trees[containerId] = tree
        return tree
    }

    /// The container's hierarchy if it has started one, without making it.
    func tree(reading containerId: String?) -> Tree? {
        guard let containerId else { return nil }
        return trees[containerId]
    }

    /// What is picked in one container.
    func actionableIdPairs(in containerId: String?) -> Set<ActionableIdPair> {
        guard let containerId else { return [] }
        return actionableIdPairsByContainer[containerId] ?? []
    }

    /// Picks a pair in a container, or unpicks it if it was already picked.
    func toggleActionableIdPair(_ pair: ActionableIdPair, in containerId: String) {
        var pairs = actionableIdPairsByContainer[containerId] ?? []
        if pairs.contains(pair) {
            pairs.remove(pair)
        } else {
            pairs.insert(pair)
        }
        actionableIdPairsByContainer[containerId] = pairs
    }

    /// Replaces what is picked in one container — what the editor saying so
    /// amounts to. Left alone are the other containers, which the editor was not
    /// talking about.
    func setActionableIdPairs(_ pairs: Set<ActionableIdPair>, in containerId: String) {
        actionableIdPairsByContainer[containerId] = pairs
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

    public init(containerId: InertiaID, inertiaSchemas: [InertiaID: InertiaAnimationSchema]) {
        self.containerId = containerId
        self.inertiaSchemas = inertiaSchemas
        // Initialize from schema keys
        self.registeredHierarchyIdPrefixes = Set(inertiaSchemas.keys)
        // Initialize states for all schema keys
        self.states = inertiaSchemas.keys.reduce(into: [:]) { result, key in
            result[key] = InertiaAnimationState(id: key, trigger: false, isCancelled: false)
        }
        // Schemas loaded off disk carry the loop they were authored against —
        // in a shipped build nothing else ever says what it is.
        if let authored = Self.authoredLoopDuration(of: inertiaSchemas) {
            self.loopDuration = InertiaPlayback.clampLoopDuration(authored)
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

/// The frame every animation in it is measured against.
///
/// A `translate` of 1 crosses the whole container, so what the container *is*
/// has to mean the same thing on every runtime or one authored animation moves a
/// different distance on each. It is the space the host offers this view,
/// filled: `GeometryReader` takes the whole proposal, and the frames below hold
/// the content out to it. The Compose runtime's `fillMaxSize()` container and
/// the React runtime's `width: 100%; height: 100%` div are the same rectangle.
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
                wrappedValue: InertiaDataModel(containerId: id, inertiaSchemas: [:])
            )
        } else {
            // Read as bytes rather than text: an animation file is MessagePack,
            // and most of it is not valid UTF-8.
            if let url = bundle.url(forResource: id, withExtension: InertiaCoding.fileExtension) {
                if let data = try? Data(contentsOf: url),
                   let schemas = decodeInertiaSchemas(data: data) {
                    InertiaLog.info("InertiaDataModel instantiated for container: \(id)")
                    let schemaMap = schemas.reduce(into: [String: InertiaAnimationSchema]()) { $0[$1.id] = $1 }
                    self._inertiaDataModel = State(
                        wrappedValue: InertiaDataModel(containerId: id, inertiaSchemas: schemaMap)
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
        // Guides are drawn, never touched — the same as `dragAlignmentGuides`,
        // which has said so all along. These two lines appear the moment a move
        // starts, directly over the node being moved, and a hittable view
        // arriving mid-gesture is one the rest of that gesture can land on
        // instead.
        .allowsHitTesting(false)
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
            // Plays this container's animations again whenever the app hands it
            // a new `hierarchyId`.
            //
            // A `hierarchyId` is what the app names the screen this container is
            // currently showing, so a change of one is a navigation — and the
            // screen arrived at should play its animations rather than hold the
            // final frame of the run they finished the first time it was up. The
            // Compose and React runtimes restart on the same signal.
            //
            // Watched here rather than inside each actionable, which is where
            // this used to live. An actionable only sees the change while the
            // navigation keeps it mounted, so a screen torn down on the way out
            // restarted nothing at all — and `InertiaEditable`, the half of the
            // pair the editor is actually looking at, never watched it in the
            // first place, which is why switching tabs under the editor played
            // nothing on this runtime while it played on the other two. One
            // container, one restart per change.
            //
            // No guard on the first id, unlike the other two: `onChange` fires
            // on changes only, where a `LaunchedEffect` and a `useEffect` also
            // run on the composition/mount they are keyed into.
            .onChange(of: hierarchyId) { _, _ in
                inertiaDataModel.restartAll()
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
    /// The size the editor has already been told about, so layout reporting the
    /// same box again does not put another message on the wire.
    @State private var reportedSize: CGSize? = nil

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
        // Centred, because the middle of the view is the origin a shape's own
        // coordinates are measured from — see `InertiaShapesView.body`.
        //
        // Two canvases, on the two sides of the content, because that is what a
        // shape's `position` picks between — see `InertiaShapePosition`.
        .background(alignment: .center) { containerCanvas }
        .overlay(alignment: .center) { containerOverlayCanvas }
    }

    /// The shapes authored against this actionable, if it has any. Read off the
    /// schema rather than the running animation so the backdrop is there
    /// whether or not the animation is playing.
    private var shapes: [InertiaShape] {
        inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel)?.shapes ?? []
    }

    /// The actionable's canvases for one side of its content: the shapes drawn
    /// there, in Metal. Sized and placed by the box the shapes occupy — `size`
    /// is the actionable, and the shapes are multiples of it — and each shape
    /// carrying a track of its own drawn on a canvas of its own, moved by that
    /// track. See `InertiaShapesView`.
    ///
    /// Left out entirely when there is nothing to draw on that side: a canvas is
    /// an `MTKView`, and most actionables have no shapes at all.
    @ViewBuilder
    private func canvasView(for size: CGSize, at position: InertiaShapePosition) -> some View {
        let shapes = self.shapes.filter { $0.position == position && isShowing($0) }
        if !shapes.isEmpty {
            InertiaShapesView(
                vm: vm,
                shapes: shapes,
                size: size,
                containerSize: inertiaContainerSize,
                values: shapeDisplayValues(for:)
            )
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
        canvasView(for: layoutFrame.size, at: .bottom)
    }

    /// The same canvas on the other side of the content, for the shapes
    /// authored to sit over the view rather than behind it. Measured and
    /// anchored identically: the two differ in nothing but which modifier hangs
    /// them off the content.
    @ViewBuilder
    private var containerOverlayCanvas: some View {
        canvasView(for: layoutFrame.size, at: .top)
    }

    /// The track as a timeline that can be evaluated at any point in it, which
    /// is what scrubbing needs and `keyframeAnimator` — a play button with no
    /// seek bar — cannot give.
    ///
    /// Held out to the full loop when repeating, so the animation and the
    /// editor's playhead share one period. Built by the schema itself, so the
    /// editor's canvas — which has no data model to ask — pads and samples the
    /// same track this does.
    func timeline(for animation: InertiaAnimationSchema) -> KeyframeTimeline<InertiaAnimationValues> {
        let isRepeating = inertiaDataModel?.isRepeating ?? true
        let loop = inertiaDataModel?.playbackDuration ?? InertiaPlayback.defaultLoopDuration

        return animation.timeline(filling: isRepeating ? loop : nil)
    }

    /// Names this node, once.
    ///
    /// Claimed once per view and never re-claimed: this runs from `.task`, which
    /// starts again every time the view comes back on screen, and taking a fresh
    /// index each time renamed a node that had not moved. Everything already
    /// filed under the old name — the node in the tree, the selection the editor
    /// is holding, the measurement, the schema mapping — went on naming a view
    /// that no longer answered to it.
    @MainActor
    func updateHierarchyId() {
        guard hierarchyId == nil else { return }

        let index = indexManager?.claimIndex(containerId: inertiaContainerId, prefix: hierarchyIdPrefix) ?? .zero
        hierarchyId = "\(hierarchyIdPrefix)--\(index)"
        // Register this prefix with the data model
        inertiaDataModel?.registerHierarchyIdPrefix(hierarchyIdPrefix)
    }

    /// Whether the run itself is on screen — playing, parked somewhere in the
    /// track by the editor, or holding the frame a finished pass ended on.
    /// Anything else draws where the animation starts.
    var isShowingTrack: Bool {
        trackTime != nil
    }

    /// Where in the track this actionable is drawn, or nil when it is not drawn
    /// from its track at all — see `InertiaDataModel.trackTime(for:)`, which is
    /// where the question is actually answered.
    var trackTime: CGFloat? {
        inertiaDataModel?.trackTime(for: hierarchyIdPrefix)
    }

    /// What to show right now: where the run has got to, or — with no run on
    /// screen — the values the animation starts from.
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
    ///
    /// An animation that is not running is not the same as no animation at all:
    /// an actionable waiting on its trigger sits where its schema says it
    /// starts. This used to draw nothing there, leaving the node at its layout
    /// position, so initial values only ever appeared once something played —
    /// the React and Compose runtimes have always drawn them.
    func displayValues(for animation: InertiaAnimationSchema) -> InertiaAnimationValues {
        // A parked playhead holds there, a running one advances, and a finished
        // pass stays on the frame it ended on. Same read.
        guard let time = trackTime else {
            return animation.initialValues.sanitized
        }

        return timeline(for: animation).value(time: time).sanitized
    }

    /// Where a shape's own track has got to.
    ///
    /// Read at the same playhead as everything else, so a shape moves in time
    /// with the actionable it was authored behind rather than on a clock of its
    /// own — and is padded to the same loop, so the two come round together.
    ///
    /// What it does not share is the actionable's `invokeType`: a shape
    /// animation marked `auto` runs as soon as the container's clock does, even
    /// while the actionable it backs is still waiting on the app to trigger it.
    /// A shape given a `trigger` animation waits for the actionable, which is
    /// the only trigger a shape can be reached by — and is held with it when its
    /// pass ends, since the frame the actionable is holding is the one the shape
    /// was drawn on.
    func shapeDisplayValues(for animation: InertiaAnimationSchema) -> InertiaAnimationValues {
        guard let inertiaDataModel else { return animation.initialValues.sanitized }

        let isPlaying = inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil
        let playheadTime = inertiaDataModel.seekTime ?? inertiaDataModel.playheadTime
        let time = trackTime ?? (animation.invokeType == .auto && isPlaying ? playheadTime : nil)

        guard let time else { return animation.initialValues.sanitized }

        return timeline(for: animation).value(time: time).sanitized
    }

    /// Whether a shape is drawn at all right now — see
    /// `InertiaShape.showsBeforeAnimation`.
    ///
    /// "Playing" is the same run being on screen that `shapeDisplayValues` reads
    /// the track for, and for the same reason: a shape that appears with the
    /// animation has to appear on the frame the animation starts drawing from,
    /// not one frame either side of it.
    func isShowing(_ shape: InertiaShape) -> Bool {
        guard !shape.showsBeforeAnimation else { return true }
        guard let inertiaDataModel else { return false }

        let isPlaying = inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil
        return isShowingTrack || (shape.animation?.invokeType == .auto && isPlaying)
    }

    var body: some View {
        //        GeometryReader { rootProxy in
        Group {
            if let animation = animation ?? getAnimation {
                let values = displayValues(for: animation)

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

        // One level out from every rendering effect above, so what the shapes
        // are projected from is where this view was laid out — not where the
        // animation has currently drawn it.
        .measuringLayoutFrame(in: inertiaContainerId) { frame in
            layoutFrame = frame
            reportMeasurement(frame.size)
        }
        .environment(\.inertiaParentID, hierarchyId)
        .environment(\.isInertiaContainer, false)
        .buttonStyle(.plain)
        .onAppear {
            manager.messageReceivedSignal = handleMessageSignal
        }
        // A navigation is the container's to notice — see
        // `InertiaContainer.body`. Watched from here, it restarted once per
        // actionable the navigation happened to keep mounted, and not at all for
        // one it tore down.
        .task {
            updateHierarchyId()
            // The id is what a measurement is filed under, and it is only known
            // once this runs — so a box measured before then is reported here
            // instead of being dropped.
            reportMeasurement(layoutFrame.size)
        }
        .onDisappear {
            // Cleanup disabled for new schema - no shape objects with zIndex
        }


    }

    /// Tells the editor how big this actionable was laid out, so a shape
    /// authored against it can be drawn to size somewhere the app itself is not
    /// — see `InertiaMessage.MessageNodeMeasured`.
    ///
    /// The size rather than the whole frame: a shape is a multiple of the box,
    /// not of where the box sits, so a view scrolled across its container
    /// changes nothing about the drawing while reporting a new frame the whole
    /// way. Sent only when the size actually changes, for the same reason.
    private func reportMeasurement(_ size: CGSize) {
        guard let hierarchyId, size.width > 0, size.height > 0, size != reportedSize else { return }

        reportedSize = size
        manager.sendMessage(
            InertiaMessage.MessageNodeMeasured(
                hierarchyIdPrefix: hierarchyIdPrefix,
                hierarchyId: hierarchyId,
                sizeX: size.width,
                sizeY: size.height
            )
        )
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
        case .trigger(let id):
            // The app's own entry point, reached by the editor's Trigger action
            // standing in for the app — a `trigger` animation starts the one way
            // whoever is watching it in the editor is authoring it to start.
            inertiaDataModel?.trigger(id)
        }
    }
    
    /// The schema behind this actionable, whatever it is currently doing.
    ///
    /// Free of playback state, like `inertiaSchema` itself: what an actionable
    /// *has* is not what it is doing. Whether the run is on screen is
    /// `isShowingTrack`'s to say, and an actionable that is not playing still
    /// draws — at the values its animation starts from.
    var getAnimation: InertiaAnimationSchema? {
        guard let inertiaDataModel else {
            InertiaLog.debug("inertiaDataModel is nil")
            return nil
        }

        guard let hierarchyId else {
            InertiaLog.debug("hierarchyId is nil")
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

    /// The next index to hand a view of this prefix in this container, and the
    /// counter moved along.
    ///
    /// Counted per container rather than per prefix alone: the index is what
    /// tells two instances of the same authored view apart, and two containers
    /// each holding one instance are not two instances. Sharing one counter had
    /// the second container's node come up as `card0--1` with no `card0--0`
    /// beside it, so a selection authored against the first container named
    /// nothing the second one drew.
    func claimIndex(containerId: String?, prefix: String) -> Int {
        let key = "\(containerId ?? "")\u{1}\(prefix)"
        let index = indexMap[key] ?? .zero
        indexMap[key] = index + 1
        return index
    }
}

private extension View {
    /// Keeps this node answering to the pointer even when an actionable above it
    /// has disabled everything under itself.
    ///
    /// An actionable disables its content while the editor is picking things —
    /// see `InertiaEditable.wrappedContent` — and `disabled` is inherited: an
    /// actionable *inside* another one is part of that content, so its own tap,
    /// its drag and its tool handles all went dead. The press then fell through
    /// to the nearest ancestor still listening, which is the outer actionable —
    /// so a nested node could only ever select and move the thing it sits in.
    ///
    /// `disabled(false)` cannot undo it: nested calls combine, and the most
    /// disabling one wins. Writing the environment value outright is the one
    /// thing that does, and it reaches exactly as far as the next `disabled`
    /// below it — which is this node's own, over its own content. So the node's
    /// chrome comes back while the app's controls inside it stay inert.
    ///
    /// Only while the editor is picking, because that is the only time anything
    /// was disabled on its account. Left on, this would also override a
    /// `disabled` the *app* put around a node for its own reasons.
    ///
    /// This is what the React runtime gets from `pointer-events`, where a nested
    /// node's `auto` beats the `none` its parent put on its content — see
    /// `InertiaGuts` in `inertia-react`.
    func interactiveWhileEditing(_ isEditing: Bool) -> some View {
        // `transformEnvironment` rather than a branch around `environment`: a
        // node whose modifiers change shape when the editor attaches is a
        // different view to SwiftUI, which throws away the state underneath it —
        // the id it was indexed under included.
        transformEnvironment(\.isEnabled) { isEnabled in
            if isEditing { isEnabled = true }
        }
    }

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
    @State private var animation: InertiaAnimationSchema? = nil
    @State private var contentSize: CGSize = .zero
    @State private var vm = InertiaViewModel()
    @State private var hierarchyId: String? = nil
    /// What the gesture in progress has changed so far. Replaced on every move,
    /// so a tool only ever contributes the one property it edits.
    @State private var gestureEdit: InertiaToolEdit = .none
    /// What the gestures before this one left behind, still waiting for the
    /// editor to fold them into the schema. `DragGesture` reports movement
    /// relative to its own start, so without carrying this every gesture after
    /// the first would snap the node back to where its schema puts it.
    @State private var settledEdit: InertiaToolEdit = .none
    /// This node's box in the container's space, as laid out — measured outside
    /// both the animation and the editor's gestures. The shapes are projected
    /// from it, the guides are boxed to it, and the handles turn about it.
    @State private var layoutFrame: CGRect = .zero
    /// The size the editor has already been told about, so layout reporting the
    /// same box again does not put another message on the wire.
    @State private var reportedSize: CGSize? = nil
    /// The same two edits, per shape drawn behind this node, keyed by shape id.
    ///
    /// Held here rather than in the canvas because the canvas is rebuilt from
    /// the schema on every change, which would throw a gesture away halfway
    /// through it. A shape gets its own entries so that dragging one leaves the
    /// node it is drawn behind — and every other shape on it — where they were.
    @State private var shapeGestureEdits: [InertiaID: InertiaToolEdit] = [:]
    @State private var shapeSettledEdits: [InertiaID: InertiaToolEdit] = [:]

    /// Everything the editor's gestures have added on top of the schema:
    /// what previous ones settled at, plus what this one has done so far.
    private var totalEdit: InertiaToolEdit {
        settledEdit + gestureEdit
    }

    /// The edit actually on screen. Held back unless this node is the one being
    /// edited, for the same reason the drag used to be: an edit is a gesture,
    /// not a position — what an actionable *is* at rests in its schema. Applied
    /// unconditionally, a node deselected before the editor had pushed the
    /// gesture back stayed stuck where it had been left, with nothing on screen
    /// agreeing that it belonged there.
    private var liveEdit: InertiaToolEdit {
        isEditable ? totalEdit : .none
    }

    /// The values the node is drawn at right now: whatever the schema shows —
    /// its starting values, or where the run has got to — with the gesture in
    /// progress folded in.
    private var displayedValues: InertiaAnimationValues {
        let base = (animation ?? getAnimation).map { displayValues(for: $0) } ?? .identity
        return base.applying(liveEdit, containerSize: inertiaContainerSize)
    }

    /// What the editor is told once a gesture ends.
    ///
    /// Measured from the schema's *starting* values rather than from wherever
    /// playback has the node at: a keyframe recorded from a scrubbed position
    /// would otherwise bake the track's own interpolation into itself. It has to
    /// carry those starting values, too — an edit sent as the gesture alone is
    /// written back over the transform it was measured from rather than added to
    /// it, so a node with an initial offset jumped back by it the moment the new
    /// schema landed.
    private var authoredValues: InertiaAnimationValues {
        (initialValues ?? .identity).sanitized
            .applying(totalEdit, containerSize: inertiaContainerSize)
    }

    /// Where the node's center currently sits in the container: its layout
    /// position moved by everything on screen.
    private var currentCenter: CGPoint {
        displayedValues.drawnPoint(
            CGPoint(x: layoutFrame.width / 2, y: layoutFrame.height / 2),
            in: layoutFrame,
            containerSize: inertiaContainerSize
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
        return inertiaDataModel?.actionableIdPairs(in: inertiaContainerId).contains(where: { $0.hierarchyId == hierarchyId }) ?? false
    }

    var showSelectedBorder: Bool {
        InertiaLog.verbose("\(String(describing: hierarchyId)) \(hierarchyIdPrefix)")
        return isSelected
    }

    /// Only a selected node takes an editor gesture. Editing acts on the
    /// selection, and a committed edit is attributed to *all* selected pairs —
    /// so letting an unselected node be dragged both changes something the user
    /// never picked and attributes the change to the wrong nodes.
    private var isEditable: Bool {
        (inertiaDataModel?.isActionable ?? false) && isSelected
    }

    /// Which tool the editor has the viewport in.
    private var activeTool: InertiaTool {
        inertiaDataModel?.activeTool ?? .translate
    }

    /// The whole node is the handle for the move tool, and only for it. Every
    /// other tool edits through the chrome in `toolHandles`, so a drag across
    /// the body of a node does nothing — the same way a modal tool behaves in
    /// any other editor.
    ///
    /// The move tool's own chrome — its two axis arrows — is driven by this same
    /// gesture rather than by a handle of its own, so this covers a press on one
    /// of those too. See `InertiaTranslateAxes`.
    private var isBodyDraggable: Bool {
        isEditable && activeTool == .translate
    }

    /// The arrow that has the press, while one does.
    ///
    /// Set on touch-down by the arrow's own drag, which opens immediately —
    /// before this one's 10 points of travel have been covered — so the free
    /// move can stand down rather than move the node a second time.
    @State private var axisDrag: InertiaTranslateAxis? = nil

    /// A free move: the node follows the pointer in both axes.
    ///
    /// Measured globally rather than in the node's own space, which the gesture
    /// is itself dragging out from under the pointer — a translation taken there
    /// counts only the part of the move the node has not caught up with yet, and
    /// the node trails the cursor. Globally rather than in the container's
    /// *named* space because a name only resolves while nothing between here and
    /// the container hosts its children separately; a `TabView` does, and the
    /// fallback is silent. Neither frame moves, so for a translation the two are
    /// the same measurement — one of them just always works.
    ///
    /// Pinning to one axis is not decided here. It used to be — the press was
    /// measured against where the arrows were drawn, which needed the press
    /// location, the node's drawn center and its layout frame to agree on a
    /// coordinate space. A drag reports the same translation in any space, so
    /// once that agreement broke this went on working perfectly while both axis
    /// pins quietly died. The arrows now say which of them was pressed instead —
    /// see `InertiaToolHandles.onAxisTranslate`, which needs no space at all.
    var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                // An arrow already has this press and is pinning it — see
                // `axisDrag`. Both of them authoring the same drag moved the
                // node twice as far as the pointer went.
                guard axisDrag == nil, isBodyDraggable else { return }
                apply(InertiaToolEdit(translate: value.translation))
            }
            .onEnded { value in
                guard axisDrag == nil, isBodyDraggable else { return }
                apply(InertiaToolEdit(translate: value.translation))
                commitEdit()
            }
    }

    /// Tells the editor how big this node was laid out, so a shape authored
    /// against it can be drawn to size in a window that has no copy of the app
    /// to measure — see `InertiaMessage.MessageNodeMeasured`.
    ///
    /// The size rather than the whole frame: a shape is a multiple of the box,
    /// not of where the box sits, so a node scrolled across its container
    /// changes nothing about the drawing while reporting a new frame the whole
    /// way. Sent only when the size actually changes, for the same reason.
    ///
    /// Unlike `MessageSelectedNodeProperties`, this is not about a gesture: it
    /// is sent by every node that lays out, selected or not, dragged or not.
    private func reportMeasurement(_ size: CGSize) {
        guard let hierarchyId, size.width > 0, size.height > 0, size != reportedSize else { return }

        reportedSize = size
        manager.sendMessage(
            InertiaMessage.MessageNodeMeasured(
                hierarchyIdPrefix: hierarchyIdPrefix,
                hierarchyId: hierarchyId,
                sizeX: size.width,
                sizeY: size.height
            )
        )
    }

    /// Shows what a gesture has produced so far, and reports it to the editor's
    /// inspector. Nothing is authored yet — see `commitEdit`.
    private func apply(_ edit: InertiaToolEdit) {
        gestureEdit = edit

        // The guides box a node in as it is moved. They mean nothing for a
        // rotation or an opacity, where the node stays where layout put it.
        let isMoving = activeTool == .translate
        inertiaDataModel?.showGrid = isMoving
        if isMoving {
            // The box the node is *drawn* in, not the one it was laid out in:
            // scale is about the center, so an actionable its schema scales up
            // keeps its center and grows around it.
            let scale = displayedValues.scale
            inertiaDataModel?.selectedNodeCenter = currentCenter
            inertiaDataModel?.selectedNodeSize = CGSize(
                width: layoutFrame.width * scale,
                height: layoutFrame.height * scale
            )
        }

        let authored = authoredValues
        manager.sendMessage(
            InertiaMessage.MessageSelectedNodeProperties(
                positionX: authored.translate.width * inertiaContainerSize.width,
                positionY: authored.translate.height * inertiaContainerSize.height,
                sizeX: layoutFrame.width,
                sizeY: layoutFrame.height,
                values: authored
            )
        )
    }

    /// Ends a gesture: folds it into what the node is showing so the next one
    /// starts from where this one left it, and hands the result to the editor to
    /// be written into the schema.
    ///
    /// One `MessageEdit` whatever the tool, carrying the whole transform: a
    /// keyframe holds all five values, so the four this gesture did not touch
    /// have to travel with the one it did.
    private func commitEdit() {
        let authored = authoredValues
        settledEdit = .none
        gestureEdit = .none
        inertiaDataModel?.showGrid = false

        guard let actionableIdPairs = inertiaDataModel?.actionableIdPairs(in: inertiaContainerId) else { return }

        manager.sendMessage(
            InertiaMessage.MessageEdit(
                tool: activeTool,
                values: authored,
                actionableIds: actionableIdPairs
            )
        )
    }

    /// Whether the editor has picked this shape, by its own id — the same
    /// selection the actionables are picked out of, since a shape is selected
    /// as an `ActionableIdPair` like anything else.
    private func isSelected(shape: InertiaShape) -> Bool {
        inertiaDataModel?.actionableIdPairs(in: inertiaContainerId).contains { $0.hierarchyId == shape.id } ?? false
    }

    /// Everything a shape drawn behind this node needs in order to be picked and
    /// dragged, or nil when nothing here is selectable.
    ///
    /// The shapes sit inside this node's own transform, so they are handed it as
    /// their outer one — see `InertiaToolHandles.outer`.
    private var shapeEditing: InertiaShapeEditing? {
        guard inertiaDataModel?.isActionable ?? false else { return nil }

        return InertiaShapeEditing(
            isSelected: { isSelected(shape: $0) },
            tool: activeTool,
            containerSpace: inertiaContainerId,
            outer: InertiaOuterTransform(values: displayedValues, layoutFrame: layoutFrame),
            edit: { shape in
                (shapeSettledEdits[shape.id] ?? .none) + (shapeGestureEdits[shape.id] ?? .none)
            },
            onChange: { shape, edit in
                shapeGestureEdits[shape.id] = edit
            },
            onEnded: { shape in commitShapeEdit(shape) },
            onPlaced: { shape, values in commitShapePlacement(shape, values: values) },
            onTap: { shape in toggleSelection(of: shape) }
        )
    }

    /// Picks a shape up, or puts it down again: the toggle a press on the
    /// artwork runs, which is the same one a tap on an actionable's body runs
    /// and writes to the same selection.
    ///
    /// A shape travels as an `ActionableIdPair` like anything else — its own id
    /// under the schema that carries it, which is how the editor's hierarchy
    /// names it too, so picking a shape out here lights up the same row.
    ///
    /// The whole selection goes back on the wire rather than the one shape that
    /// changed, because that is what a `MessageActionables` says: not what was
    /// picked, but what *is* picked.
    private func toggleSelection(of shape: InertiaShape) {
        guard let inertiaDataModel, inertiaDataModel.isActionable else { return }
        guard let containerId = inertiaContainerId else { return }

        let pair = ActionableIdPair(hierarchyIdPrefix: hierarchyIdPrefix, hierarchyId: shape.id)
        inertiaDataModel.toggleActionableIdPair(pair, in: containerId)

        sendActionables()
    }

    /// Tells the editor what this node's container is showing and what is picked
    /// in it.
    ///
    /// The container's own tree and its own selection, never the app's: the two
    /// halves of a `MessageActionables` are read together, and the editor files
    /// what it is told under the tree that came with it.
    private func sendActionables() {
        guard let inertiaDataModel,
              let containerId = inertiaContainerId,
              let tree = inertiaDataModel.tree(reading: containerId)
        else { return }

        manager.sendMessage(
            InertiaMessage.MessageActionables(
                tree: tree,
                actionableIds: inertiaDataModel.actionableIdPairs(in: containerId)
            )
        )
    }

    /// Ends a gesture on a shape: folds it in so the next one starts from where
    /// this one left it, and hands the result to the editor.
    ///
    /// The same `MessageEdit` an actionable sends, naming the shape's own id
    /// under the schema that carries it — which is exactly how it was selected.
    /// Measured from the shape's authored starting values rather than from
    /// wherever its track has it, for the reason `authoredValues` gives.
    private func commitShapeEdit(_ shape: InertiaShape) {
        let settled = (shapeSettledEdits[shape.id] ?? .none) + (shapeGestureEdits[shape.id] ?? .none)
        shapeSettledEdits[shape.id] = settled
        shapeGestureEdits[shape.id] = nil

        let authored = (shape.animation?.initialValues ?? .identity).sanitized
            .applying(settled, containerSize: inertiaContainerSize)

        manager.sendMessage(
            InertiaMessage.MessageEdit(
                tool: activeTool,
                values: authored,
                actionableIds: [
                    ActionableIdPair(hierarchyIdPrefix: hierarchyIdPrefix, hierarchyId: shape.id)
                ]
            )
        )
    }

    /// Ends a gesture on a nested vector: folds it in so the next one starts
    /// from where this one left it, and hands the editor where the shape now
    /// sits in its parent.
    ///
    /// A placement rather than a take. A nested shape is drawn into its parent's
    /// vertex buffer — it has no canvas of its own to move and no track the
    /// runtime would ever read off it — so where it sits is the only thing a
    /// gesture on it can author, whether or not the editor is recording. That is
    /// the same thing the editor's own canvas writes with its transform toolset;
    /// see `EditorViewModel.applyShapeTransforms(_:)`.
    ///
    /// The values are worked out by the canvas that drew the handles, which is
    /// the one place that knows what a point of screen is worth to the box this
    /// shape is placed in — see `InertiaShapesView.placementUnit(of:)`. What goes
    /// on the wire is the same `MessageEdit` a top-level shape sends, naming the
    /// shape's own id: which of the two it is gets read off the shape at the
    /// other end, see `KeyframeHandler.recordShape`.
    private func commitShapePlacement(_ shape: InertiaShape, values: InertiaAnimationValues) {
        shapeSettledEdits[shape.id] = (shapeSettledEdits[shape.id] ?? .none) + (shapeGestureEdits[shape.id] ?? .none)
        shapeGestureEdits[shape.id] = nil

        manager.sendMessage(
            InertiaMessage.MessageEdit(
                tool: activeTool,
                values: values,
                actionableIds: [
                    ActionableIdPair(hierarchyIdPrefix: hierarchyIdPrefix, hierarchyId: shape.id)
                ]
            )
        )
    }

    /// The chrome for the active tool, drawn over a selected node.
    @ViewBuilder
    private var toolHandles: some View {
        if isEditable {
            InertiaToolHandles(
                tool: activeTool,
                values: displayedValues,
                layoutFrame: layoutFrame,
                containerSize: inertiaContainerSize,
                containerSpace: inertiaContainerId,
                onChange: { apply($0) },
                onEnded: { axisDrag = nil; commitEdit() },
                // The arrows report which of them was pressed rather than being
                // measured against a press location — see
                // `InertiaToolHandles.onAxisTranslate`. A node sits wherever the
                // app under test put it, which may be inside a `TabView` or any
                // other host that breaks the container's named coordinate space;
                // an arrow that names itself does not care.
                onAxisTranslate: { axis, translation in
                    axisDrag = axis
                    apply(InertiaToolEdit(translate: axis.constrain(translation)))
                }
            )
        }
    }

    var wrappedContent: some View {
        ZStack(alignment: .center) {
            content
                // The app's own controls go inert while the editor is picking
                // things, so a press on a node selects it instead of pressing
                // the button that happens to be under it. Everything nested
                // inside this node — including another actionable — goes inert
                // with it, which is what `interactiveWhileEditing` undoes for
                // the one below.
                .disabled(inertiaDataModel?.isActionable ?? false)
        }
        // Behind the content and inside everything that moves it — the drag
        // below as well as the animation in `body` — so the shapes stay with
        // the node they belong to, and over it for the shapes authored to sit
        // there. See `InertiaActionable.wrappedContent`.
        .background(alignment: .center) { containerCanvas }
        .overlay(alignment: .center) { containerOverlayCanvas }
        // What `onChange(of: initialValues)` does for the node, for the shapes:
        // the canvases already draw where the schema says they start, so an edit
        // still stacked on top of that would count the gesture the editor has
        // just written back a second time.
        //
        // On the content rather than on either canvas, so it still fires for an
        // actionable whose shapes are all on the other side of it.
        .onChange(of: shapes) { _, _ in
            shapeSettledEdits = [:]
            shapeGestureEdits = [:]
        }
        .onTapGesture { toggleSelection() }
        .overlay {
            if showSelectedBorder && inertiaDataModel?.isActionable ?? false {
                // `strokeBorder` rather than `stroke`: a stroke centers the line
                // on the edge, so half of it hangs outside the node's bounds and
                // over its neighbours. Inset, the way the Compose runtime's
                // `Modifier.border` draws it.
                Rectangle()
                    .strokeBorder(Color.green, lineWidth: 2)
            }
        }
        // Inside everything that transforms the node, so the handles stay glued
        // to it as it turns and scales, and above the selection border so a knob
        // sitting on the edge is the thing that gets grabbed.
        .overlay { toolHandles }
        // Masked off rather than merely inert when this node isn't being moved:
        // an attached DragGesture claims the drag even when its handlers do
        // nothing, which would stop a selected ancestor from being dragged, and
        // would swallow the drags meant for this node's own tool handles. The
        // tap that selects lives on the subviews, so `.subviews` keeps it live.
        .gesture(dragGesture, including: isBodyDraggable ? .all : .subviews)
    }

    /// Picks this node up, or puts it down again — the same toggle a press on a
    /// shape runs, on the same selection.
    private func toggleSelection() {
        InertiaLog.debug("tapped \(content)")
        guard let inertiaDataModel, inertiaDataModel.isActionable else { return }
        guard let hierarchyId, let containerId = inertiaContainerId else { return }

        let pair = ActionableIdPair(hierarchyIdPrefix: hierarchyIdPrefix, hierarchyId: hierarchyId)
        inertiaDataModel.toggleActionableIdPair(pair, in: containerId)

        InertiaLog.info("Tapped: Starting to send data...")
        sendActionables()
    }
    
    /// The shapes authored against this actionable, if it has any. Read off the
    /// schema rather than the running animation, so the editor shows the
    /// backdrop while the timeline is parked as well as while it plays.
    private var shapes: [InertiaShape] {
        inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel)?.shapes ?? []
    }

    /// The values the schema starts this actionable from. Watched rather than
    /// read: `displayValues` is what draws them, and the drag stacked on top has
    /// to get out of their way whenever they change.
    private var initialValues: InertiaAnimationValues? {
        inertiaSchema(hierarchyId: hierarchyId, hierarchyIdPrefix: hierarchyIdPrefix, in: inertiaDataModel)?.initialValues
    }

    /// The same canvases the shipped runtime draws on one side of an actionable
    /// — including a shape's own animation moving it — so what is authored here
    /// is what the app renders. See `InertiaActionable.canvasView(for:at:)`.
    @ViewBuilder
    private func canvasView(for size: CGSize, at position: InertiaShapePosition) -> some View {
        let shapes = self.shapes.filter { $0.position == position && isShowing($0) }
        if !shapes.isEmpty {
            InertiaShapesView(
                vm: vm,
                shapes: shapes,
                size: size,
                containerSize: inertiaContainerSize,
                values: shapeDisplayValues(for:),
                editing: shapeEditing
            )
        }
    }

    /// The canvas fitted to the shapes' own box. Sized and anchored exactly as
    /// the shipped runtime does it — see `InertiaActionable.containerCanvas`,
    /// which also has the reason both of them measure from a measured layout
    /// frame instead of a `GeometryReader` in here — so a shape sits where the
    /// editor shows it sitting.
    @ViewBuilder
    private var containerCanvas: some View {
        canvasView(for: layoutFrame.size, at: .bottom)
    }

    /// The same canvas over the content, for the shapes authored to sit there.
    @ViewBuilder
    private var containerOverlayCanvas: some View {
        canvasView(for: layoutFrame.size, at: .top)
    }

    /// The track as a timeline that can be evaluated at any point in it, which
    /// is what scrubbing needs and `keyframeAnimator` — a play button with no
    /// seek bar — cannot give.
    ///
    /// Held out to the full loop when repeating, so the animation and the
    /// editor's playhead share one period. Built by the schema itself, so the
    /// editor's canvas — which has no data model to ask — pads and samples the
    /// same track this does.
    func timeline(for animation: InertiaAnimationSchema) -> KeyframeTimeline<InertiaAnimationValues> {
        let isRepeating = inertiaDataModel?.isRepeating ?? true
        let loop = inertiaDataModel?.playbackDuration ?? InertiaPlayback.defaultLoopDuration

        return animation.timeline(filling: isRepeating ? loop : nil)
    }

    /// Whether the run itself is on screen — playing, parked somewhere in the
    /// track by the editor, or holding the frame a finished pass ended on.
    /// Anything else draws where the animation starts.
    var isShowingTrack: Bool {
        trackTime != nil
    }

    /// Where in the track this node is drawn, or nil when it is not drawn from
    /// its track at all — see `InertiaDataModel.trackTime(for:)`.
    var trackTime: CGFloat? {
        inertiaDataModel?.trackTime(for: hierarchyIdPrefix)
    }

    /// What to show right now: where the run has got to, or — with no run on
    /// screen — the values the animation starts from. See
    /// `InertiaActionable.displayValues`, which this deliberately mirrors.
    ///
    /// The editor's copy of an animation is drawn from the runtime's own clock
    /// rather than handed to a `keyframeAnimator`, so playing, pausing and
    /// scrubbing are all the same thing: read the track at the playhead. It is
    /// also the only way play can pick up mid-loop — an animator can only ever
    /// start a track at its beginning.
    func displayValues(for animation: InertiaAnimationSchema) -> InertiaAnimationValues {
        guard let time = trackTime else {
            return animation.initialValues.sanitized
        }

        return timeline(for: animation).value(time: time).sanitized
    }

    /// Where a shape's own track has got to, drawn from the same playhead as
    /// the actionable it backs. See `InertiaActionable.shapeDisplayValues`,
    /// which this deliberately mirrors — a shape being authored has to move in
    /// the editor exactly as it will in the app.
    func shapeDisplayValues(for animation: InertiaAnimationSchema) -> InertiaAnimationValues {
        guard let inertiaDataModel else { return animation.initialValues.sanitized }

        let isPlaying = inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil
        let playheadTime = inertiaDataModel.seekTime ?? inertiaDataModel.playheadTime
        let time = trackTime ?? (animation.invokeType == .auto && isPlaying ? playheadTime : nil)

        guard let time else { return animation.initialValues.sanitized }

        return timeline(for: animation).value(time: time).sanitized
    }

    /// Whether a shape is drawn at all right now — see
    /// `InertiaActionable.isShowing(_:)`, which this mirrors.
    ///
    /// With one exception the shipped runtime has no use for: the shape being
    /// worked on stays drawn whatever it says. Selection happens in the editor's
    /// hierarchy, but everything done to a shape after that is done to the thing
    /// on screen — dragged by its own box, sized by its handles — and a shape
    /// that vanished until the timeline was rolling could not be authored at
    /// all. The green border is already the sign that this one is being shown
    /// for the editor's sake.
    func isShowing(_ shape: InertiaShape) -> Bool {
        guard !shape.showsBeforeAnimation else { return true }
        guard let inertiaDataModel else { return false }
        guard !(inertiaDataModel.isActionable && isSelected(shape: shape)) else { return true }

        let isPlaying = inertiaDataModel.isRunning || inertiaDataModel.seekTime != nil
        return isShowingTrack || (shape.animation?.invokeType == .auto && isPlaying)
    }

    /// Names this node, once — see `InertiaActionable.updateHierarchyId`, which
    /// this is the editing half of and which has the reason.
    ///
    /// It matters more here than there: this runs from `.onAppear`, which a
    /// `TabView` fires again on every switch back to a tab, and it is the
    /// editor that is left holding the stale name.
    @MainActor
    func updateHierarchyId() {
        guard hierarchyId == nil else { return }

        let index = indexManager?.claimIndex(containerId: inertiaContainerId, prefix: hierarchyIdPrefix) ?? .zero
        hierarchyId = "\(hierarchyIdPrefix)--\(index)"
        // Register this prefix with the data model
        inertiaDataModel?.registerHierarchyIdPrefix(hierarchyIdPrefix)
    }


    var body: some View {
        Group {
            // One stack for the schema and the gesture together, rather than the
            // gesture applied somewhere inside the animation's own modifiers:
            // what the editor is sent is a single set of values, and this is what
            // makes the node's appearance agree with them.
            //
            // Unconditional, and the identity transform when there is neither an
            // animation nor a gesture. A node that grew its modifiers only once
            // it had something to show was a *different* view to SwiftUI the
            // moment it did, which threw away the state underneath it —
            // including the id it had been indexed under — mid-gesture.
            let values = displayedValues
            // Worked out ahead of the chain rather than inside it: the type
            // checker charges these two multiplications against the whole body,
            // which is long enough already.
            let offset = CGSize(
                width: values.translate.width * inertiaContainerSize.width,
                height: values.translate.height * inertiaContainerSize.height
            )

            wrappedContent
                .scaleEffect(values.scale)
                .rotationEffect(Angle(degrees: values.rotate), anchor: .topLeading)
                .rotationEffect(Angle(degrees: values.rotateCenter), anchor: .center)
                .offset(x: offset.width, y: offset.height)
                .opacity(values.opacity)
        }

        // The animation above already puts this node where the schema says it
        // starts, so the edit stacked on top of it goes back to zero whenever
        // those values change: by then the gesture has been authored into the
        // schema, and leaving it in place would count the same move twice. It is
        // also what returns a node to the origin when the editor resets an
        // animation's initial values — until this, a reset changed the authored
        // animation and left the node sitting wherever it had been dragged to.
        //
        // Matches `LaunchedEffect(animation?.initialValues)` in the Compose
        // runtime and the `pos` effect in the React one.
        .onChange(of: initialValues) { _, _ in
            settledEdit = .none
            gestureEdit = .none
        }


        // Outside the animation and outside the editor's gestures, so the shapes
        // are projected from where this node was laid out rather than from
        // wherever it has been drawn or dragged to, the guides box the node
        // itself, and the handles turn about a fixed frame. All of those
        // transforms then move the result as rendering effects, which is what
        // keeps the canvas and the chrome stuck to the node.
        .measuringLayoutFrame(in: inertiaContainerId) { frame in
            layoutFrame = frame
            reportMeasurement(frame.size)
        }
        // Outside everything this node listens with — its tap, its drag and its
        // tool handles — and outside the `disabled` it puts on its own content,
        // so an actionable nested in another one is picked and moved on its own
        // account rather than passing the press up to the one it sits in.
        .interactiveWhileEditing(inertiaDataModel?.isActionable ?? false)
        .environment(\.inertiaParentID, hierarchyId)
        .environment(\.isInertiaContainer, false)
        .buttonStyle(.plain)
        .onAppear {
            updateHierarchyId()
            // The id is what a measurement is filed under, and a box measured
            // before this ran had none to be filed under.
            reportMeasurement(layoutFrame.size)

            InertiaLog.info("Connecting to the editor (setup)...")
            manager.start()

            manager.messageReceived = handleMessage(tree:selectedIds:)
            manager.messageReceivedSchema = handleMessageSchema
            manager.messageReceivedIsActionable = handleMessageActionable
            manager.messageReceivedTool = handleMessageTool(tool:)
            manager.messageReceivedSignal = handleMessageSignal(_:sequence:)
        }
        .onChange(of: manager.isConnected, { oldValue, newValue in
            // An editor just attached — push the current hierarchy so it can
            // render the tree without waiting for the next change.
            guard newValue else {
                return
            }

            InertiaLog.info("Editor attached, sending current tree...")
            sendActionables()

            // Layout happened long before this editor was listening, and it
            // will not happen again just because one attached. Forgetting what
            // was already sent is what makes the measurement go out again.
            reportedSize = nil
            reportMeasurement(layoutFrame.size)
        })
        // Registered whenever the id lands rather than only on the first one it
        // ever had. It used to bail out on any later change, which was only ever
        // right because the id never legitimately changed — and when a stale
        // `updateHierarchyId` renamed the node anyway, this is what quietly left
        // the tree describing a name nothing answered to.
        .onChange(of: hierarchyId) { _, hierarchyId in
            guard let hierarchyId, let containerId = inertiaContainerId else {
                return
            }

            InertiaLog.debug("adding relationship: hierarchyId: \(hierarchyId) inertiaParentID: \(String(describing: inertiaParentID)), isInertiaContainer: \(isInertiaContainer)")

            // Into this container's own hierarchy — see `InertiaDataModel.trees`.
            let tree = inertiaDataModel?.tree(for: containerId)
            tree?.addRelationship(id: hierarchyId, parentId: inertiaParentID, parentIsContainer: isInertiaContainer)
            if let tree {
                for node in tree.nodeMap.values {
                    node.tree = tree
                    node.link()
                }
            }

            InertiaLog.debug("Starting to send data 2...")
            manager.start()

            sendActionables()
        }
        .onDisappear {
            // Cleanup disabled for new schema - no shape objects with zIndex
        }
    }

    /// Free of playback state, the same as `InertiaActionable.getAnimation` —
    /// what an actionable *has* is not what it is doing, and whether the run is
    /// on screen is `isShowingTrack`'s to say.
    ///
    /// This used to hold out for a triggered animation, which threw away the one
    /// thing an untriggered node still has to show: the values its animation
    /// starts from. An edit is written into exactly those values and handed
    /// straight back, so a node dragged before anything had played snapped back
    /// to where it was laid out the moment the new schema landed and its gesture
    /// was folded in — and stayed there until the first play triggered it, at
    /// which point every edit made until then appeared at once.
    var getAnimation: InertiaAnimationSchema? {
        guard let inertiaDataModel else {
            InertiaLog.debug("inertiaDataModel is nil")
            return nil
        }

        guard let hierarchyId else {
            InertiaLog.debug("hierarchyId is nil")
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
    
    /// What the editor says is picked, in the hierarchy it says it about.
    ///
    /// Filed under the tree that came with it rather than over the whole app:
    /// the editor draws one panel per hierarchy and writes a selection back
    /// through the packet it was made in, so a message names one container. Laid
    /// over everything, picking a row in one container silently cleared what was
    /// picked in every other.
    func handleMessage(tree: Tree, selectedIds: Set<ActionableIdPair>) {
        InertiaLog.debug("✅ Updating actionableIdPairs for \(tree.id) from WS: \(selectedIds)")
        inertiaDataModel?.setActionableIdPairs(selectedIds, in: tree.id)
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
        case .trigger(let id):
            // The app's own entry point, reached by the editor's Trigger action
            // standing in for the app — a `trigger` animation starts the one way
            // whoever is watching it in the editor is authoring it to start.
            inertiaDataModel?.trigger(id)
        }
    }

    /// Takes the whole project from the editor, replacing whatever this runtime
    /// was holding for this container.
    ///
    /// Replaced rather than merged in: the editor sends every animation it has
    /// on every edit, so the message is a statement of what the project *is*,
    /// not of what changed in it. Merged in, an animation deleted in the editor
    /// had nothing to say — the wrapper for it simply stopped arriving — and the
    /// app under test went on playing it until it was rebuilt. Same for a shape
    /// or a keypoint dropped from one, which travel inside their schema.
    ///
    /// Only what the editor sends is ever in here to lose: a container in `dev`
    /// starts empty and reads nothing off disk, and a shipped build never opens
    /// the socket this arrives on.
    func handleMessageSchema(schemaWrappers: [InertiaSchemaWrapper]) {
        InertiaLog.debug("[handleMessageSchema] received \(schemaWrappers.count) schema wrappers")

        var schemas: [InertiaID: InertiaAnimationSchema] = [:]
        var actionableIdToAnimationIdMap: [String: String] = [:]

        for schemaWrapper in schemaWrappers {
            InertiaLog.verbose("[handleMessageSchema] wrapper - containerId: \(schemaWrapper.container.containerId), actionableId: \(schemaWrapper.actionableId), animationId: \(schemaWrapper.animationId)")
            InertiaLog.verbose("[handleMessageSchema] my containerId: \(inertiaDataModel?.containerId ?? "nil")")

            if schemaWrapper.container.containerId == inertiaDataModel?.containerId {
                // The mapping from actionable ID to animation ID
                actionableIdToAnimationIdMap[schemaWrapper.actionableId] = schemaWrapper.animationId
                // The schema, by its animation ID
                schemas[schemaWrapper.animationId] = schemaWrapper.schema
                InertiaLog.info("✅ stored schema - animationId: \(schemaWrapper.animationId) actionableId: \(schemaWrapper.actionableId)")
            } else {
                InertiaLog.warning("❌ skipped - container mismatch")
            }
        }

        inertiaDataModel?.replaceSchemas(schemas, actionableIdToAnimationIdMap: actionableIdToAnimationIdMap)
        InertiaLog.verbose("map now: \(inertiaDataModel?.actionableIdToAnimationIdMap ?? [:])")

        // The loop travels with the schemas, so a project opened at a length
        // other than the default plays at it from the first send rather than
        // waiting for the timeline to be nudged.
        inertiaDataModel?.adoptLoopDurationFromSchemas()

        // Schemas arriving from the editor are the other order round: the
        // actionables are already on screen, and this is the moment the runtime
        // learns which of them start on their own.
        inertiaDataModel?.startAutoAnimations()
    }
    
    func handleMessageActionable(isActionable: Bool) {
        inertiaDataModel?.isActionable = isActionable
    }

    /// The editor has switched tools. Any gesture in progress is dropped rather
    /// than carried over: it was opened against the old tool's handle, and the
    /// property it was editing is not the one the new tool would author.
    func handleMessageTool(tool: InertiaTool) {
        gestureEdit = .none
        inertiaDataModel?.showGrid = false
        inertiaDataModel?.activeTool = tool
    }
}

public struct InertiaAnimationState: Identifiable, Equatable, Codable {
    public let id: InertiaID
    public var trigger: Bool?
    public let isCancelled: Bool
    /// Where the track is frozen after a triggered run has had its pass, in
    /// seconds into the loop — nil while the animation is waiting, running, or
    /// being scrubbed.
    ///
    /// Ending a pass clears `trigger`, so the animation can be asked for again;
    /// on its own that would also take the node back to its initial values,
    /// since nothing but a running track draws anywhere else. It stays where the
    /// run left it instead, which is this: the frame it was showing when the
    /// pass ended, held until it is triggered again.
    public var heldTime: CGFloat?

    public init(id: InertiaID, trigger: Bool? = nil, isCancelled: Bool = false, heldTime: CGFloat? = nil) {
        self.id = id
        self.trigger = trigger
        self.isCancelled = isCancelled
        self.heldTime = heldTime
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

public extension InertiaAnimationValues {
    /// Draws a thing exactly where it was laid out: what something with no
    /// animation of its own is shown at.
    static let identity = InertiaAnimationValues(scale: 1, translate: .zero, rotate: 0, rotateCenter: 0, opacity: 1)

    var isFinite: Bool {
        scale.isFinite && translate.width.isFinite && translate.height.isFinite
            && rotate.isFinite && rotateCenter.isFinite && opacity.isFinite
    }

    /// Falls back to the identity transform so a NaN slipping out of interpolation
    /// can't reach a geometry modifier, which traps.
    var sanitized: InertiaAnimationValues {
        isFinite ? self : .identity
    }
}

public extension InertiaAnimationSchema {
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

    /// This animation as a timeline that can be read at any point in it, rather
    /// than a run that can only be started — which is what scrubbing needs, and
    /// what makes playing and pausing the same operation as scrubbing.
    ///
    /// `loop` is the length every track is padded out to, so actionables of
    /// different lengths come round together. Nil for a run that stops when its
    /// own keyframes do, which is what a non-repeating animation is.
    func timeline(filling loop: CGFloat?) -> KeyframeTimeline<InertiaAnimationValues> {
        let track = loop.map { keyframes(filling: $0) } ?? playableKeyframes

        return KeyframeTimeline(initialValue: initialValues.sanitized) {
            KeyframeTrack {
                for keyframe in track {
                    CubicKeyframe(keyframe.values, duration: keyframe.duration)
                }
            }
        }
    }

    /// Where this animation has got to at `time`, seconds into the loop.
    ///
    /// The one read behind playing, pausing and scrubbing alike — and behind
    /// every place a schema is drawn: the runtime's own actionables and the
    /// shapes they carry, and the editor's shape canvas, which draws the same
    /// schemas with none of the app around them. Sampling in one place is what
    /// keeps the canvas showing the frame the app is showing.
    ///
    /// Sanitized, so a NaN out of a spline solved over a hand-edited file can't
    /// reach a geometry modifier, which traps.
    func values(at time: CGFloat, filling loop: CGFloat?) -> InertiaAnimationValues {
        timeline(filling: loop).value(time: time).sanitized
    }
}

public extension InertiaPlayback {
    /// One turn of the timeline for a set of schemas: the loop, or the longest
    /// track in them where something was recorded past it.
    ///
    /// The runtime works this out for the app it is animating; the editor works
    /// it out for the schemas it draws on its own canvas. One answer for both,
    /// so a track padded in here and the same track padded over there are the
    /// same length and the two playheads mean the same thing.
    static func duration(loop: CGFloat, of schemas: some Collection<InertiaAnimationSchema>) -> CGFloat {
        let longestTrack = schemas
            .map { schema in schema.playableKeyframes.reduce(CGFloat.zero) { $0 + $1.duration } }
            .max() ?? .zero

        return max(loop, longestTrack)
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

public enum InertiaAnimationInvokeType: String, Codable, CustomStringConvertible {
    public var description: String {
        "\(self.rawValue)"
    }
    
    case trigger, auto
}

public struct InertiaAnimationSchema: Codable, Identifiable, Equatable, CustomStringConvertible {
    public var description: String {
"""
{"id": \(id), "initialValues": \(initialValues), "invokeType": \(invokeType), "keyframes": \(keyframes), shapes: \(shapes), loopDuration: \(loopDuration)}
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
    /// How long one loop of the timeline this was authored on lasts.
    ///
    /// A property of the animation rather than of the editor that recorded it:
    /// a track is padded out to the loop, so an animation played back at a
    /// length other than the one it was drawn against holds — or truncates —
    /// where its author did not mean it to. Every schema in a project carries
    /// the same value, which is what the editor's one timeline slider writes.
    ///
    /// Optional to author, so an animation recorded before the loop was part of
    /// the schema — or one happy with the default — still decodes.
    public let loopDuration: CGFloat

    public init(id: InertiaID, initialValues: InertiaAnimationValues, invokeType: InertiaAnimationInvokeType, keyframes: [InertiaAnimationKeyframe], shapes: [InertiaShape] = [], loopDuration: CGFloat = InertiaPlayback.defaultLoopDuration) {
        self.id = id
        self.initialValues = initialValues
        self.invokeType = invokeType
        self.keyframes = keyframes
        self.shapes = shapes
        self.loopDuration = InertiaPlayback.clampLoopDuration(loopDuration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(InertiaID.self, forKey: .id)
        self.initialValues = try container.decode(InertiaAnimationValues.self, forKey: .initialValues)
        self.invokeType = try container.decode(InertiaAnimationInvokeType.self, forKey: .invokeType)
        self.keyframes = try container.decode([InertiaAnimationKeyframe].self, forKey: .keyframes)
        self.shapes = try container.decodeIfPresent([InertiaShape].self, forKey: .shapes) ?? []
        self.loopDuration = InertiaPlayback.clampLoopDuration(
            try container.decodeIfPresent(CGFloat.self, forKey: .loopDuration) ?? InertiaPlayback.defaultLoopDuration
        )
    }

    /// The same animation, authored against a loop of `loopDuration`.
    ///
    /// Every other field is a `let` and stays exactly as it was: the loop is
    /// project-wide, so the editor restamps it across schemas it is otherwise
    /// not editing.
    public func with(loopDuration: CGFloat) -> InertiaAnimationSchema {
        InertiaAnimationSchema(
            id: id,
            initialValues: initialValues,
            invokeType: invokeType,
            keyframes: keyframes,
            shapes: shapes,
            loopDuration: loopDuration
        )
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

func decodeInertiaSchemas(data: Data) -> [InertiaAnimationSchema]? {
    do {
        return try InertiaCoding.decode([InertiaAnimationSchema].self, from: data)
    } catch {
        InertiaLog.error("Failed to decode the animation file: \(error.localizedDescription)")
        return nil
    }
}
