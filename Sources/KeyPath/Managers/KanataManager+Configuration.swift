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

        // Try TCP validation first if enabled and Kanata is running
        let tcpConfig = PreferencesService.tcpSnapshot()
        if tcpConfig.shouldUseTCPServer, isRunning {
            AppLogger.shared.log("🌐 [Validation] Attempting TCP validation")
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

    // MARK: - Hot Reload via TCP

    func triggerTCPReloadWithErrorCapture() async -> TCPReloadResult {
        let tcpConfig = PreferencesService.tcpSnapshot()
        guard tcpConfig.shouldUseTCPServer else {
            AppLogger.shared.log("⚠️ [TCP Reload] TCP server not enabled - falling back to service restart")
            await restartKanata()
            return .success(response: "Service restarted (TCP disabled)")
        }

        AppLogger.shared.log("🌐 [TCP Reload] Triggering config reload via TCP on port \(tcpConfig.port)")

        let client = KanataTCPClient(port: tcpConfig.port)

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
            let responseData = try await sendTCPCommand(commandData, port: tcpConfig.port)
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
}
