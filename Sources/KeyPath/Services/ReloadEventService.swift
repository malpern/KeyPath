import Foundation
import KeyPathCore

final class ReloadEventService {
    func awaitReloadEventAndReport(port: Int, timeout: TimeInterval = 2.0) async {
        let client = KanataTCPClient(port: port)
        if let event = await client.awaitOneReloadEvent(timeout: timeout) {
            if event.isReady {
                await MainActor.run { AppLogger.shared.info("✅ [TCP Reload] Ready event received") }
            } else {
                let whereStr = if let line = event.line, let col = event.column {
                    " (line \(line), col \(col))"
                } else {
                    ""
                }
                let msg = event.message ?? "unknown"
                await MainActor.run {
                    AppLogger.shared.error("❌ [TCP Reload] ConfigError: \(msg)\(whereStr)")
                    UserFeedbackService.show(message: "❌ Reload failed: \(msg)\(whereStr)")
                }
            }
        } else {
            await MainActor.run { AppLogger.shared.debug("ℹ️ [TCP Reload] No post-reload event received (timeout)") }
        }
    }
}
