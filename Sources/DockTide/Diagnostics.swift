import AppKit
import ApplicationServices
import DockTideCore

/// All callers run on the main run loop. No window titles, contents or screenshots.
enum Diagnostics {
    private static var buffer = DiagnosticBuffer()
    private static let start = ProcessInfo.processInfo.systemUptime

    static func record(_ message: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        buffer.append(String(format: "+%.2fs %@", elapsed, message))
    }

    static func report() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        return (["DockTide \(version)", ProcessInfo.processInfo.operatingSystemVersionString,
                 "Accessibility trusted: \(AXIsProcessTrusted())", "--- Recent events (memory only) ---"]
                + buffer.entries).joined(separator: "\n")
    }
}
