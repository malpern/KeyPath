import ApplicationServices
import Foundation
import IOKit.hidsystem
import SwiftUI

// MARK: - KanataManager Configuration Extension

extension KanataManager {
    // MARK: - Configuration Initialization

    func createInitialConfigIfNeeded() async {
        do {
            try await configurationService.createInitialConfigIfNeeded()
        } catch {
            AppLogger.shared.log("❌ [Config] Failed to create initial config via ConfigurationService: \(error)")
        }
    }

    /// Public wrapper to ensure a default user config exists.
    /// Returns true if the config exists after this call.
    func createDefaultUserConfigIfMissing() async -> Bool {
        AppLogger.shared.log("🛠️ [Config] Ensuring default user config at \(configurationService.configurationPath)")
        await createInitialConfigIfNeeded()
        let exists = FileManager.default.fileExists(atPath: configurationService.configurationPath)
        if exists {
            AppLogger.shared.log("✅ [Config] Verified user config exists at \(configurationService.configurationPath)")
        } else {
            AppLogger.shared.log("❌ [Config] User config still missing at \(configurationService.configurationPath)")
        }
        return exists
    }

    // MARK: - Configuration Validation

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        guard FileManager.default.fileExists(atPath: configurationService.configurationPath) else {
            return (false, ["Config file does not exist at: \(configurationService.configurationPath)"])
        }

        // Use CLI validation (TCP-only mode)
        AppLogger.shared.log("📄 [Validation] Using file-based validation")
        return configurationService.validateConfigViaFile()
    }

    // MARK: - Hot Reload via TCP

    /// Main reload method using TCP protocol
    func triggerConfigReload() async -> ReloadResult {
        // Try TCP reload
        AppLogger.shared.log("📡 [Reload] Attempting TCP reload")
        let tcpResult = await triggerTCPReload()
        if tcpResult.isSuccess {
            return ReloadResult(
                success: true,
                response: tcpResult.response ?? "",
                errorMessage: nil,
                protocol: .tcp
            )
        } else {
            AppLogger.shared.log("📡 [Reload] TCP reload failed: \(tcpResult.errorMessage ?? "Unknown error")")
            // Fall back to service restart
            AppLogger.shared.log("⚠️ [Reload] Falling back to service restart")
            await restartKanata()
            return ReloadResult(
                success: true,
                response: "Service restarted (TCP reload failed)",
                errorMessage: nil,
                protocol: nil
            )
        }
    }

    /// TCP-based config reload (no authentication required - see ADR-013)
    func triggerTCPReload() async -> TCPReloadResult {
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [TCP Reload] Skipping TCP reload in test environment")
            return .networkError("Test environment - TCP disabled")
        }

        AppLogger.shared.log("📡 [TCP Reload] Triggering config reload via EngineClient (TCP)")
        return await engineClient.reloadConfig()
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        let result = await triggerConfigReload()
        if !result.isSuccess {
            AppLogger.shared.log("🔄 [Reload] Falling back to service restart due to error: \(result.errorMessage ?? "Unknown")")
            await restartKanata()
        }
    }
}

// MARK: - Result Types

/// UDP reload result
struct ReloadResult {
    let success: Bool
    let response: String?
    let errorMessage: String?
    let `protocol`: CommunicationProtocol?

    var isSuccess: Bool { success }
}
