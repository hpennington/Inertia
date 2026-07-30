//
//  InertiaWebSocketClient.swift
//  Inertia
//
//  The editor hosts the WebSocket; the runtime dials into it — the same
//  direction the React and Compose runtimes already use.
//

import Foundation
import Observation

/// The port the editor listens on for SwiftUI runtimes.
public let inertiaDefaultPort: UInt16 = 8060

/// Where to find the editor. A simulator shares this Mac's network stack, so
/// loopback reaches the editor process directly. A runtime on a physical device
/// needs the Mac's address on the local network instead — pass it to
/// ``InertiaWebSocketClient/setEnabled(_:host:port:)``.
public let inertiaDefaultHost: String = "127.0.0.1"

@available(*, deprecated, renamed: "InertiaWebSocketClient")
public typealias InertiaWebSocketServer = InertiaWebSocketClient

/// Bridges `URLSession`'s delegate callbacks back to the client.
///
/// `URLSessionWebSocketDelegate` requires `NSObject` inheritance, which the
/// `@Observable` client does not want, so the conformance lives here and
/// forwards. Open and close are worth having from the delegate rather than
/// inferring them from send and receive results: without them a dial at a port
/// nobody is listening on looks connected until the first message fails.
private final class InertiaWebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: ((URLSessionWebSocketTask) -> Void)? = nil
    var onClose: ((URLSessionWebSocketTask) -> Void)? = nil

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        onOpen?(webSocketTask)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onClose?(webSocketTask)
    }

    /// Fires for a dial that never opened — the editor not running yet, which is
    /// the normal case at launch — as well as for one that dropped later.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let webSocketTask = task as? URLSessionWebSocketTask else { return }
        onClose?(webSocketTask)
    }
}

@Observable
public final class InertiaWebSocketClient {
    public static let shared = InertiaWebSocketClient()

    /// True while the editor connection is open.
    public private(set) var isConnected: Bool = false

    public var messageReceived: ((_ selectedIds: Set<ActionableIdPair>) -> Void)? = nil
    public var messageReceivedSchema: ((_ schemas: [InertiaSchemaWrapper]) -> Void)? = nil
    public var messageReceivedSignal: ((_ signal: AnimationSignal, _ sequence: Int) -> Void)? = nil
    public var messageReceivedIsActionable: ((_ isActionable: Bool) -> Void)? = nil

    // Plumbing below is deliberately not observed: `isConnected` is the only
    // thing the view tree reacts to, and registering the send path's state with
    // the observation machinery would put it on every playback frame.
    @ObservationIgnored private let queue = DispatchQueue(label: "com.inertia.websocket.client")
    @ObservationIgnored private let delegate = InertiaWebSocketDelegate()
    @ObservationIgnored private lazy var session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

    /// Everything below is owned by `queue`.
    @ObservationIgnored private var task: URLSessionWebSocketTask? = nil
    /// True once the connection is open, mirrored to `isConnected` on the main
    /// queue. Kept here as well because sends need to test it without hopping.
    @ObservationIgnored private var isOpen: Bool = false
    @ObservationIgnored private var endpoint: URL = URL(string: "ws://\(inertiaDefaultHost):\(inertiaDefaultPort)")!
    @ObservationIgnored private var reconnectAttempt: Int = 0

    @ObservationIgnored private let playbackProgressLock = NSLock()
    @ObservationIgnored private var pendingPlaybackProgress: InertiaMessage.MessagePlaybackProgress? = nil
    /// True from the moment a playback-progress send is handed to the network
    /// until its completion has actually fired.
    ///
    /// The clock ticks every ~16ms regardless of how long a send takes to
    /// drain, so without this a stall anywhere downstream lets sends queue up
    /// in the socket layer — and they then drain in a burst once whatever was
    /// stalling clears, rather than a steady stream. Only one send is ever
    /// outstanding; anything that arrives while it's in flight overwrites
    /// `pendingPlaybackProgress` and rides along on the next one.
    @ObservationIgnored private var isPlaybackProgressSendInFlight = false

    // MARK: - Diagnostics
    @ObservationIgnored private var diagSentCount = 0
    @ObservationIgnored private var diagCoalescedCount = 0
    @ObservationIgnored private var diagSendDurationMsTotal: Double = 0
    @ObservationIgnored private var diagLastLogMs: UInt64 = 0
    private static let diagLogIntervalMs: UInt64 = 2_000

