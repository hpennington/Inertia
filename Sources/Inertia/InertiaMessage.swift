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

/// What a drag in the runtime's viewport edits.
///
/// Picked in the editor's toolbar and pushed to the runtime, because the gesture
/// happens in the app under test rather than in the editor. One case per
/// property of ``InertiaAnimationValues``: the toolbar, the timeline's
/// per-property rows and the handles a selected node grows are three views of
/// the same five numbers.
public enum InertiaTool: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case translate
    case rotate
    case rotateCenter
    case opacity
    case scale

    public var id: String { rawValue }
}

public enum InertiaMessage {
    public enum MessageType: String, Codable {
        case actionable
        case actionables
        case translationEnded
        case schema
        case selectedNodeProperties
        case signal
        case playbackProgress
        case tool
        case edit
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
    
    /// Sent while a gesture is in progress, for the editor's inspector.
    ///
    /// `values` is what the selection would be authored at if the gesture ended
    /// now, and is absent from runtimes that only ever move a node — the field
    /// is decoded with `decodeIfPresent` so a translate-only runtime's message
    /// still reads.
    public struct MessageSelectedNodeProperties: Codable {
        public let positionX: CGFloat
        public let positionY: CGFloat
        public let sizeX: CGFloat
        public let sizeY: CGFloat
        public let values: InertiaAnimationValues?

        public init(
            positionX: CGFloat,
            positionY: CGFloat,
            sizeX: CGFloat,
            sizeY: CGFloat,
            values: InertiaAnimationValues? = nil
        ) {
            self.positionX = positionX
            self.positionY = positionY
            self.sizeX = sizeX
            self.sizeY = sizeY
            self.values = values
        }

        enum CodingKeys: String, CodingKey {
            case positionX, positionY, sizeX, sizeY, values
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            positionX = try container.decode(CGFloat.self, forKey: .positionX)
            positionY = try container.decode(CGFloat.self, forKey: .positionY)
            sizeX = try container.decode(CGFloat.self, forKey: .sizeX)
            sizeY = try container.decode(CGFloat.self, forKey: .sizeY)
            values = try container.decodeIfPresent(InertiaAnimationValues.self, forKey: .values)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(positionX, forKey: .positionX)
            try container.encode(positionY, forKey: .positionY)
            try container.encode(sizeX, forKey: .sizeX)
            try container.encode(sizeY, forKey: .sizeY)
            try container.encodeIfPresent(values, forKey: .values)
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

    /// Editor → runtime: which tool a gesture on a selected node applies.
    ///
    /// The runtime opens on ``InertiaTool/translate`` and keeps whatever it was
    /// last told, so a runtime that reconnects mid-session is sent the current
    /// tool again rather than being left on the default.
    public struct MessageTool: Codable {
        public let tool: InertiaTool

        public init(tool: InertiaTool) {
            self.tool = tool
        }
    }

    /// Runtime → editor: where a gesture left the selection.
    ///
    /// Carries the whole transform rather than the one property the active tool
    /// changed, because that is what the editor records — a keyframe holds all
    /// five values, and the four the tool did not touch still have to be the
    /// ones the node is actually sitting at.
    ///
    /// Generalizes ``MessageTranslation``, which the React and Compose runtimes
    /// still send and which the editor reads as an edit that only translates.
    public struct MessageEdit: Codable {
        public let tool: InertiaTool
        public let values: InertiaAnimationValues
        public let actionableIds: Set<ActionableIdPair>

        public init(tool: InertiaTool, values: InertiaAnimationValues, actionableIds: Set<ActionableIdPair>) {
            self.tool = tool
            self.values = values
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
