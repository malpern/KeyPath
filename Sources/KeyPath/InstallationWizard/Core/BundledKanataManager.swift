import AppKit
import Foundation
import KeyPathCore

@MainActor
class BundledKanataManager {
    private let packageManager = PackageManager()

    /// Replace system kanata binary with bundled Developer ID signed version
    func replaceBinaryWithBundled() async -> Bool {
        AppLogger.shared.log("🔄 [BundledKanataManager] Starting replacement of system kanata binary")

        guard let systemKanataPath = findSystemKanataPath() else {
            AppLogger.shared.log("❌ [BundledKanataManager] No system kanata binary found to replace")
            return false
        }

        guard bundledKanataExists() else {
            AppLogger.shared.log("❌ [BundledKanataManager] Bundled kanata binary not found")
            return false
        }

        do {
            let backupPath = try createBackup(of: systemKanataPath)
            AppLogger.shared.log("📁 [BundledKanataManager] Created backup at: \(backupPath)")

            let success = try await replaceSystemBinary(at: systemKanataPath)
            if success {
                AppLogger.shared.log("✅ [BundledKanataManager] Successfully replaced system kanata binary")
                return true
            } else {
                try restoreBackup(from: backupPath, to: systemKanataPath)
                AppLogger.shared.log("🔙 [BundledKanataManager] Replacement failed, backup restored")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [BundledKanataManager] Replacement failed: \(error)")
            return false
        }
    }

    /// Check if bundled kanata is properly signed
    func bundledKanataSigningStatus() -> CodeSigningStatus {
        let bundledPath = WizardSystemPaths.bundledKanataPath
        return packageManager.getCodeSigningStatus(at: bundledPath)
    }

    /// Get information about the current system kanata installation
    func getSystemKanataInfo() -> KanataInstallationInfo? {
        guard let systemPath = findSystemKanataPath() else { return nil }

        let installationInfo = packageManager.detectKanataInstallation()

        if installationInfo.isInstalled, installationInfo.path == systemPath {
            return installationInfo
        }

        return nil
    }

    // MARK: - Private Methods

    private func findSystemKanataPath() -> String? {
        let systemPaths = [
            WizardSystemPaths.kanataSystemInstallPath, // System install (highest priority)
            "/usr/local/bin/kanata", // Intel Homebrew
            "/opt/homebrew/bin/kanata" // ARM Homebrew
        ]

        for path in systemPaths where FileManager.default.fileExists(atPath: path) {
            AppLogger.shared.log("🔍 [BundledKanataManager] Found system kanata at: \(path)")
            return path
        }

        return nil
    }

    private func bundledKanataExists() -> Bool {
        let bundledPath = WizardSystemPaths.bundledKanataPath
        let exists = FileManager.default.fileExists(atPath: bundledPath)

        if exists {
            AppLogger.shared.log("✅ [BundledKanataManager] Bundled kanata found at: \(bundledPath)")
        } else {
            AppLogger.shared.log("❌ [BundledKanataManager] Bundled kanata not found at: \(bundledPath)")
        }

        return exists
    }

    private func createBackup(of originalPath: String) throws -> String {
        let backupPath = "\(originalPath).backup.\(Int(Date().timeIntervalSince1970))"

        try FileManager.default.copyItem(atPath: originalPath, toPath: backupPath)
        AppLogger.shared.log("📁 [BundledKanataManager] Created backup: \(originalPath) -> \(backupPath)")

        return backupPath
    }

    private func replaceSystemBinary(at systemPath: String) async throws -> Bool {
        let bundledPath = WizardSystemPaths.bundledKanataPath

        let result = await PrivilegedCommandRunner.runAsync(
            "cp '\(bundledPath)' '\(systemPath)'",
            prompt: "KeyPath needs to replace the system kanata binary."
        )

        if result.exitCode == 0 {
            AppLogger.shared.log("✅ [BundledKanataManager] Successfully copied bundled kanata to system path")
            return verifyReplacement(at: systemPath)
        } else {
            AppLogger.shared.log("❌ [BundledKanataManager] Privileged command error: \(result.output)")
            return false
        }
    }

    private func verifyReplacement(at systemPath: String) -> Bool {
        let newSigningStatus = packageManager.getCodeSigningStatus(at: systemPath)
        let bundledSigningStatus = bundledKanataSigningStatus()

        let verified = newSigningStatus.isDeveloperID && bundledSigningStatus.isDeveloperID

        if verified {
            AppLogger.shared.log("✅ [BundledKanataManager] Verification successful: System binary is now Developer ID signed")
        } else {
            AppLogger.shared.log("❌ [BundledKanataManager] Verification failed: System binary signing status: \(newSigningStatus)")
        }

        return verified
    }

    private func restoreBackup(from backupPath: String, to originalPath: String) throws {
        let result = PrivilegedCommandRunner.run(
            "cp '\(backupPath)' '\(originalPath)'",
            prompt: "KeyPath needs to restore the backup binary."
        )

        if result.exitCode != 0 {
            AppLogger.shared.log("❌ [BundledKanataManager] Failed to restore backup: \(result.output)")
            throw NSError(domain: "BundledKanataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to restore backup"])
        }

        AppLogger.shared.log("🔙 [BundledKanataManager] Successfully restored backup")
        try FileManager.default.removeItem(atPath: backupPath)
        AppLogger.shared.log("🗑️ [BundledKanataManager] Cleaned up backup file")
    }
}
