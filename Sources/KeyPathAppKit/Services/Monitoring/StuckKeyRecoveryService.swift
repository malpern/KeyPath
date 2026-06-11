import Foundation
import KeyPathCore

/// Detects stuck keys (infinite autorepeat after kanata dies) and triggers automatic recovery.
///
/// When kanata crashes or hangs while a key is held, vhiddaemon never receives the key-up
/// event, causing macOS to generate infinite autorepeat. This service monitors for that
/// condition via AutorepeatMismatch correlations and triggers a kanata restart to clear the
/// stale virtual HID state (kanata's startup F24 flush handles the actual key release).
///
/// LIMITATION (MAL-57): This detector lives in the GUI app and only runs while KeyPath.app
/// is open. Stuck-key incidents that occur while the GUI is closed are neither recovered nor
/// captured — both 2026-06-10 MAL-57 incidents were missed for this reason. Daemon-side
/// detection would be needed to close that gap.
@MainActor
final class StuckKeyRecoveryService {
    static let shared = StuckKeyRecoveryService()

    /// Minimum time since last kanata event before we consider a mismatch "stuck" (not normal repeat).
    private static let kanataUnresponsiveThresholdMs = 3000

    /// Minimum cooldown between recovery attempts to avoid restart loops.
    private static let recoveryCooldownSeconds: TimeInterval = 30

    private var lastRecoveryAt: Date?
    private var isRecovering = false

    /// Called to restart kanata. Wired up by RuntimeCoordinator during bootstrap.
    var restartKanata: ((String) async -> Bool)?

    /// Evaluate an AutorepeatMismatch correlation and trigger recovery if the key is truly stuck.
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

        guard !isRecovering else { return }

        if let lastRecovery = lastRecoveryAt,
           Date().timeIntervalSince(lastRecovery) < Self.recoveryCooldownSeconds
        {
            return
        }

        isRecovering = true

        AppLogger.shared.errorUnlessQuietTest(
            "🚨 [StuckKeyRecovery] Stuck key detected: \(correlation.key) repeating with kanata unresponsive for \(msSinceKanata)ms — triggering automatic restart"
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRecovering = false }

            await writeDiagnosticSnapshot(correlation)

            if let restart = restartKanata {
                let success = await restart("Stuck key recovery (\(correlation.key))")
                lastRecoveryAt = Date()
                if success {
                    AppLogger.shared.info("✅ [StuckKeyRecovery] Kanata restarted — stuck key should be cleared")
                } else {
                    AppLogger.shared.errorUnlessQuietTest(
                        "❌ [StuckKeyRecovery] Kanata restart failed — user may need to intervene"
                    )
                }
            } else {
                AppLogger.shared.errorUnlessQuietTest("❌ [StuckKeyRecovery] No restart handler configured — cannot recover")
            }
        }
    }

    // MARK: - Diagnostic Snapshot

    private func writeDiagnosticSnapshot(_ correlation: InvestigationSystemEventCorrelation) async {
        let tracker = await DuplicateKeyInvestigationTracker.shared.snapshot(
            phase: "stuck-key-recovery",
            reason: "key=\(correlation.key) ms_since_kanata=\(correlation.msSinceAnyKanataEvent ?? -1)"
        )

        let lastRecoveryDescription = lastRecoveryAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never"

        let snapshot = DiagnosticSnapshotData(
            correlation: correlation,
            tracker: tracker,
            lastRecoveryDescription: lastRecoveryDescription
        )

        await Task.detached(priority: .utility) {
            Self.writeSnapshotToDisk(snapshot)
        }.value
    }

    private nonisolated static func writeSnapshotToDisk(_ snapshot: DiagnosticSnapshotData) {
        let diagnosticsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KeyPath/stuck-key-incidents")

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
        lines.append("=== Held Keys at Recovery ===")
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

        lines.append("=== System Load ===")
        lines.append(contentsOf: systemLoadLines())
        lines.append("")

        lines.append("=== Kanata Stderr (last 50 lines) ===")
        lines.append(contentsOf: logTail(path: "/var/log/com.keypath.kanata.stderr.log", maxLines: 50))
        lines.append("")

        // The pqrs driver-connection evidence (connected / driver connected / output backend
        // unavailable / dropping KEY_* Release) goes to stdout, not stderr. The high-volume
        // "virtual_hid_keyboard_ready true" heartbeat is filtered out; "... false" lines are
        // kept because they indicate driver disconnects.
        lines.append("=== Kanata Stdout (last 200 lines, vhid-ready spam filtered) ===")
        lines.append(contentsOf: logTail(
            path: "/var/log/com.keypath.kanata.stdout.log",
            maxLines: 200,
            excludingLinesContaining: "virtual_hid_keyboard_ready true"
        ))
        lines.append("")

        lines.append("=== Recovery History ===")
        lines.append("last_recovery_at: \(snapshot.lastRecoveryDescription)")
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

    /// Last `maxLines` lines of a log file, optionally dropping lines that contain `filter`.
    /// Reads only the trailing chunk of the file — kanata's stdout log grows to hundreds of MB.
    nonisolated static func logTail(
        path: String,
        maxLines: Int,
        excludingLinesContaining filter: String? = nil
    ) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return ["(file not readable)"]
        }
        defer { try? handle.close() }

        let maxBytes: UInt64 = 1024 * 1024
        guard let size = try? handle.seekToEnd() else {
            return ["(file not readable)"]
        }
        try? handle.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8)
        else {
            return ["(file not readable)"]
        }

        var tail = content.components(separatedBy: .newlines)
        if let filter {
            tail = tail.filter { !$0.contains(filter) }
        }
        return Array(tail.suffix(maxLines))
    }

    /// Load average plus the top CPU consumers — the leading MAL-57 hypothesis is
    /// CPU-starvation-induced heartbeat misses, so each capture needs load context.
    nonisolated static func systemLoadLines() -> [String] {
        var lines: [String] = []
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            lines.append(String(format: "loadavg: %.2f %.2f %.2f", loads[0], loads[1], loads[2]))
        } else {
            lines.append("loadavg: (unavailable)")
        }
        lines.append("top_cpu_processes:")
        lines.append(contentsOf: topCPUProcessLines(limit: 5))
        return lines
    }

    /// Top CPU-consuming processes via `ps`. Skipped under tests — spawning process-listing
    /// tools in the test environment can deadlock (see KeyPathTestCase).
    nonisolated static func topCPUProcessLines(limit: Int) -> [String] {
        guard !TestEnvironment.isRunningTests else {
            return ["  (skipped in tests)"]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pcpu,pid,comm", "-r"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return ["  (ps output unreadable)"]
            }
            let rows = output.components(separatedBy: .newlines)
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
    let lastRecoveryDescription: String
}
