import AppKit
import KeyPathCore

/// Rejects the retired helper-repair launch mode without inspecting host sentinels.
@MainActor
enum OneShotProbeHandler {
    static func handleIfNeeded() -> Bool {
        guard OneShotProbeEnvironment.isActive() else { return false }
        FileHandle.standardError.write(
            Data("Helper repair is unavailable in the driverless build.\n".utf8)
        )
        Task { @MainActor in NSApplication.shared.terminate(nil) }
        return true
    }
}
