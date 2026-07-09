import Foundation
@_exported import KeyPathSystemProbes

/// Central owner for system-state evidence used by installer and runtime decisions.
///
/// Phase 1 grows this into the full snapshot provider. The first slices centralize
/// process-liveness and TCP-readiness primitives so callers share one definition.
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

    public func isTCPPortResponding(port: Int, timeoutMs: Int = 300) async -> Bool {
        probes.probeTCPPort(port: port, timeoutMs: timeoutMs)
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

    public func launchctlPrint(target: String) async -> LaunchctlPrintEvidence {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            return LaunchctlPrintEvidence(target: "", exitCode: nil, stdout: "", stderr: "")
        }

        return await probes.launchctlPrint(target: trimmedTarget)
    }

    public nonisolated static func processIDsSynchronously(matching pattern: String) -> [pid_t] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }

        return liveProbes.processIDsSynchronously(matching: trimmedPattern)
    }

    public nonisolated static func isProcessAlive(pid: pid_t) -> Bool {
        liveProbes.isProcessAlive(pid: pid)
    }

    public nonisolated static func probeTCPPort(port: Int, timeoutMs: Int = 300) -> Bool {
        liveProbes.probeTCPPort(port: port, timeoutMs: timeoutMs)
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
