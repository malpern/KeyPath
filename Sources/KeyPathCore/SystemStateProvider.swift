import Darwin
import Foundation

/// Central owner for system-state evidence used by installer and runtime decisions.
///
/// Phase 1 grows this into the full snapshot provider. This first slice centralizes
/// the process-liveness primitive so all callers share ADR-040 semantics.
public actor SystemStateProvider {
    public init() {}

    public nonisolated func isProcessAlive(pid: pid_t) -> Bool {
        Self.isProcessAlive(pid: pid)
    }

    public nonisolated static func isProcessAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public nonisolated static func isKanataReady(running: Bool, responding: Bool) -> Bool {
        running && responding
    }
}

public struct KanataLivenessEvidence: Equatable, Sendable {
    public let pid: pid_t?
    public let running: Bool
    public let responding: Bool

    public init(pid: pid_t?, running: Bool, responding: Bool) {
        self.pid = pid
        self.running = running
        self.responding = responding
    }

    public var ready: Bool {
        SystemStateProvider.isKanataReady(running: running, responding: responding)
    }
}
