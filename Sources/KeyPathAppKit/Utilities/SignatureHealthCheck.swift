import Foundation
import KeyPathCore
import Security

#if canImport(AppKit)
    import AppKit
#endif

/// Checks if the running app's signature matches the installed app bundle.
/// This detects cases where the app was updated but not restarted.
enum SignatureHealthCheck {
    /// Returns the Team ID for a signed code object at a given path.
    private static func teamIdentifier(forPath path: String) -> String? {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        let status = SecStaticCodeCreateWithPath(url, [], &staticCode)

        guard status == errSecSuccess, let code = staticCode else {
            return nil
        }

        var infoDict: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, [], &infoDict)

        guard infoStatus == errSecSuccess,
              let info = infoDict as? [String: Any]
        else {
            return nil
        }

        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Whether the running app appears to be ad-hoc/unsigned (no Team ID).
    static func isRunningAdHoc() -> Bool {
        let runningPath = Bundle.main.bundlePath
        guard let team = teamIdentifier(forPath: runningPath) else { return true }
        return team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Verifies that the running process's signature matches the installed app bundle.
    /// Logs warnings if there's a mismatch (which causes XPC helper connection failures).
    static func verifySignatureConsistency() {
        let runningPath = Bundle.main.bundlePath
        let installedPath = "/Applications/KeyPath.app"

        // Only check if we're running from /Applications
        guard runningPath == installedPath else {
            AppLogger.shared.debug("🔐 [Signature] Running from non-standard location: \(runningPath)")
            return
        }

        // Get running process code signature hash
        guard let runningHash = getCodeHash(forPath: runningPath) else {
            AppLogger.shared.log("⚠️ [Signature] Could not read running process signature")
            return
        }

        // Get installed bundle code signature hash
        guard let installedHash = getCodeHash(forPath: installedPath) else {
            AppLogger.shared.log("⚠️ [Signature] Could not read installed bundle signature")
            return
        }

        // Compare hashes
        if runningHash == installedHash {
            AppLogger.shared.debug("✅ [Signature] Running process matches installed bundle")
        } else {
            AppLogger.shared.log("❌ [Signature] MISMATCH DETECTED!")
            AppLogger.shared.log("   Running:   \(runningHash)")
            AppLogger.shared.log("   Installed: \(installedHash)")
            AppLogger.shared.log("   ⚠️  This will cause XPC helper connection failures!")
            AppLogger.shared.log("   💡 SOLUTION: Restart KeyPath to load the new signature")

            // Show alert in non-headless mode
            if !ProcessInfo.processInfo.arguments.contains("--headless") {
                DispatchQueue.main.async {
                    showSignatureMismatchAlert()
                }
            }
        }
    }

    /// Gets the CDHash (code directory hash) for a code object at the given path
    private static func getCodeHash(forPath path: String) -> String? {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        let status = SecStaticCodeCreateWithPath(url, [], &staticCode)

        guard status == errSecSuccess, let code = staticCode else {
            return nil
        }

        var infoDict: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, [], &infoDict)

        guard infoStatus == errSecSuccess,
              let info = infoDict as? [String: Any],
              let cdhash = info["cdhash" as String] as? Data
        else {
            return nil
        }

        return cdhash.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Shows an alert if signature check hasn't been done yet or failed
    /// Called from XPC error handlers when signature mismatch is suspected
    @MainActor
    static func showRestartAlertIfNeeded() {
        // Quick check without full signature comparison
        let runningPath = Bundle.main.bundlePath
        let installedPath = "/Applications/KeyPath.app"

        guard runningPath == installedPath else { return }

        // If app is ad-hoc signed, show a more specific alert.
        if isRunningAdHoc() {
            showUnsignedBuildAlert()
        } else {
            showSignatureMismatchAlert()
        }
    }

    /// Shows an alert warning the user about signature mismatch
    @MainActor
    private static func showSignatureMismatchAlert() {
        #if canImport(AppKit)
            let alert = NSAlert()
            alert.messageText = "KeyPath Needs to Restart"
            alert.informativeText = """
            The KeyPath app has been updated on disk, but you're still running the old version. \
            This prevents communication with system services.

            Please restart KeyPath to load the updated version.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Restart Now")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Restart the app
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["/Applications/KeyPath.app"]
                try? task.run()
                NSApplication.shared.terminate(nil)
            }
        #else
            // AppKit not available (e.g., in test environment) - just log
            AppLogger.shared.log("⚠️ [Signature] Alert not shown - AppKit not available")
        #endif
    }

    /// Shows an alert when the running app is ad-hoc/unsigned (helper will reject XPC).
    @MainActor
    private static func showUnsignedBuildAlert() {
        #if canImport(AppKit)
            let alert = NSAlert()
            alert.messageText = "Unsigned Build Detected"
            alert.informativeText = """
            This KeyPath build is ad-hoc signed, so the privileged helper will reject it.

            For helper access, run a signed build (e.g. ./build.sh) or open the signed app in /Applications.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Signed App")
            alert.addButton(withTitle: "Keep Running")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["/Applications/KeyPath.app"]
                try? task.run()
                NSApplication.shared.terminate(nil)
            }
        #else
            AppLogger.shared.log("⚠️ [Signature] Unsigned build alert not shown - AppKit not available")
        #endif
    }
}
