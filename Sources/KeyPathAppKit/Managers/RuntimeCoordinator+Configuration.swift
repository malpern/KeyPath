import ApplicationServices
import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle

// MARK: - RuntimeCoordinator Configuration Extension

extension RuntimeCoordinator {
    // MARK: - Configuration Initialization

    func createInitialConfigIfNeeded() async {
        do {
            try await configurationService.createInitialConfigIfNeeded()
        } catch {
            AppLogger.shared.error(
                "❌ [Config] Failed to create initial config via ConfigurationService: \(error)"
            )
        }
    }

    /// Public wrapper to ensure a default user config exists.
    /// Returns true if the config exists after this call.
    func createDefaultUserConfigIfMissing() async -> Bool {
        await configurationManager.createDefaultIfMissing()
    }

    // MARK: - Configuration Validation

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        await configurationManager.validateConfigFile()
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
        -> String
    {
        try await configurationManager.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )
    }

    // MARK: - Hot Reload via TCP (delegates to ConfigReloadCoordinator)

    /// Main reload method using TCP protocol
    func triggerConfigReload() async -> ReloadResult {
        await configReloadCoordinator.triggerConfigReload()
    }

    /// TCP-based config reload (no authentication required - see ADR-013)
    func triggerTCPReload() async -> TCPReloadResult {
        await configReloadCoordinator.triggerTCPReload()
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        await configReloadCoordinator.triggerReload()
    }
}

// MARK: - Result Types

/// TCP reload result
struct ReloadResult {
    let success: Bool
    let response: String?
    let errorMessage: String?
    let `protocol`: CommunicationProtocol?

    var isSuccess: Bool {
        success
    }
}
