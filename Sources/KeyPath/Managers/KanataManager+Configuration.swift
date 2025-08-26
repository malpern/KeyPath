import ApplicationServices
import Foundation
import IOKit.hidsystem
import Network
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
                    "📡 [Validation] UDP validation unavailable, trying TCP fallback")
            }
        }

        // Try TCP validation as fallback if enabled and Kanata is running
        if commConfig.shouldUseTCP, isRunning {
            AppLogger.shared.log("🌐 [Validation] Attempting TCP validation (fallback)")
            if let tcpResult = await configurationService.validateConfigViaTCP() {
                return tcpResult
            } else {
                AppLogger.shared.log(
                    "🌐 [Validation] TCP validation unavailable, falling back to file-based validation")
            }
        }

        // Fallback to traditional file-based validation
        AppLogger.shared.log("📄 [Validation] Using file-based validation")
        return configurationService.validateConfigViaFile()
    }

    // MARK: - Hot Reload via UDP/TCP

    /// Main reload method that uses the preferred protocol (UDP or TCP)
    func triggerConfigReload() async -> ReloadResult {
        let commConfig = PreferencesService.communicationSnapshot()

        // Try UDP first if it's the preferred protocol
        if commConfig.shouldUseUDP {
            AppLogger.shared.log("📡 [Reload] Attempting UDP reload (preferred)")
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
                // Fall back to TCP if available
            }
        }

        // Try TCP as fallback or if it's the preferred protocol
        if commConfig.shouldUseTCP {
            AppLogger.shared.log("🌐 [Reload] Attempting TCP reload \(commConfig.shouldUseUDP ? "(fallback)" : "(preferred)")")
            let tcpResult = await triggerTCPReloadWithErrorCapture()

            return ReloadResult(
                success: tcpResult.success,
                response: "TCP reload completed",
                errorMessage: tcpResult.errorMessage,
                protocol: .tcp
            )
        }

        // If no protocol is available, fall back to service restart
        AppLogger.shared.log("⚠️ [Reload] No communication protocol available - falling back to service restart")
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

    /// TCP-based config reload (backward compatibility)
    func triggerTCPReloadWithErrorCapture() async -> TCPReloadResult {
        let commConfig = PreferencesService.communicationSnapshot()
        guard commConfig.shouldUseTCP else {
            AppLogger.shared.log("⚠️ [TCP Reload] TCP server not enabled - falling back to service restart")
            await restartKanata()
            return .success(response: "Service restarted (TCP disabled)")
        }

        AppLogger.shared.log("🌐 [TCP Reload] Triggering config reload via TCP on port \(commConfig.tcpPort)")

        let client = KanataTCPClient(port: commConfig.tcpPort)

        // Check if TCP server is available
        guard await client.checkServerStatus() else {
            AppLogger.shared.log("❌ [TCP Reload] TCP server not available - falling back to service restart")
            await restartKanata()
            return .success(response: "Service restarted (TCP unavailable)")
        }

        do {
            // Send reload command as JSON
            let reloadCommand = #"{"Reload":{}}"#
            let commandData = reloadCommand.data(using: .utf8)!

            // Use low-level TCP to send reload command
            let responseData = try await sendTCPCommand(commandData, port: commConfig.tcpPort)
            let responseString = String(data: responseData, encoding: .utf8) ?? ""

            AppLogger.shared.log("🌐 [TCP Reload] Server response (\(responseData.count) bytes): \(responseString)")
            AppLogger.shared.log("🔍 [TCP Reload] Checking for success patterns...")
            AppLogger.shared.log("🔍 [TCP Reload] Contains 'status:Ok': \(responseString.contains("\"status\":\"Ok\""))")
            AppLogger.shared.log("🔍 [TCP Reload] Contains 'Live reload successful': \(responseString.contains("Live reload successful"))")

            // Parse response for success/failure
            if responseString.contains("\"status\":\"Ok\"") || responseString.contains("Live reload successful") {
                AppLogger.shared.log("✅ [TCP Reload] Config reload successful")
                return .success(response: responseString)
            } else if responseString.contains("\"status\":\"Error\"") {
                // Extract error message from Kanata response
                let errorMsg = extractErrorFromKanataResponse(responseString)
                AppLogger.shared.log("❌ [TCP Reload] Config reload failed: \(errorMsg)")
                return .failure(error: errorMsg, response: responseString)
            } else {
                AppLogger.shared.log("⚠️ [TCP Reload] Unexpected response - treating as failure")
                return .failure(error: "Unexpected response format", response: responseString)
            }

        } catch {
            AppLogger.shared.log("❌ [TCP Reload] Failed to send reload command: \(error)")
            return .failure(error: "TCP communication failed: \(error.localizedDescription)")
        }
    }

    /// Extract error message from Kanata's JSON response
    private func extractErrorFromKanataResponse(_ response: String) -> String {
        // Parse JSON response to extract error message
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["msg"] as? String {
            return msg
        }
        return "Unknown error from Kanata"
    }

    /// Legacy method for backward compatibility
    func triggerTCPReload() async {
        let result = await triggerTCPReloadWithErrorCapture()
        if !result.success {
            AppLogger.shared.log("🔄 [TCP Reload] Falling back to service restart due to error: \(result.errorMessage ?? "Unknown")")
            await restartKanata()
        }
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        let result = await triggerConfigReload()
        if !result.isSuccess {
            AppLogger.shared.log("🔄 [Reload] Falling back to service restart due to error: \(result.errorMessage ?? "Unknown")")
            await restartKanata()
        }
    }

    /// Send raw TCP command to Kanata server
    private func sendTCPCommand(_ data: Data, port: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "kanata-tcp-reload")

            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(throwing: TCPError.invalidPort)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host("127.0.0.1"),
                port: nwPort,
                using: .tcp
            )

            var hasResumed = false

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send the reload command
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(throwing: error)
                            }
                            return
                        }

                        // Receive the response - accumulate all data from multiple responses
                        var accumulatedData = Data()

                        func receiveMoreData() {
                            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { responseData, _, isComplete, error in
                                if let error {
                                    connection.cancel()
                                    if !hasResumed {
                                        hasResumed = true
                                        continuation.resume(throwing: error)
                                    }
                                    return
                                }

                                if let responseData {
                                    accumulatedData.append(responseData)
                                }

                                // Check if we have both responses (LayerChange + status)
                                let responseString = String(data: accumulatedData, encoding: .utf8) ?? ""
                                let hasLayerChange = responseString.contains("LayerChange")
                                let hasStatus = responseString.contains("status")

                                if (hasLayerChange && hasStatus) || accumulatedData.count > 1024 || isComplete {
                                    // We have both responses or connection complete
                                    connection.cancel()
                                    if !hasResumed {
                                        hasResumed = true
                                        continuation.resume(returning: accumulatedData)
                                    }
                                } else {
                                    // Continue receiving more data
                                    receiveMoreData()
                                }
                            }
                        }

                        receiveMoreData()
                    })
                case let .failed(error):
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout after 10 seconds
            queue.asyncAfter(deadline: .now() + 10) {
                if !hasResumed {
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: TCPError.timeout)
                }
            }
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

/// Unified reload result that works with both UDP and TCP
struct ReloadResult {
    let success: Bool
    let response: String?
    let errorMessage: String?
    let `protocol`: CommunicationProtocol?

    var isSuccess: Bool { success }
}

/// TCP reload result (backward compatibility)
enum TCPReloadResult {
    case success(response: String)
    case failure(error: String, response: String)

    var success: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    var response: String? {
        switch self {
        case let .success(response: response):
            return response
        case .failure(error: _, response: let response):
            return response
        }
    }

    var errorMessage: String? {
        switch self {
        case .success:
            return nil
        case .failure(error: let error, response: _):
            return error
        }
    }
}
