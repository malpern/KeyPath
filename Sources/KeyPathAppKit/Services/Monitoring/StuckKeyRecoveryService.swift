import Foundation
import KeyPathCore

/// Detects stuck keys (infinite autorepeat after kanata dies) and captures diagnostics.
///
/// When kanata crashes or hangs while a key is held, vhiddaemon never receives the key-up
/// event, causing macOS to generate infinite autorepeat. This service monitors for that
/// condition via AutorepeatMismatch correlations, writes an incident snapshot, and surfaces
/// the incident for a user-initiated repair. It must not restart Kanata from this background
/// monitor.
///
/// Limitation: this service lives in the GUI app, so incidents that occur while
/// KeyPath.app is not running are neither detected nor captured (both MAL-57
/// incidents on 2026-06-10 were missed this way). Daemon-side capture would
/// require moving detection out of the app.
@MainActor
final class StuckKeyRecoveryService {
    static let shared = StuckKeyRecoveryService()

    struct StuckKeyIncident: Equatable, Sendable {
        let key: String
        let keyCode: Int64
        let msSinceAnyKanataEvent: Int?
        let observedAt: Date
    }

    /// Minimum time since last kanata event before we consider a mismatch "stuck" (not normal repeat).
    private static let kanataUnresponsiveThresholdMs = 3000

    /// Minimum cooldown between surfaced incidents to avoid notification loops.
    private static let incidentCooldownSeconds: TimeInterval = 30

    private var lastIncidentAt: Date?
    private var isCapturingIncident = false

    /// Called after diagnostic capture so app/UI code can surface user-initiated repair.
    var onIncidentDetected: ((StuckKeyIncident) -> Void)?

