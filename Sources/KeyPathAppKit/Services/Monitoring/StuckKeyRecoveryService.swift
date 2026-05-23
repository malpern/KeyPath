import Foundation
import KeyPathCore

/// Detects stuck keys (infinite autorepeat after kanata dies) and triggers automatic recovery.
///
/// When kanata crashes or hangs while a key is held, vhiddaemon never receives the key-up
/// event, causing macOS to generate infinite autorepeat. This service monitors for that
/// condition via AutorepeatMismatch correlations and triggers a kanata restart to clear the
/// stale virtual HID state (kanata's startup F24 flush handles the actual key release).
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
           Date().timeIntervalSince(lastRecovery) < Self.recoveryCooldownSeconds {
            return
        }

        isRecovering = true

        AppLogger.shared.error(
            "🚨 [StuckKeyRecovery] Stuck key detected: \(correlation.key) repeating with kanata unresponsive for \(msSinceKanata)ms — triggering automatic restart"
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRecovering = false }

            if let restart = restartKanata {
                let success = await restart("Stuck key recovery (\(correlation.key))")
                lastRecoveryAt = Date()
                if success {
                    AppLogger.shared.info("✅ [StuckKeyRecovery] Kanata restarted — stuck key should be cleared")
                } else {
                    AppLogger.shared.error("❌ [StuckKeyRecovery] Kanata restart failed — user may need to intervene")
                }
            } else {
                AppLogger.shared.error("❌ [StuckKeyRecovery] No restart handler configured — cannot recover")
            }
        }
    }
}
