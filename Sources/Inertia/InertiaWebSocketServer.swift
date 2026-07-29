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
    public var messageReceivedSignal: ((_ signal: AnimationSignal) -> Void)? = nil
    public var messageReceivedIsActionable: ((_ isActionable: Bool) -> Void)? = nil

    private var listener: NWListener? = nil
    private var connections: [UUID: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.inertia.websocket.server")

    init() {}

    /// Starts listening. Safe to call repeatedly — subsequent calls are ignored
    /// while a listener is already up.
    public func start(port: UInt16 = inertiaDefaultPort) {
        queue.async { [weak self] in
            self?._start(port: port)
        }
    }

    private func _start(port: UInt16) {
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
            NSLog("[INERTIA_LOG]: ❌ Failed to create listener on port \(port)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("[INERTIA_LOG]: ✅ Listener ready on port \(port)")
            case .failed(let error):
                NSLog("[INERTIA_LOG]: ❌ Listener failed: \(error)")
                self?.queue.async { self?.tearDown() }
            case .cancelled:
                NSLog("[INERTIA_LOG]: ⚠️ Listener cancelled")
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
                NSLog("[INERTIA_LOG]: ✅ Editor connected: \(clientId)")
                self.updateIsConnected()
                self.receiveNextMessage(on: connection, clientId: clientId)
            case .failed(let error):
                NSLog("[INERTIA_LOG]: ❌ Connection failed: \(error)")
                self.remove(clientId)
            case .cancelled:
                NSLog("[INERTIA_LOG]: ⚠️ Connection cancelled: \(clientId)")
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
                NSLog("[INERTIA_LOG]: ❌ Receive error: \(error)")
                self.remove(clientId)
                return
            }

            defer { self.receiveNextMessage(on: connection, clientId: clientId) }

            guard let context = context else { return }

            if let wsMetadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch wsMetadata.opcode {
                case .close:
                    NSLog("[INERTIA_LOG]: 🔌 Editor closed connection: \(clientId)")
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
                NSLog("[INERTIA_LOG]: ❌ Receive decode error: \(error)")
            }
        }
    }

    private func handleMessage(_ messageWrapper: InertiaMessage.MessageWrapper) {
        switch messageWrapper.type {
        case .actionable:
            guard let message = try? JSONDecoder().decode(InertiaMessage.MessageActionable.self, from: messageWrapper.payload) else {
                return
            }
            NSLog("[INERTIA_LOG]: Received message (data): \(message)")
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
            NSLog("[INERTIA_LOG]: Received message (data): \(message)")
            DispatchQueue.main.async { self.messageReceivedSchema?(message.schemaWrappers) }
        case .signal:
            guard let message = try? JSONDecoder().decode(InertiaMessage.MessageSignal.self, from: messageWrapper.payload) else {
                return
            }
            NSLog("[INERTIA_LOG]: Received message (data): \(message)")
            DispatchQueue.main.async { self.messageReceivedSignal?(message.signal) }
        case .translationEnded:
            // Runtime-to-editor only.
            NSLog("[INERTIA_LOG]: ⚠️ Unexpected translationEnded from editor")
        case .selectedNodeProperties:
            // Runtime-to-editor only.
            NSLog("[INERTIA_LOG]: ⚠️ Unexpected selectedNodePropertiesr from editor")
        case .playbackProgress:
            // Runtime-to-editor only.
            NSLog("[INERTIA_LOG]: ⚠️ Unexpected playbackProgress from editor")
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
        broadcast(type: .playbackProgress, payload: message)
    }

    private func broadcast<T: Encodable>(type: InertiaMessage.MessageType, payload: T) {
        queue.async { [weak self] in
            guard let self else { return }

            guard
                let payloadData = try? JSONEncoder().encode(payload),
                let wrapperData = try? JSONEncoder().encode(InertiaMessage.MessageWrapper(type: type, payload: payloadData))
            else {
                NSLog("[INERTIA_LOG]: ❌ Error encoding message of type \(type)")
                return
            }

            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "WebSocketMessage", metadata: [metadata])

            for (clientId, connection) in self.connections where connection.state == .ready {
                connection.send(content: wrapperData, contentContext: context, isComplete: true, completion: .contentProcessed({ error in
                    if let error = error {
                        NSLog("[INERTIA_LOG]: ❌ Send error to \(clientId): \(error)")
                    } else if type != .playbackProgress {
                        // Progress ticks every frame; logging them drowns the log.
                        NSLog("[INERTIA_LOG]: ✅ Sent message of type \(type)")
                    }
                }))
            }
        }
    }
}
