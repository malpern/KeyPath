import Foundation

/// Central owner for system-state evidence used by installer and runtime decisions.
///
/// Process liveness and engine-socket readiness live here so callers share one definition.
public actor SystemStateProvider {
    public static let shared = SystemStateProvider()
    public static let liveProbes = SystemProbeClient.live

    private let probes: SystemProbeClient

    public init(probes: SystemProbeClient = .live) {
        self.probes = probes
    }

    public nonisolated func isProcessAlive(pid: pid_t) -> Bool {
        Self.isProcessAlive(pid: pid)
    }

    /// Whether the session worker's engine answers on its control socket (ADR-046).
    public func isEngineSocketResponding(path: String?, timeoutMs: Int = 300) async -> Bool {
        guard let path else { return false }
        return await Task.detached { EngineControlSocket.isResponding(path: path, timeoutMs: timeoutMs) }.value
    }

    public func processIDs(matching pattern: String) async -> [pid_t] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }
        return await probes.processIDs(matching: trimmedPattern)
    }

    public func processMatches(matching pattern: String) async -> [SystemProcessMatch] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }
        return await probes.processMatches(matching: trimmedPattern)
    }

    public nonisolated static func processIDsSynchronously(matching pattern: String) -> [pid_t] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }

        return liveProbes.processIDsSynchronously(matching: trimmedPattern)
    }

    public nonisolated static func isProcessAlive(pid: pid_t) -> Bool {
        liveProbes.isProcessAlive(pid: pid)
    }

    public nonisolated static func canSignalProcess(pid: pid_t) -> Bool {
        SystemProbeClient.canSignalProcess(pid: pid)
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
