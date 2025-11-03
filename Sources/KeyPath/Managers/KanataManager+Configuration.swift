import ApplicationServices
import KeyPathCore
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
            AppLogger.shared.error("❌ [Config] Failed to create initial config via ConfigurationService: \(error)")
        }
    }

    /// Public wrapper to ensure a default user config exists.
    /// Returns true if the config exists after this call.
    func createDefaultUserConfigIfMissing() async -> Bool {
        return await configurationManager.createDefaultIfMissing()
    }

    // MARK: - Configuration Validation

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        return await configurationManager.validateConfigFile()
    }

    // MARK: - Hot Reload via TCP

    /// Main reload method using TCP protocol
    func triggerConfigReload() async -> ReloadResult {
        // Try TCP reload
        AppLogger.shared.debug("📡 [Reload] Attempting TCP reload")
        let tcpResult = await triggerTCPReload()
        if tcpResult.isSuccess {
            // Successful reload -> clear stale diagnostics (e.g., Invalid Configuration)
            clearDiagnostics()
            return ReloadResult(
                success: true,
                response: tcpResult.response ?? "",
                errorMessage: nil,
                protocol: .tcp
            )
        } else {
            AppLogger.shared.debug("📡 [Reload] TCP reload failed: \(tcpResult.errorMessage ?? "Unknown error")")
            // Fall back to service restart
            AppLogger.shared.warn("⚠️ [Reload] Falling back to service restart")
            await restartKanata()
            // After a successful restart, clear stale diagnostics
            clearDiagnostics()
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
            AppLogger.shared.debug("🧪 [TCP Reload] Skipping TCP reload in test environment")
            return .networkError("Test environment - TCP disabled")
        }

        AppLogger.shared.log("📡 [TCP Reload] Triggering config reload via EngineClient (TCP)")
        let res = await engineClient.reloadConfig()
        return mapEngineToTCP(res)
    }

    private func mapEngineToTCP(_ result: EngineReloadResult) -> TCPReloadResult {
        switch result {
        case let .success(response: resp): .success(response: resp)
        case let .failure(error: err, response: resp): .failure(error: err, response: resp)
        case .authenticationRequired: .authenticationRequired
        case let .networkError(err): .networkError(err)
        }
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        let result = await triggerConfigReload()
        if !result.isSuccess {
            AppLogger.shared.info("🔄 [Reload] Falling back to service restart due to error: \(result.errorMessage ?? "Unknown")")
            await restartKanata()
        }
    }
}

// MARK: - Result Types

/// TCP reload result
struct ReloadResult {
    let success: Bool
    let response: String?
    let errorMessage: String?
    let `protocol`: CommunicationProtocol?

    var isSuccess: Bool { success }
}
