//
// Inertia SwiftUI animation library
// Created by Hayden Pennington
//
// Copyright (c) 2024 Vector Studio. All rights reserved.
//

import Foundation

/// Verbosity levels for the runtime's internal logging, ordered from most to
/// least chatty. Setting `InertiaLog.level` filters out everything below it.
public enum InertiaLogLevel: Int, Comparable, CustomStringConvertible {
    /// Per-frame tracing: animation lookups, full tree/message dumps. Only
    /// useful while chasing a specific bug — floods the console otherwise.
    case verbose = 0
    /// Expected transient states and per-interaction traces (missing
    /// mappings before a schema arrives, gesture bookkeeping).
    case debug = 1
    /// Lifecycle and connection events: container instantiated, listener up,
    /// editor attached. The default — enough to follow what the runtime is
    /// doing without the noise.
    case info = 2
    /// Something unexpected that the runtime recovered from on its own.
    case warning = 3
    /// A failure that broke a request or a connection.
    case error = 4
    /// Silences the runtime entirely.
    case off = 5

    public static func < (lhs: InertiaLogLevel, rhs: InertiaLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .off: return "OFF"
        }
    }
}

/// The runtime's internal logger. Every `[INERTIA_LOG]` line goes through
/// here so a host app can dial verbosity up or down without patching call
/// sites — e.g. `InertiaLog.level = .warning` before shipping, or `.verbose`
/// while chasing an animation-mapping bug.
public enum InertiaLog {
    /// Messages below this level are dropped. Defaults to `.info`.
    public static var level: InertiaLogLevel = .verbose

    public static func verbose(_ message: @autoclosure () -> String) {
        log(.verbose, message())
    }

    public static func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    public static func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    public static func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    public static func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    private static func log(_ messageLevel: InertiaLogLevel, _ message: String) {
        guard messageLevel >= level else { return }
        NSLog("[INERTIA_LOG][\(messageLevel)]: \(message)")
    }
}
