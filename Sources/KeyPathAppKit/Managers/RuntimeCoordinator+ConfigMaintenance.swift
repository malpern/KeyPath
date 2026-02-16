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
                // triggerConfigReload() already checks service health and returns failure
                // when service is unavailable. Don't trigger rollback for that case -
                // the config passed our validation, it just can't be applied yet.
                if !reloadResult.isSuccess,
                   let reason = reloadResult.errorMessage,
                   reason.contains("not healthy") || reason.contains("requires approval") || reason.contains("starting")
                {
                    AppLogger.shared.info("ℹ️ [SaveCoordinator] Service unavailable - config saved but not validated by kanata")
                    return (true, nil)
                }
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
                // Distinguish "TCP unreachable" (service down) from "kanata rejected config".
                // Only trigger rollback for actual config rejections, not network errors.
                if case .networkError = tcpResult {
                    AppLogger.shared.info("ℹ️ [SaveCoordinator] TCP unreachable - config saved but not validated (service may be starting)")
                    return (true, nil)
                }
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
