import Foundation
import os

/// Unified logging. Messages are marked public because NSLog-style output is redacted as
/// <private> on current macOS, which makes field diagnostics impossible. Nothing personal is
/// logged: only DDC bytes, return codes and state changes.
///
/// Read with: /usr/bin/log stream --level debug --predicate 'subsystem == "<bundle id>"'
/// (raw I2C traffic is logged at debug level, so it is only shown with `--level debug`).
public enum Log {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "candelactl"
    private static let ddcLogger = Logger(subsystem: subsystem, category: "ddc")
    private static let appLogger = Logger(subsystem: subsystem, category: "app")

    public static func ddc(_ message: String) { ddcLogger.notice("\(message, privacy: .public)") }
    /// One raw I2C transaction. Debug level: not stored on disk, shown only when asked for.
    public static func trace(_ message: String) { ddcLogger.debug("\(message, privacy: .public)") }
    public static func app(_ message: String) { appLogger.notice("\(message, privacy: .public)") }
    public static func error(_ message: String) { appLogger.error("\(message, privacy: .public)") }
}