    /// Guarded by `playbackProgressLock`: called from the send-completion
    /// callback, but `diagCoalescedCount` is also written from `sendMessage`,
    /// which can run on a different thread (whatever calls `report(isRunning:)`).
    private func logPlaybackProgressDiagnosticsIfDue() {
        let nowMs = DispatchTime.now().uptimeNanoseconds / 1_000_000

        playbackProgressLock.lock()
        if diagLastLogMs == 0 {
            diagLastLogMs = nowMs
            playbackProgressLock.unlock()
            return
        }
        let elapsedMs = nowMs &- diagLastLogMs
        guard elapsedMs >= Self.diagLogIntervalMs else {
            playbackProgressLock.unlock()
            return
        }
        let sent = diagSentCount
        let coalesced = diagCoalescedCount
        let avgSendMs = sent > 0 ? diagSendDurationMsTotal / Double(sent) : 0
        diagSentCount = 0
        diagCoalescedCount = 0
        diagSendDurationMsTotal = 0
        diagLastLogMs = nowMs
        playbackProgressLock.unlock()

        let elapsedS = Double(elapsedMs) / 1000
        InertiaLog.debug(String(format: "[diag] playbackProgress sent=%d coalesced=%d over %.1fs avgSendMs=%.2f", sent, coalesced, elapsedS, avgSendMs))
    }

    /// Whether the runtime is allowed to talk to the editor at all.
    ///
    /// Set from `InertiaContainer`'s `dev` flag, and false until something sets
    /// it: a shipped build has no business dialing an editor, and the decision
    /// belongs here rather than at the call sites so that a `start()` from
    /// anywhere — a view that is still on screen from a previous editor session,
    /// or an embedder driving the runtime directly — cannot open one either.
    @ObservationIgnored private var isEnabled: Bool = false

    /// Whether anything has asked to be connected yet. Held separately from
    /// `isEnabled` because the two arrive from different places in the view
    /// tree, in no guaranteed order: the container enables the channel, the
    /// editable views request the connection. Whichever lands second dials.
    @ObservationIgnored private var isStartRequested: Bool = false

    init() {
        delegate.onOpen = { [weak self] task in
            self?.queue.async { self?.handleOpen(task) }
        }
        delegate.onClose = { [weak self] task in
            self?.queue.async { self?.handleClose(task) }
        }
    }

