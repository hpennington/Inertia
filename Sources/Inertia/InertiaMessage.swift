//
//  InertiaMessage.swift
//  Inertia
//
//  Wire format shared by the runtime (server) and the editor (client).
//
//  Every frame is one MessagePack-encoded `MessageWrapper`, sent as a binary
//  WebSocket frame. `payload` is `Data`, which MessagePack carries as a `bin`
//  value: the inner message is a separately encoded MessagePack document, so
//  the envelope can be read without knowing what it holds.
//

import Foundation

public enum InertiaMessage {
    public enum MessageType: String, Codable {
        case actionable
        case actionables
        case translationEnded
        case schema
        case selectedNodeProperties
        case signal
        case playbackProgress
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
        public let actionableIds: Set<ActionableIdPair>

        public init(tree: Tree, actionableIds: Set<ActionableIdPair>) {
            self.tree = tree
            self.actionableIds = actionableIds
        }
    }
    
    public struct MessageSelectedNodeProperties: Codable {
        public let positionX: CGFloat
        public let positionY: CGFloat
        public let sizeX: CGFloat
        public let sizeY: CGFloat
        
        public init(positionX: CGFloat, positionY: CGFloat, sizeX: CGFloat, sizeY: CGFloat) {
            self.positionX = positionX
            self.positionY = positionY
            self.sizeX = sizeX
            self.sizeY = sizeY
        }
    }

    public struct MessageTranslation: Codable {
        public let translationX: CGFloat
        public let translationY: CGFloat
        public let actionableIds: Set<ActionableIdPair>

        public init(translationX: CGFloat, translationY: CGFloat, actionableIds: Set<ActionableIdPair>) {
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
    
    /// Where the run currently on screen has got to, reported by the runtime
    /// while it animates so the editor's playhead can follow it.
    public struct MessagePlaybackProgress: Codable {
        /// Seconds since the run started, clamped to `duration`.
        public let time: CGFloat
        /// Length of the longest track in the run.
        public let duration: CGFloat
        /// False on the last message of a run — it finished or was paused.
        public let isRunning: Bool
        /// The `sequence` of the last `MessageSignal` the runtime had applied
        /// when this report was produced.
        ///
        /// The runtime's clock free-runs and keeps reporting while a pause or
        /// resume signal is still in flight, so the editor can't tell a stale
        /// report from a fresh one by `isRunning` alone. Echoing back the
        /// sequence it has caught up to lets the editor tell structurally
        /// whether a given report reflects a request it already sent, instead
        /// of guessing from a timeout.
        public let lastProcessedSequence: Int

        public init(time: CGFloat, duration: CGFloat, isRunning: Bool, lastProcessedSequence: Int) {
            self.time = time
            self.duration = duration
            self.isRunning = isRunning
            self.lastProcessedSequence = lastProcessedSequence
        }
    }

    public struct MessageSignal: Codable {
        public let signal: AnimationSignal
        /// Monotonically increasing per connection; assigned by the sender.
        /// Echoed back in `MessagePlaybackProgress.lastProcessedSequence` once
        /// the runtime has applied it.
        public let sequence: Int

        public init(signal: AnimationSignal, sequence: Int) {
            self.signal = signal
            self.sequence = sequence
        }
    }
}
