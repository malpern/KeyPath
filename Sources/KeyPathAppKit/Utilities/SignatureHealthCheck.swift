import Foundation
import KeyPathCore
import Security

#if canImport(AppKit)
    import AppKit
#endif

/// Checks if the running app's signature matches the installed app bundle.
/// This detects cases where the app was updated but not restarted.
enum SignatureHealthCheck {
    /// Verifies that the running process's signature matches the installed app bundle.
    /// Logs warnings if there's a mismatch: the session runtime worker launches from the
    /// bundle on disk, so a stale parent would run beside a newer worker.
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
            AppLogger.shared.log("   ⚠️  The session runtime would launch from the newer bundle")
            AppLogger.shared.log("   💡 SOLUTION: Restart KeyPath to load the new signature")

            // Show alert in non-headless mode
            if !ProcessInfo.processInfo.arguments.contains("--headless") {
                Task { @MainActor in
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

    /// Shows an alert warning the user about signature mismatch
    @MainActor
    private static func showSignatureMismatchAlert() {
        #if canImport(AppKit)
            let alert = NSAlert()
            alert.messageText = "KeyPath Needs to Restart"
            alert.informativeText = """
            KeyPath has been updated on disk, but you're still running the old version. \
            Its keyboard runtime starts from the updated copy, so the two may not match.

            Please restart KeyPath to load the updated version.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Restart Now")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Restart the app
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/KeyPath.app"))
                NSApplication.shared.terminate(nil)
            }
        #else
            // AppKit not available (e.g., in test environment) - just log
            AppLogger.shared.log("⚠️ [Signature] Alert not shown - AppKit not available")
        #endif
    }
}
