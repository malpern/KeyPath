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

        // Try UDP validation first if enabled and Kanata is running
        let commConfig = PreferencesService.communicationSnapshot()
        if commConfig.shouldUseUDP, isRunning {
            AppLogger.shared.log("📡 [Validation] Attempting UDP validation")
            if let udpResult = await configurationService.validateConfigViaUDP() {
                return udpResult
            } else {
                AppLogger.shared.log(
                    "📡 [Validation] UDP validation unavailable, falling back to file-based validation")
            }
        }

        // Fallback to traditional file-based validation
        AppLogger.shared.log("📄 [Validation] Using file-based validation")
        return configurationService.validateConfigViaFile()
    }

    // MARK: - Hot Reload via UDP

    /// Main reload method using UDP protocol
    func triggerConfigReload() async -> ReloadResult {
        let commConfig = PreferencesService.communicationSnapshot()

        // Try UDP reload
        if commConfig.shouldUseUDP {
            AppLogger.shared.log("📡 [Reload] Attempting UDP reload")
            let udpResult = await triggerUDPReload()
            if udpResult.isSuccess {
                return ReloadResult(
                    success: true,
                    response: udpResult.response ?? "",
                    errorMessage: nil,
                    protocol: .udp
                )
            } else {
                AppLogger.shared.log("📡 [Reload] UDP reload failed: \(udpResult.errorMessage ?? "Unknown error")")
            }
        }

        // If UDP is not available, fall back to service restart
        AppLogger.shared.log("⚠️ [Reload] UDP communication not available - falling back to service restart")
        await restartKanata()
        return ReloadResult(
            success: true,
            response: "Service restarted (no protocol available)",
            errorMessage: nil,
            protocol: nil
        )
    }

    /// UDP-based config reload using secure actor-based client
    func triggerUDPReload() async -> UDPReloadResult {
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [UDP Reload] Skipping UDP reload in test environment")
            return .networkError("Test environment - UDP disabled")
        }
        let commConfig = PreferencesService.communicationSnapshot()
        guard commConfig.shouldUseUDP else {
            AppLogger.shared.log("⚠️ [UDP Reload] UDP server not enabled - skipping")
            return .networkError("UDP server not enabled")
        }

        AppLogger.shared.log("📡 [UDP Reload] Triggering config reload via UDP on port \(commConfig.udpPort)")

        let client = KanataUDPClient(port: commConfig.udpPort)

        // Get secure token from Keychain
        let secureToken: String
        do {
            secureToken = try await MainActor.run {
                try KeychainService.shared.retrieveUDPToken()
            } ?? ""
        } catch {
            AppLogger.shared.log("❌ [UDP Reload] Failed to retrieve secure token: \(error)")
            return .authenticationRequired
        }

        // Try auto-generated token if no stored token
        let authToken = secureToken.isEmpty ? await getGeneratedUDPToken() : secureToken
        guard let token = authToken, await client.authenticate(token: token) else {
            AppLogger.shared.log("❌ [UDP Reload] Authentication failed")
            return .authenticationRequired
        }

        return await client.reloadConfig()
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        let result = await triggerConfigReload()
        if !result.isSuccess {
            AppLogger.shared.log("🔄 [Reload] Falling back to service restart due to error: \(result.errorMessage ?? "Unknown")")
            await restartKanata()
        }
    }

    // MARK: - Helper Methods

    /// Get the auto-generated UDP token from Kanata logs
    /// Returns nil if token not found or server not running
    private func getGeneratedUDPToken() async -> String? {
        AppLogger.shared.log("🔍 [UDP Token] Searching for auto-generated token in logs...")

        // Check if Kanata is running with UDP server
        guard isRunning else {
            AppLogger.shared.log("⚠️ [UDP Token] Kanata not running - cannot extract token")
            return nil
        }

        // Try to read the log file for auto-generated token
        let logPath = "/var/log/kanata.log"
        guard FileManager.default.fileExists(atPath: logPath) else {
            AppLogger.shared.log("⚠️ [UDP Token] Log file not found at \(logPath)")
            return nil
        }

        do {
            let logContent = try String(contentsOfFile: logPath)

            // Look for the pattern: "UDP auth token: <token>"
            let pattern = #"UDP auth token: ([a-f0-9]+)"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(logContent.startIndex..., in: logContent)

            if let match = regex.firstMatch(in: logContent, options: [], range: range),
               let tokenRange = Range(match.range(at: 1), in: logContent) {
                let token = String(logContent[tokenRange])
                AppLogger.shared.log("✅ [UDP Token] Found auto-generated token")

                // Store the discovered token securely
                try await MainActor.run {
                    try KeychainService.shared.storeUDPToken(token)
                }

                return token
            } else {
                AppLogger.shared.log("⚠️ [UDP Token] No auto-generated token found in logs")
                return nil
            }
        } catch {
            AppLogger.shared.log("❌ [UDP Token] Failed to read log file: \(error)")
            return nil
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
