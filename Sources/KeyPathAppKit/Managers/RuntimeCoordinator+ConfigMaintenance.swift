import Foundation
import KeyPathCore

extension RuntimeCoordinator {
    /// Configuration management errors
    enum ConfigError: Error, LocalizedError {
        case noBackupAvailable
        case reloadFailed(String)
        case validationFailed([String])
        case postSaveValidationFailed(errors: [String])

        var errorDescription: String? {
            switch self {
            case .noBackupAvailable:
                "No backup configuration available for rollback"
            case let .reloadFailed(message):
                "Config reload failed: \(message)"
            case let .validationFailed(errors):
                "Config validation failed: \(errors.joined(separator: ", "))"
            case let .postSaveValidationFailed(errors):
                "Post-save validation failed: \(errors.joined(separator: ", "))"
            }
        }
    }

    /// Backup current working config before making changes
    func backupCurrentConfig() async {
        let config = await configurationService.current()
        saveCoordinator.backupCurrentConfig(config.content)
    }

    /// Restore last known good config in case of validation failure
    func restoreLastGoodConfig() async throws {
        try await saveCoordinator.restoreLastGoodConfig()
    }

    /// Save a complete generated configuration (for Claude API generated configs)
    func saveGeneratedConfiguration(_ configContent: String) async throws {
        AppLogger.shared.log("💾 [RuntimeCoordinator] Saving generated configuration")

        let result = await saveCoordinator.saveGeneratedConfig(
            content: configContent,
            reloadHandler: { [weak self] in
                guard let self else { return (false, "Coordinator deallocated") }
                let reloadResult = await triggerConfigReload()
                return (reloadResult.isSuccess, reloadResult.errorMessage)
            }
        )

        // Sync coordinator state to RuntimeCoordinator
        saveStatus = saveCoordinator.saveStatus

        if result.success, let mappings = result.mappings {
            lastConfigUpdate = Date()
            applyKeyMappings(mappings)
            notifyStateChanged()
        } else if let error = result.error {
            notifyStateChanged()
            throw error
        }
    }

    func saveConfiguration(input: String, output: String) async throws {
        AppLogger.shared.log("💾 [RuntimeCoordinator] Saving configuration mapping")

        let result = await saveCoordinator.saveMapping(
            input: input,
            output: output,
            ruleCollectionsManager: ruleCollectionsManager,
            reloadHandler: { [weak self] in
                guard let self else { return (false, "Coordinator deallocated") }
                let tcpResult = await triggerTCPReload()
                return (tcpResult.isSuccess, tcpResult.errorMessage)
            }
        )

        // Sync coordinator state to RuntimeCoordinator
        saveStatus = saveCoordinator.saveStatus

        if result.success, let mappings = result.mappings {
            applyKeyMappings(mappings, persistCollections: false)
            notifyStateChanged()
            AppLogger.shared.log("⚡ [Config] Validation-on-demand save completed")
        } else if let error = result.error {
            notifyStateChanged()
            throw error
        }
    }
}
