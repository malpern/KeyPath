import Foundation

/// In-memory ring buffer for wizard events (no I/O).
actor WizardTelemetry {
    static let shared = WizardTelemetry()

    private var buffer: [WizardEvent] = []
    private var capacity: Int
    private var index: Int = 0
    private var isFull = false

    init(capacity: Int = 200) {
        self.capacity = capacity
        buffer = Array(repeating: WizardEvent(timestamp: .distantPast, category: .health, name: "init", result: nil, details: nil), count: capacity)
    }

    func record(_ event: WizardEvent) {
        buffer[index] = event
        index = (index + 1) % capacity
        if index == 0 { isFull = true }
    }

    func snapshot() -> [WizardEvent] {
        if !isFull {
            return Array(buffer.prefix(index))
        }
        return Array(buffer[index...] + buffer[..<index])
    }

    func reset() {
        buffer = Array(repeating: WizardEvent(timestamp: .distantPast, category: .health, name: "init", result: nil, details: nil), count: capacity)
        index = 0
        isFull = false
    }
}
