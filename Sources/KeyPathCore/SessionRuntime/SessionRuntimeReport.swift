import Foundation

/// Private, nonce-bound evidence from the independently launched app process.
/// Contains capabilities and emitted-key cleanup state, never captured input or text.
public struct SessionRuntimeReport: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case capabilities, starting, running, secureInput, stopped, failed
    }

    public let nonce: String
    public let pid: Int32
    public let uid: UInt32
    public let state: State
    public let accessibility: Bool
    public let effectiveInputAccess: Bool
    public let tapActive: Bool
    public let tcpPort: UInt16
    public let inputCount: UInt64
    public let outputCount: UInt64
    public let timestamp: Date
    public let failure: String?
    public let heldOutputUsages: [UInt32]

    public init(
        nonce: String, pid: Int32, uid: UInt32, state: State,
        accessibility: Bool, effectiveInputAccess: Bool, tapActive: Bool,
        tcpPort: UInt16, inputCount: UInt64, outputCount: UInt64,
        timestamp: Date = Date(), failure: String? = nil, heldOutputUsages: [UInt32] = []
    ) {
        self.nonce = nonce
        self.pid = pid
        self.uid = uid
        self.state = state
        self.accessibility = accessibility
        self.effectiveInputAccess = effectiveInputAccess
        self.tapActive = tapActive
        self.tcpPort = tcpPort
        self.inputCount = inputCount
        self.outputCount = outputCount
        self.timestamp = timestamp
        self.failure = failure
        self.heldOutputUsages = heldOutputUsages
    }

    /// Cleanup evidence remains useful after a stalled worker dies. Callers must
    /// confirm termination separately before replaying this launch's ledger.
    public func belongsTo(nonce: String, pid: Int32, uid: UInt32) -> Bool {
        self.nonce == nonce && self.pid == pid && self.uid == uid
    }

    public func isCurrent(nonce: String, pid: Int32, uid: UInt32, now: Date) -> Bool {
        belongsTo(nonce: nonce, pid: pid, uid: uid)
            && timestamp <= now.addingTimeInterval(1)
            && now.timeIntervalSince(timestamp) <= 2
    }
}