    /// Opens or closes the editor channel for the whole process.
    ///
    /// Disabling drops the connection, so a container that switches out of
    /// editor mode does not leave one open.
    ///
    /// The client is a singleton, so this is process-wide: in an app with more
    /// than one container the last one to appear decides. That is the intended
    /// shape — `dev` comes from a build flag, so every container in a build
    /// agrees — but a deliberately mixed hierarchy would need its own gate.
    public func setEnabled(
        _ isEnabled: Bool,
        host: String = inertiaDefaultHost,
        port: UInt16 = inertiaDefaultPort
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard isEnabled != self.isEnabled else { return }

            self.isEnabled = isEnabled

            if isEnabled {
                InertiaLog.info("Editor channel enabled")
                self.setEndpoint(host: host, port: port)
                if self.isStartRequested {
                    self.connect()
                }
            } else {
                InertiaLog.info("Editor channel disabled, tearing down")
                self.tearDown()
            }
        }
    }

    /// Asks to be connected to the editor, if the editor channel is enabled.
    /// Safe to call repeatedly — subsequent calls are ignored while a connection
    /// is already up or being dialed.
    public func start(host: String = inertiaDefaultHost, port: UInt16 = inertiaDefaultPort) {
        queue.async { [weak self] in
            guard let self else { return }

            self.isStartRequested = true

            guard self.isEnabled else {
                InertiaLog.debug("Not connecting — editor channel is disabled")
                return
            }

            self.setEndpoint(host: host, port: port)
            self.connect()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStartRequested = false
            self.tearDown()
        }
    }

    // MARK: - Connection

    /// Must run on `queue`. Redialing on a changed endpoint drops the current
    /// connection so the next `connect()` picks the new address up.
    private func setEndpoint(host: String, port: UInt16) {
        guard let url = URL(string: "ws://\(host):\(port)") else {
            InertiaLog.error("Invalid editor endpoint: ws://\(host):\(port)")
            return
        }
        guard url != endpoint else { return }

        endpoint = url
        if task != nil {
            dropConnection()
        }
    }

    /// Must run on `queue`.
    private func connect() {
        guard isEnabled, isStartRequested else { return }
        guard task == nil else { return }

        InertiaLog.info("Connecting to editor at \(endpoint)")

        let task = session.webSocketTask(with: endpoint)
        self.task = task
        task.resume()

        receiveNextMessage(on: task)
    }

    /// Must run on `queue`.
    private func handleOpen(_ task: URLSessionWebSocketTask) {
        guard task === self.task else { return }

        InertiaLog.info("Editor connected at \(endpoint)")
        isOpen = true
        reconnectAttempt = 0
        publishIsConnected(true)
    }

    /// Must run on `queue`. Idempotent: the delegate and a failed receive can
    /// both report the same drop, and only the one still holding the current
    /// task gets to act on it.
    private func handleClose(_ task: URLSessionWebSocketTask) {
        guard task === self.task else { return }

        if isOpen {
            InertiaLog.info("🔌 Editor connection closed")
        }
        dropConnection()
        scheduleReconnect()
    }

    /// Must run on `queue`.
    private func dropConnection() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isOpen = false
        publishIsConnected(false)
    }

    /// Must run on `queue`. Backs off so a runtime left running against no
    /// editor is not dialing every half second forever, but stays quick enough
    /// that starting the editor attaches within a few seconds.
    private func scheduleReconnect() {
        guard isEnabled, isStartRequested else { return }

        let delay = min(0.5 * pow(2, Double(reconnectAttempt)), 4)
        reconnectAttempt += 1

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    /// Must run on `queue`.
    private func tearDown() {
        dropConnection()
        reconnectAttempt = 0
    }

    private func publishIsConnected(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = connected
        }
    }

    // MARK: - Receive

    private func receiveNextMessage(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                self.queue.async {
                    guard task === self.task else { return }
                    InertiaLog.error("Receive error: \(error)")
                    self.handleClose(task)
                }
            case .success(let message):
                switch message {
                case .data(let data):
                    self.decodeAndHandle(data)
                case .string(let text):
                    InertiaLog.warning("Received unexpected text frame: \(text)")
                @unknown default:
                    InertiaLog.warning("Received an unknown message type")
                }

                self.receiveNextMessage(on: task)
            }
        }
    }

    private func decodeAndHandle(_ data: Data) {
        do {
            let messageWrapper = try JSONDecoder().decode(InertiaMessage.MessageWrapper.self, from: data)
            handleMessage(messageWrapper)
        } catch {
            InertiaLog.error("Receive decode error: \(error)")
        }
    }

    private func handleMessage(_ messageWrapper: InertiaMessage.MessageWrapper) {
        switch messageWrapper.type {
        case .actionable:
            guard let message = try? JSONDecoder().decode(InertiaMessage.MessageActionable.self, from: messageWrapper.payload) else {
                return
            }
            InertiaLog.verbose("Received message (data): \(message)")
            DispatchQueue.main.async { self.messageReceivedIsActionable?(message.isActionable) }
        case .actionables:
            guard let message = try? JSONDecoder().decode(InertiaMessage.MessageActionables.self, from: messageWrapper.payload) else {
                return
            }
            DispatchQueue.main.async { self.messageReceived?(message.actionableIds) }
        case .schema:
            guard let message = try? JSONDecoder().decode(InertiaMessage.MessageSchema.self, from: messageWrapper.payload) else {
                return
            }
            InertiaLog.verbose("Received message (data): \(message)")
            DispatchQueue.main.async { self.messageReceivedSchema?(message.schemaWrappers) }
        case .signal:
            guard let message = try? JSONDecoder().decode(InertiaMessage.MessageSignal.self, from: messageWrapper.payload) else {
                return
            }
            InertiaLog.verbose("Received message (data): \(message)")
            DispatchQueue.main.async { self.messageReceivedSignal?(message.signal, message.sequence) }
        case .translationEnded:
            // Runtime-to-editor only.
            InertiaLog.warning("Unexpected translationEnded from editor")
        case .selectedNodeProperties:
            // Runtime-to-editor only.
            InertiaLog.warning("Unexpected selectedNodeProperties from editor")
        case .playbackProgress:
            // Runtime-to-editor only.
            InertiaLog.warning("Unexpected playbackProgress from editor")
        }
    }

    // MARK: - Send

    public func sendMessage(_ message: InertiaMessage.MessageSelectedNodeProperties) {
        send(type: .selectedNodeProperties, payload: message)
    }

    public func sendMessage(_ message: InertiaMessage.MessageActionables) {
        send(type: .actionables, payload: message)
    }

    public func sendMessage(_ message: InertiaMessage.MessageSchema) {
        send(type: .schema, payload: message)
    }

    public func sendMessage(_ message: InertiaMessage.MessageTranslation) {
        send(type: .translationEnded, payload: message)
    }

    public func sendMessage(_ message: InertiaMessage.MessagePlaybackProgress) {
        playbackProgressLock.lock()
        let isOverwritingPending = pendingPlaybackProgress != nil
        pendingPlaybackProgress = message
        let shouldStartSend = !isPlaybackProgressSendInFlight
        if shouldStartSend {
            isPlaybackProgressSendInFlight = true
        }
        if isOverwritingPending { diagCoalescedCount += 1 }
        playbackProgressLock.unlock()

        guard shouldStartSend else { return } // A send is already draining; it'll pick up this value once it completes.

        queue.async { [weak self] in
            self?.flushPlaybackProgress()
        }
    }

    private func send<T: Encodable>(type: InertiaMessage.MessageType, payload: T) {
        queue.async { [weak self] in
            self?.sendNow(type: type, payload: payload)
        }
    }

    private func flushPlaybackProgress() {
        playbackProgressLock.lock()
        let message = pendingPlaybackProgress
        pendingPlaybackProgress = nil
        playbackProgressLock.unlock()

        guard let message else {
            playbackProgressLock.lock()
            isPlaybackProgressSendInFlight = false
            playbackProgressLock.unlock()
            return
        }

        // Only schedules the next flush once the send for this one has actually
        // completed — never more than one playback progress send outstanding at
        // a time.
        let sendStartMs = DispatchTime.now().uptimeNanoseconds / 1_000_000
        sendNow(type: .playbackProgress, payload: message) { [weak self] in
            guard let self else { return }

            let sendDurationMs = Double((DispatchTime.now().uptimeNanoseconds / 1_000_000) &- sendStartMs)

            self.playbackProgressLock.lock()
            self.diagSentCount += 1
            self.diagSendDurationMsTotal += sendDurationMs
            let hasPendingMessage = self.pendingPlaybackProgress != nil
            if !hasPendingMessage {
                self.isPlaybackProgressSendInFlight = false
            }
            self.playbackProgressLock.unlock()

            self.logPlaybackProgressDiagnosticsIfDue()

            guard hasPendingMessage else { return }

            self.queue.async { [weak self] in
                self?.flushPlaybackProgress()
            }
        }
    }

    /// Must run on `queue`. `completion` runs exactly once however the send
    /// ends, including the paths that never reach the socket — the playback
    /// progress flush stalls forever otherwise.
    private func sendNow<T: Encodable>(
        type: InertiaMessage.MessageType,
        payload: T,
        completion: (() -> Void)? = nil
    ) {
        guard let task, isOpen else {
            completion?()
            return
        }

        guard
            let payloadData = try? JSONEncoder().encode(payload),
            let wrapperData = try? JSONEncoder().encode(InertiaMessage.MessageWrapper(type: type, payload: payloadData))
        else {
            InertiaLog.error("Error encoding message of type \(type)")
            completion?()
            return
        }

        task.send(.data(wrapperData)) { [weak self] error in
            if let error = error {
                InertiaLog.error("Send error: \(error)")
                self?.queue.async { self?.handleClose(task) }
            } else if type != .playbackProgress {
                // Progress ticks every frame; logging them drowns the log.
                InertiaLog.verbose("Sent message of type \(type)")
            }
            completion?()
        }
    }
}
