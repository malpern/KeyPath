import ApplicationServices
import Foundation
import IOKit.hidsystem
import SwiftUI

// MARK: - KanataManager Configuration Extension

extension KanataManager {
    // MARK: - Configuration Initialization

    func createInitialConfigIfNeeded() async {
        do {
            try await configurationManager.createInitialConfigIfNeeded()
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

        // Try TCP validation first if enabled and Kanata is running
        let commConfig = PreferencesService.communicationSnapshot()
        if commConfig.shouldUseTCP, isRunning {
            AppLogger.shared.log("📡 [Validation] Attempting TCP validation")
            if let tcpResult = await configurationManager.validateTCP() {
                return tcpResult
            } else {
                AppLogger.shared.log(
                    "📡 [Validation] TCP validation unavailable, falling back to file-based validation")
            }
        }

        // Fallback to traditional file-based validation
        AppLogger.shared.log("📄 [Validation] Using file-based validation")
        return configurationManager.validateFile()
    }

    // MARK: - Hot Reload via TCP

    /// Main reload method using TCP protocol
    func triggerConfigReload() async -> ReloadResult {
        let commConfig = PreferencesService.communicationSnapshot()

        // Try TCP reload
        if commConfig.shouldUseTCP {
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
            }
        }

        // If TCP is not available, fall back to service restart
        AppLogger.shared.log("⚠️ [Reload] TCP communication not available - falling back to service restart")
        await restartKanata()
        return ReloadResult(
            success: true,
            response: "Service restarted (no protocol available)",
            errorMessage: nil,
            protocol: nil
        )
    }

    /// TCP-based config reload using secure actor-based client
    func triggerTCPReload() async -> TCPReloadResult {
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [TCP Reload] Skipping TCP reload in test environment")
            return .networkError("Test environment - TCP disabled")
        }
        let commConfig = PreferencesService.communicationSnapshot()
        guard commConfig.shouldUseTCP else {
            AppLogger.shared.log("⚠️ [TCP Reload] TCP server not enabled - skipping")
            return .networkError("TCP server not enabled")
        }

        AppLogger.shared.log("📡 [TCP Reload] Triggering config reload via TCP on port \(commConfig.tcpPort)")

        // Ensure TCP client exists (should have been created during validation)
        if tcpClient == nil {
            tcpClient = KanataTCPClient(port: commConfig.tcpPort)
        }
        let client = tcpClient!

        // Get secure token from Keychain
        let secureToken: String
        do {
            secureToken = try await MainActor.run {
                try KeychainService.shared.retrieveTCPToken()
            } ?? ""
        } catch {
            AppLogger.shared.log("❌ [TCP Reload] Failed to retrieve secure token: \(error)")
            return .authenticationRequired
        }

        // Try auto-generated token if no stored token
        let authToken = secureToken.isEmpty ? await getGeneratedTCPToken() : secureToken
        guard let token = authToken, await client.authenticate(token: token) else {
            AppLogger.shared.log("❌ [TCP Reload] Authentication failed")
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

    /// Get the auto-generated TCP token from Kanata logs
    /// Returns nil if token not found or server not running
    private func getGeneratedTCPToken() async -> String? {
        AppLogger.shared.log("🔍 [TCP Token] Searching for auto-generated token in logs...")

        // Check if Kanata is running with TCP server
        guard isRunning else {
            AppLogger.shared.log("⚠️ [TCP Token] Kanata not running - cannot extract token")
            return nil
        }

        // Try to read the log file for auto-generated token
        let logPath = "/var/log/kanata.log"
        guard FileManager.default.fileExists(atPath: logPath) else {
            AppLogger.shared.log("⚠️ [TCP Token] Log file not found at \(logPath)")
            return nil
        }

        do {
            let logContent = try String(contentsOfFile: logPath)

            // Look for the pattern: "TCP auth token: <token>"
            // Token is base64-style with uppercase, lowercase, and digits
            let pattern = #"TCP auth token: ([A-Za-z0-9+/=]+)"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(logContent.startIndex..., in: logContent)

            if let match = regex.firstMatch(in: logContent, options: [], range: range),
               let tokenRange = Range(match.range(at: 1), in: logContent) {
                let token = String(logContent[tokenRange])
                AppLogger.shared.log("✅ [TCP Token] Found auto-generated token")

                // Store the discovered token securely
                try await MainActor.run {
                    try KeychainService.shared.storeTCPToken(token)
                }

                return token
            } else {
                AppLogger.shared.log("⚠️ [TCP Token] No auto-generated token found in logs")
                return nil
            }
        } catch {
            AppLogger.shared.log("❌ [TCP Token] Failed to read log file: \(error)")
            return nil
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
