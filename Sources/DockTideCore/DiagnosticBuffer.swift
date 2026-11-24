/// A bounded, in-memory trace. It never writes files or sends data anywhere.
public struct DiagnosticBuffer {
    public let capacity: Int
    public private(set) var entries: [String] = []

    public init(capacity: Int = 60) { self.capacity = max(1, capacity) }

    public mutating func append(_ entry: String) {
        guard entries.last != entry else { return }
        if entries.count == capacity { entries.removeFirst() }
        entries.append(entry)
    }
}
