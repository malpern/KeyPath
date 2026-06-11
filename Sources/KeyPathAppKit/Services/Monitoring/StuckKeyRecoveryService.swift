import Foundation
import KeyPathCore

/// Detects stuck keys (infinite autorepeat after kanata dies) and triggers automatic recovery.
///
/// When kanata crashes or hangs while a key is held, vhiddaemon never receives the key-up
/// event, causing macOS to generate infinite autorepeat. This service monitors for that
/// condition via AutorepeatMismatch correlations and triggers a kanata restart to clear the
/// stale virtual HID state (kanata's startup F24 flush handles the actual key release).
///
/// Limitation: this service lives in the GUI app, so incidents that occur while
/// KeyPath.app is not running are neither detected nor captured (both MAL-57
/// incidents on 2026-06-10 were missed this way). Daemon-side capture would
/// require moving detection out of the app.
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

    /// Where incident snapshots are written. Tests must never touch the real directory:
    /// it holds genuine stuck-key evidence and the prune-to-20 pass in
    /// `writeSnapshotToDisk` would silently delete it, so test runs are redirected to a
    /// temp location.
    nonisolated static var diagnosticsDirectory: URL {
        if TestEnvironment.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("KeyPathTests/stuck-key-incidents", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KeyPath/stuck-key-incidents", isDirectory: true)
    }

    private nonisolated static func writeSnapshotToDisk(_ snapshot: DiagnosticSnapshotData) {
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

        lines.append("=== Kanata Stderr (last 50 lines) ===")
        if let data = FileManager.default.contents(atPath: "/var/log/com.keypath.kanata.stderr.log"),
           let content = String(data: data, encoding: .utf8)
        {
            lines.append(contentsOf: content.components(separatedBy: .newlines).suffix(50))
        } else {
            lines.append("(file not readable)")
        }
        lines.append("")

        // The diagnostic gold lives in stdout, not stderr: key-input traces,
        // VHID connection events ("connected", "driver connected:",
        // "output backend unavailable during write", "dropping KEY_X Release").
        // The 2026-06-10 MAL-57 incidents were diagnosed entirely from stdout.
        lines.append("=== Kanata Stdout (last 120 lines) ===")
        lines.append(contentsOf: tailOfFile(
            atPath: KeyPathConstants.Logs.kanataStdout,
            lineCount: 120
        ))
        lines.append("")

        // CPU starvation is the leading trigger for the VHID disconnects
        // behind stuck keys (MAL-57); record load so incidents can confirm or
        // refute the correlation without a live investigation.
        lines.append("=== System Load ===")
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            lines.append("loadavg_1m_5m_15m: \(loads[0]) \(loads[1]) \(loads[2])")
        } else {
            lines.append("loadavg_1m_5m_15m: (unavailable)")
        }
        lines.append("active_cpu_count: \(ProcessInfo.processInfo.activeProcessorCount)")
        if !TestEnvironment.isRunningTests {
            lines.append("top_cpu_processes:")
            lines.append(contentsOf: topCPUProcesses())
        }
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

    /// Bounded tail of a possibly-huge log file. The kanata stdout log can
    /// exceed 100MB; never load it whole. Internal for testability.
    nonisolated static func tailOfFile(
        atPath path: String,
        lineCount: Int,
        maxBytes: Int = 64 * 1024
    ) -> [String] {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return ["(file not readable)"]
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64 = (try? fileHandle.seekToEnd()) ?? 0
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        try? fileHandle.seek(toOffset: offset)
        guard let data = try? fileHandle.readToEnd(),
              let content = String(data: data, encoding: .utf8)
        else {
            return ["(file not readable)"]
        }
        return Array(content.components(separatedBy: .newlines).suffix(lineCount))
    }

    /// Top CPU consumers at capture time. Spawns `ps`; callers must not invoke
    /// this in tests (subprocess spawning is forbidden there — see KeyPathTestCase).
    private nonisolated static func topCPUProcesses(count: Int = 5) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pcpu,comm", "-r"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ["  (ps failed to launch: \(error.localizedDescription))"]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            return ["  (ps output unreadable)"]
        }
        return output
            .components(separatedBy: .newlines)
            .dropFirst() // header
            .prefix(count)
            .map { "  \($0.trimmingCharacters(in: .whitespaces))" }
    }
}

private struct DiagnosticSnapshotData: Sendable {
    let correlation: InvestigationSystemEventCorrelation
    let tracker: InvestigationReloadSnapshot
    let lastRecoveryDescription: String
}
