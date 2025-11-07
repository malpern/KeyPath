import Foundation
import KeyPathCore

enum ProcessKiller {
    static func kill(pid: Int) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["kill", "-TERM", String(pid)]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.info("✅ [Kill] Successfully killed process \(pid)")
            } else {
                AppLogger.shared.warn("⚠️ [Kill] Failed to kill process \(pid) (may have already exited)")
            }
        } catch {
            AppLogger.shared.error("❌ [Kill] Exception killing process \(pid): \(error)")
        }
    }
}


