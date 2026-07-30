//
//  InertiaWebSocketServer.swift
//  Inertia
//
//  The runtime hosts the WebSocket; the editor connects to it as a client.
//

import Foundation
import Network
import Observation

public let inertiaDefaultPort: UInt16 = 8060

@Observable
public final class InertiaWebSocketServer {
    public static let shared = InertiaWebSocketServer()

    /// True once at least one editor is attached.
    public private(set) var isConnected: Bool = false

    public var messageReceived: ((_ selectedIds: Set<ActionableIdPair>) -> Void)? = nil
    public var messageReceivedSchema: ((_ schemas: [InertiaSchemaWrapper]) -> Void)? = nil
    public var messageReceivedSignal: ((_ signal: AnimationSignal, _ sequence: Int) -> Void)? = nil
    public var messageReceivedIsActionable: ((_ isActionable: Bool) -> Void)? = nil

    private var listener: NWListener? = nil
    private var connections: [UUID: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.inertia.websocket.server")
    private let playbackProgressLock = NSLock()
    private var pendingPlaybackProgress: InertiaMessage.MessagePlaybackProgress? = nil
    /// True from the moment a playback-progress send is handed to the network
    /// until every ready connection's completion for it has actually fired.
    ///
    /// The clock ticks every ~16ms regardless of how long a send takes to
    /// drain, so without this a stall anywhere downstream lets sends queue up
    /// in the socket layer — and they then drain in a burst once whatever was
    /// stalling clears, rather than a steady stream. Only one send is ever
    /// outstanding; anything that arrives while it's in flight overwrites
    /// `pendingPlaybackProgress` and rides along on the next one.
    private var isPlaybackProgressSendInFlight = false

    // MARK: - Diagnostics
    private var diagSentCount = 0
    private var diagCoalescedCount = 0
    private var diagSendDurationMsTotal: Double = 0
    private var diagLastLogMs: UInt64 = 0
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

    /// Whether the runtime is allowed to host the editor channel at all.
    ///
    /// Set from `InertiaContainer`'s `dev` flag, and false until something sets
    /// it: a shipped build has no business listening on a port, and the decision
    /// belongs here rather than at the call sites so that a `start()` from
    /// anywhere — a view that is still on screen from a previous editor session,
    /// or an embedder driving the runtime directly — cannot open one either.
    private var isEnabled: Bool = false

    init() {}

    /// Opens or closes the editor channel for the whole process.
    ///
    /// Disabling tears down the listener and every attached editor, so a
    /// container that switches out of editor mode does not leave the port open.
    ///
    /// The server is a singleton, so this is process-wide: in an app with more
    /// than one container the last one to appear decides. That is the intended
    /// shape — `dev` comes from a build flag, so every container in a build
    /// agrees — but a deliberately mixed hierarchy would need its own gate.
    public func setEnabled(_ isEnabled: Bool, port: UInt16 = inertiaDefaultPort) {
        queue.async { [weak self] in
            guard let self else { return }
            guard isEnabled != self.isEnabled else { return }

            self.isEnabled = isEnabled

            if isEnabled {
                InertiaLog.info("Editor channel enabled")
            } else {
                InertiaLog.info("Editor channel disabled, tearing down")
                self.tearDown()
            }
        }
    }

    /// Starts listening, if the editor channel is enabled. Safe to call
    /// repeatedly — subsequent calls are ignored while a listener is already up.
    public func start(port: UInt16 = inertiaDefaultPort) {
        queue.async { [weak self] in
            self?._start(port: port)
        }
    }

    private func _start(port: UInt16) {
        guard isEnabled else {
            InertiaLog.debug("Not starting listener — editor channel is disabled")
            return
        }
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        guard
            let nwPort = NWEndpoint.Port(rawValue: port),
            let listener = try? NWListener(using: parameters, on: nwPort)
        else {
            InertiaLog.error("Failed to create listener on port \(port)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                InertiaLog.info("Listener ready on port \(port)")
            case .failed(let error):
                InertiaLog.error("Listener failed: \(error)")
                self?.queue.async { self?.tearDown() }
            case .cancelled:
                InertiaLog.warning("Listener cancelled")
            default:
                break
            }
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async { [weak self] in
            self?.tearDown()
        }
    }

    private func tearDown() {
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        updateIsConnected()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let clientId = UUID()
        connections[clientId] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                InertiaLog.info("Editor connected: \(clientId)")
                self.updateIsConnected()
                self.receiveNextMessage(on: connection, clientId: clientId)
            case .failed(let error):
                InertiaLog.error("Connection failed: \(error)")
                self.remove(clientId)
            case .cancelled:
                InertiaLog.warning("Connection cancelled: \(clientId)")
                self.remove(clientId)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func remove(_ clientId: UUID) {
        connections.removeValue(forKey: clientId)?.cancel()
        updateIsConnected()
    }

    private func updateIsConnected() {
        let connected = connections.values.contains { $0.state == .ready }
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = connected
        }
    }

    // MARK: - Receive

    private func receiveNextMessage(on connection: NWConnection, clientId: UUID) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if let error = error {
                InertiaLog.error("Receive error: \(error)")
                self.remove(clientId)
                return
            }

            defer { self.receiveNextMessage(on: connection, clientId: clientId) }

            guard let context = context else { return }

            if let wsMetadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch wsMetadata.opcode {
                case .close:
                    InertiaLog.info("🔌 Editor closed connection: \(clientId)")
                    self.remove(clientId)
                    return
                case .ping, .pong:
                    return // Auto-replied
                default:
                    break
                }
            }

            guard let data = data else { return }

            do {
                let messageWrapper = try JSONDecoder().decode(InertiaMessage.MessageWrapper.self, from: data)
                self.handleMessage(messageWrapper)
            } catch {
                InertiaLog.error("Receive decode error: \(error)")
            }
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
            InertiaLog.warning("Unexpected selectedNodePropertiesr from editor")
        case .playbackProgress:
            // Runtime-to-editor only.
            InertiaLog.warning("Unexpected playbackProgress from editor")
        }
    }

    // MARK: - Send

    public func sendMessage(_ message: InertiaMessage.MessageSelectedNodeProperties) {
        broadcast(type: .selectedNodeProperties, payload: message)
    }
    
    public func sendMessage(_ message: InertiaMessage.MessageActionables) {
        broadcast(type: .actionables, payload: message)
    }

    public func sendMessage(_ message: InertiaMessage.MessageSchema) {
        broadcast(type: .schema, payload: message)
    }

    public func sendMessage(_ message: InertiaMessage.MessageTranslation) {
        broadcast(type: .translationEnded, payload: message)
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

    private func broadcast<T: Encodable>(type: InertiaMessage.MessageType, payload: T) {
        queue.async { [weak self] in
            self?.broadcastNow(type: type, payload: payload)
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

        // Only schedules the next flush once every ready connection's send for
        // this one has actually completed — never more than one playback
        // progress send outstanding at a time.
        let sendStartMs = DispatchTime.now().uptimeNanoseconds / 1_000_000
        broadcastNow(type: .playbackProgress, payload: message) { [weak self] in
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

    private func broadcastNow<T: Encodable>(type: InertiaMessage.MessageType, payload: T, completion: (() -> Void)? = nil) {
        guard
            let payloadData = try? JSONEncoder().encode(payload),
            let wrapperData = try? JSONEncoder().encode(InertiaMessage.MessageWrapper(type: type, payload: payloadData))
        else {
            InertiaLog.error("Error encoding message of type \(type)")
            completion?()
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "WebSocketMessage", metadata: [metadata])

        let readyConnections = connections.filter { $0.value.state == .ready }

        guard !readyConnections.isEmpty else {
            completion?()
            return
        }

        let group = completion.map { _ in DispatchGroup() }

        for (clientId, connection) in readyConnections {
            group?.enter()
            connection.send(content: wrapperData, contentContext: context, isComplete: true, completion: .contentProcessed({ error in
                if let error = error {
                    InertiaLog.error("Send error to \(clientId): \(error)")
                } else if type != .playbackProgress {
                    // Progress ticks every frame; logging them drowns the log.
                    InertiaLog.verbose("Sent message of type \(type)")
                }
                group?.leave()
            }))
        }

        if let group, let completion {
            group.notify(queue: queue, execute: completion)
        }
    }
}