    /// Evaluate an AutorepeatMismatch correlation and surface an incident if the key is truly stuck.
    ///
    /// A stuck key is distinguished from normal autorepeat by checking that kanata has been
    /// unresponsive for a significant period — normal repeat events flow through kanata and
    /// show low `msSinceAnyKanataEvent`.
    func handleAutorepeatMismatch(_ correlation: InvestigationSystemEventCorrelation) {
        guard correlation.suggestsUnmatchedAutorepeat else { return }

        guard let msSinceKanata = correlation.msSinceAnyKanataEvent,
              msSinceKanata >= Self.kanataUnresponsiveThresholdMs
        else {
            return
        }

        guard !isCapturingIncident else { return }

        if let lastIncident = lastIncidentAt,
           Date().timeIntervalSince(lastIncident) < Self.incidentCooldownSeconds
        {
            return
        }

        isCapturingIncident = true

        AppLogger.shared.errorUnlessQuietTest(
            "🚨 [StuckKeyRecovery] Stuck key detected: \(correlation.key) repeating with kanata unresponsive for \(msSinceKanata)ms — capturing diagnostics for user repair"
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCapturingIncident = false }

            await writeDiagnosticSnapshot(correlation)

            let incident = StuckKeyIncident(
                key: correlation.key,
                keyCode: correlation.keyCode,
                msSinceAnyKanataEvent: correlation.msSinceAnyKanataEvent,
                observedAt: correlation.observedAt
            )
            lastIncidentAt = Date()
            onIncidentDetected?(incident)
            NotificationCenter.default.post(
                name: .stuckKeyIncidentDetected,
                object: self,
                userInfo: [
                    StuckKeyIncidentNotificationKey.key: incident.key,
                    StuckKeyIncidentNotificationKey.keyCode: incident.keyCode,
                    StuckKeyIncidentNotificationKey.msSinceAnyKanataEvent: incident.msSinceAnyKanataEvent as Any,
                    StuckKeyIncidentNotificationKey.observedAt: incident.observedAt
                ]
            )
            AppLogger.shared.info("[StuckKeyRecovery] Incident surfaced for user-initiated repair")
        }
    }

    // MARK: - Diagnostic Snapshot

    private func writeDiagnosticSnapshot(_ correlation: InvestigationSystemEventCorrelation) async {
        let tracker = await DuplicateKeyInvestigationTracker.shared.snapshot(
            phase: "stuck-key-incident",
            reason: "key=\(correlation.key) ms_since_kanata=\(correlation.msSinceAnyKanataEvent ?? -1)"
        )

        let lastIncidentDescription = lastIncidentAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never"

        let snapshot = DiagnosticSnapshotData(
            correlation: correlation,
            tracker: tracker,
            lastIncidentDescription: lastIncidentDescription
        )

        await Task.detached(priority: .utility) {
            await Self.writeSnapshotToDisk(snapshot)
        }.value
    }

    /// ~/Library/Logs/KeyPath/stuck-key-incidents
    /// (redirected to a temp sandbox during tests via AppPaths). Tests must
    /// never touch the real directory: it holds genuine stuck-key evidence and
    /// the prune-to-20 pass in `writeSnapshotToDisk` would silently delete it.
    nonisolated static var diagnosticsDirectory: URL {
        AppPaths.logsDirectory.appendingPathComponent("stuck-key-incidents", isDirectory: true)
    }

    private nonisolated static func writeSnapshotToDisk(_ snapshot: DiagnosticSnapshotData) async {
        let diagnosticsDir = diagnosticsDirectory

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let filename = "stuck-key-\(safeTimestamp).log"
        let fileURL = diagnosticsDir.appendingPathComponent(filename)

        var lines: [String] = []
        lines.append("=== Stuck Key Incident ===")
        lines.append("timestamp: \(timestamp)")
        lines.append("stuck_key: \(snapshot.correlation.key) (keycode \(snapshot.correlation.keyCode))")
        lines.append("ms_since_any_kanata_event: \(snapshot.correlation.msSinceAnyKanataEvent ?? -1)")
        lines.append("same_key_gap_ms: \(snapshot.correlation.sameKeyGapMs.map(String.init) ?? "nil")")
        lines.append("previous_kanata_action: \(snapshot.correlation.previousKanataAction?.rawValue ?? "none")")
        lines.append("previous_kanata_session: \(snapshot.correlation.previousKanataSessionID.map(String.init) ?? "none")")
        lines.append("event_type: \(snapshot.correlation.eventType)")
        lines.append("is_autorepeat: \(snapshot.correlation.isAutorepeat)")
        lines.append("source_pid: \(snapshot.correlation.sourcePID.map(String.init) ?? "none")")
        lines.append("")
        lines.append("=== Held Keys at Incident ===")
        if snapshot.tracker.heldKeys.isEmpty {
            lines.append("(none tracked)")
        } else {
            for held in snapshot.tracker.heldKeys {
                lines.append("  \(held.key): held for \(held.heldDurationMs)ms")
            }
        }
        lines.append("ms_since_last_key_event: \(snapshot.tracker.msSinceLastEvent.map(String.init) ?? "nil")")
        lines.append("session_id: \(snapshot.tracker.sessionID.map(String.init) ?? "none")")
        lines.append("")

        lines.append("=== Kanata Stderr (last 50 lines) ===")
        lines.append(contentsOf: logTail(path: KeyPathConstants.Logs.kanataStderr, maxLines: 50))
        lines.append("")

        // The diagnostic gold lives in stdout, not stderr: key-input traces, VHID
        // connection events ("connected", "driver connected:", "output backend
        // unavailable during write", "dropping KEY_X Release"). The 2026-06-10 MAL-57
        // incidents were diagnosed entirely from stdout. The high-volume
        // "virtual_hid_keyboard_ready true" heartbeat is filtered out; "... false"
        // lines are kept because they indicate driver disconnects.
        lines.append("=== Kanata Stdout (last 200 lines, vhid-ready spam filtered) ===")
        lines.append(contentsOf: logTail(
            path: KeyPathConstants.Logs.kanataStdout,
            maxLines: 200,
            excludingLinesContaining: "virtual_hid_keyboard_ready true"
        ))
        lines.append("")

        // CPU starvation is the leading trigger for the VHID disconnects
        // behind stuck keys (MAL-57); record load so incidents can confirm or
        // refute the correlation without a live investigation.
        lines.append("=== System Load ===")
        await lines.append(contentsOf: systemLoadLines())
        lines.append("")

        lines.append("=== Incident History ===")
        lines.append("last_incident_at: \(snapshot.lastIncidentDescription)")
        lines.append("")

        do {
            try FileManager.default.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            AppLogger.shared.info("[StuckKeyRecovery] Diagnostic snapshot written to \(fileURL.path)")
        } catch {
            AppLogger.shared.error("[StuckKeyRecovery] Failed to write diagnostic snapshot: \(error)")
        }

        // Keep at most 20 incident files
        if let files = try? FileManager.default.contentsOfDirectory(
            at: diagnosticsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) {
            let sorted = files
                .compactMap { url -> (URL, Date)? in
                    guard let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
                        return nil
                    }
                    return (url, date)
                }
                .sorted { $0.1 > $1.1 }

            for (url, _) in sorted.dropFirst(20) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Capture Helpers

    /// Last `maxLines` non-empty lines of a log file, optionally dropping lines that
    /// contain `filter`. Reads only the trailing `maxBytes` of the file — the kanata
    /// stdout log can exceed 100MB; never load it whole. When the read is truncated, a
    /// marker line is prepended (on top of `maxLines`, so the result can be
    /// `maxLines + 1` long) so a capture dominated by filtered spam can't masquerade
    /// as the full history.
    nonisolated static func logTail(
        path: String,
        maxLines: Int,
        maxBytes: UInt64 = 1024 * 1024,
        excludingLinesContaining filter: String? = nil
    ) -> [String] {
        let unreadable = ["(file not readable)"]
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return unreadable
        }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else {
            return unreadable
        }
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else {
            return unreadable
        }

        // Lossy decode: a truncated read can start mid-multibyte-character, which would
        // make String(data:encoding:) fail for the whole chunk.
        var tail = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        if offset > 0 {
            tail = Array(tail.dropFirst()) // first line of a truncated read is partial
        }
        // Drop empties (including the artifact of a trailing newline) and filtered spam.
        tail = tail.filter { line in
            guard !line.isEmpty else { return false }
            guard let filter else { return true }
            return !line.contains(filter)
        }
        var result = Array(tail.suffix(maxLines))
        if offset > 0 {
            result.insert("(… older output truncated: tail window is the last \(maxBytes / 1024)KB of the file)", at: 0)
        }
        return result
    }

    /// Load average, core count, and the top CPU consumers — the leading MAL-57
    /// hypothesis is CPU-starvation-induced heartbeat misses, so each capture
    /// needs load context.
    nonisolated static func systemLoadLines() async -> [String] {
        var lines: [String] = []
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            lines.append(String(format: "loadavg_1m_5m_15m: %.2f %.2f %.2f", loads[0], loads[1], loads[2]))
        } else {
            lines.append("loadavg_1m_5m_15m: (unavailable)")
        }
        lines.append("active_cpu_count: \(ProcessInfo.processInfo.activeProcessorCount)")
        lines.append("top_cpu_processes:")
        await lines.append(contentsOf: topCPUProcessLines(limit: 5))
        return lines
    }

    /// Top CPU-consuming processes via `ps`. Skipped under tests — spawning process-listing
    /// tools in the test environment can deadlock (see KeyPathTestCase). The timeout keeps a
    /// slow `ps` (plausible under the very CPU starvation being diagnosed) from stalling the
    /// incident snapshot.
    nonisolated static func topCPUProcessLines(limit: Int) async -> [String] {
        guard !TestEnvironment.isRunningTests else {
            return ["  (skipped in tests)"]
        }

        do {
            let result = try await SubprocessRunner.shared.run(
                "/bin/ps",
                args: ["-Aceo", "pcpu,pid,comm", "-r"],
                timeout: 5
            )
            let rows = result.stdout.components(separatedBy: .newlines)
                .dropFirst() // header
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return rows.prefix(limit).map { "  \($0)" }
        } catch {
            return ["  (ps failed: \(error.localizedDescription))"]
        }
    }
}

private struct DiagnosticSnapshotData: Sendable {
    let correlation: InvestigationSystemEventCorrelation
    let tracker: InvestigationReloadSnapshot
    let lastIncidentDescription: String
}

extension Notification.Name {
    static let stuckKeyIncidentDetected = Notification.Name("KeyPathStuckKeyIncidentDetected")
}

enum StuckKeyIncidentNotificationKey {
    static let key = "key"
    static let keyCode = "keyCode"
    static let msSinceAnyKanataEvent = "msSinceAnyKanataEvent"
    static let observedAt = "observedAt"
}
