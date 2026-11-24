import AppKit

/// Apple Events run off the main thread; only one request is in flight.
final class DockControl {
    private let queue = DispatchQueue(label: "DockTide.AppleEvents", qos: .utility)

    func run(_ statement: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", "tell application \"System Events\" to tell dock preferences to \(statement)"]
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                try process.run()
                // Both responses are tiny, bounded AppleScript messages.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "DockTide", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: errorData, as: UTF8.self)])
                }
                let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                DispatchQueue.main.async { completion(.success(value)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
