import Foundation
import KeyPathCore

extension ConfigurationService {
    // MARK: - Validation

    /// Validate configuration via file-based check
    public func validateConfigViaFile() async -> (isValid: Bool, errors: [String]) {
        if TestEnvironment.isTestMode {
            AppLogger.shared.log("🧪 [ConfigService] Test mode: Skipping file validation")
            return (true, [])
        }

        let binaryPath = WizardSystemPaths.kanataActiveBinary
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            let message = "Kanata binary missing at \(binaryPath)"
            AppLogger.shared.log("❌ [ConfigService] File validation skipped: \(message)")
            return (false, [message])
        }

        var errors: [String] = []

        do {
            let result = try await SubprocessRunner.shared.run(
                binaryPath,
                args: buildKanataArguments(checkOnly: true),
                timeout: 30
            )
            let output = result.stdout + result.stderr

            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [ConfigService] File validation passed")
                return (true, [])
            } else {
                // Parse errors from output
                let lines = output.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty && (line.contains("error") || line.contains("Error")) {
                    errors.append(line.trimmingCharacters(in: .whitespaces))
                }

                if errors.isEmpty {
                    errors.append("Configuration validation failed (exit code: \(result.exitCode))")
                }

                AppLogger.shared.log("❌ [ConfigService] File validation failed: \(errors)")
                notifyValidationFailure(errors, context: "file")
                return (false, errors)
            }

        } catch {
            AppLogger.shared.log("❌ [ConfigService] File validation error: \(error)")
            notifyValidationFailure(
                ["Failed to validate configuration file: \(error.localizedDescription)"],
                context: "file"
            )
            return (false, ["Failed to validate configuration file: \(error.localizedDescription)"])
        }
    }

    /// Validate configuration content using CLI (kanata --check)
    ///
    /// Note: TCP validation was removed because our Kanata fork doesn't support
    /// the Validate command over TCP. CLI validation is more thorough anyway.
    public func validateConfiguration(_ config: String) async -> (isValid: Bool, errors: [String]) {
        AppLogger.shared.log("🔍 [Validation] ========== CONFIG VALIDATION START ==========")
        AppLogger.shared.log("🔍 [Validation] Config size: \(config.count) characters")

        if TestEnvironment.isTestMode {
            AppLogger.shared.log("🧪 [Validation] Test mode detected – using lightweight validation")
            let result = validateConfigurationInTestMode(config)
            AppLogger.shared.log("🔍 [Validation] ========== CONFIG VALIDATION END ==========")
            return result
        }

        // Use CLI validation (kanata --check)
        let cliResult = await validateConfigWithCLI(config)
        AppLogger.shared.log("🔍 [Validation] ========== CONFIG VALIDATION END ==========")
        return cliResult
    }

    /// Parse Kanata error output to extract error messages
    /// Kanata uses miette for rich error formatting, which outputs:
    /// - [ERROR] line with brief description
    /// - Code context with arrows pointing to the error
    /// - "help:" line with actionable description (e.g., "Unknown key in defsrc: \"hangeul\"")
    public func parseKanataErrors(_ output: String) -> [String] {
        var errors: [String] = []
        let lines = output.components(separatedBy: .newlines)

        // Extract [ERROR] lines
        for line in lines where line.contains("[ERROR]") {
            if let errorRange = line.range(of: "[ERROR]") {
                let errorMessage = String(line[errorRange.upperBound...]).trimmingCharacters(
                    in: .whitespaces)
                errors.append(errorMessage)
            }
        }

        // Also extract "help:" lines - these contain the most actionable information
        // e.g., "help: Unknown key in defsrc: \"hangeul\""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("help:") {
                let helpMessage = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !helpMessage.isEmpty {
                    errors.append("💡 \(helpMessage)")
                }
            }
        }

        // Don't return empty strings - if no specific errors found and output is empty/whitespace,
        // return empty array instead of an array with empty string
        if errors.isEmpty {
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOutput.isEmpty {
                // If there's non-empty output but no [ERROR] tags, include the full output as error
                errors.append(trimmedOutput)
            }
        }

        return errors
    }

    /// Validate configuration via CLI (kanata --check)
    private func validateConfigWithCLI(_ config: String) async -> (isValid: Bool, errors: [String]) {
        AppLogger.shared.log("🖥️ [Validation-CLI] Starting CLI validation process...")
        let keepFailedConfig =
            ProcessInfo.processInfo.environment["KEYPATH_KEEP_FAILED_CONFIG"] == "1"

        // Write config to a unique temporary file for validation (UUID prevents race conditions)
        let uniqueID = UUID().uuidString.prefix(8)
        let tempConfigPath = "\(configDirectory)/temp_validation_\(uniqueID).kbd"
        AppLogger.shared.log("📝 [Validation-CLI] Creating temp config file: \(tempConfigPath)")

        do {
            let tempConfigURL = URL(fileURLWithPath: tempConfigPath)
            let configDir = URL(fileURLWithPath: configDirectory)
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try await writeFileURLAsync(string: config, to: tempConfigURL)
            AppLogger.shared.log(
                "📝 [Validation-CLI] Temp config written successfully (\(config.count) characters)")

            // Use kanata --check to validate
            let kanataBinary = WizardSystemPaths.kanataActiveBinary
            AppLogger.shared.log("🔧 [Validation-CLI] Using kanata binary: \(kanataBinary)")

            guard FileManager.default.isExecutableFile(atPath: kanataBinary) else {
                let message = "Kanata binary missing at \(kanataBinary)"
                AppLogger.shared.log("❌ [Validation-CLI] \(message)")
                if TestEnvironment.isTestMode {
                    AppLogger.shared.log("🧪 [Validation-CLI] Skipping CLI validation in tests")
                    try? FileManager.default.removeItem(at: tempConfigURL)
                    return (true, [])
                }
                try? FileManager.default.removeItem(at: tempConfigURL)
                return (false, [message])
            }

            let arguments = ["--cfg", tempConfigPath, "--check"]
            AppLogger.shared.log(
                "🔧 [Validation-CLI] Command: \(kanataBinary) \(arguments.joined(separator: " "))")

            let cliStart = Date()
            let result = try await SubprocessRunner.shared.run(
                kanataBinary,
                args: arguments,
                timeout: 30
            )
            let cliDuration = Date().timeIntervalSince(cliStart)
            AppLogger.shared.log(
                "⏱️ [Validation-CLI] CLI validation completed in \(String(format: "%.3f", cliDuration)) seconds"
            )

            let output = result.stdout + result.stderr

            AppLogger.shared.log("📋 [Validation-CLI] Exit code: \(result.exitCode)")
            if !output.isEmpty {
                AppLogger.shared.log("📋 [Validation-CLI] Output: \(output.prefix(500))...")
            }

            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [Validation-CLI] CLI validation PASSED")
                try? FileManager.default.removeItem(at: tempConfigURL)
                return (true, [])
            } else {
                let errors = parseKanataErrors(output)
                notifyValidationFailure(errors, context: "cli")
                if keepFailedConfig {
                    AppLogger.shared.log(
                        "🧪 [Validation-CLI] Keeping temp config for debugging at \(tempConfigPath)"
                    )
                } else {
                    try? FileManager.default.removeItem(at: tempConfigURL)
                }
                AppLogger.shared.log(
                    "❌ [Validation-CLI] CLI validation FAILED with \(errors.count) errors:")
                for (index, error) in errors.enumerated() {
                    AppLogger.shared.log("   Error \(index + 1): \(error)")
                }
                return (false, errors)
            }
        } catch {
            // Clean up temp file on error
            if keepFailedConfig {
                AppLogger.shared.log(
                    "🧪 [Validation-CLI] Keeping temp config for debugging at \(tempConfigPath)"
                )
            } else {
                try? FileManager.default.removeItem(atPath: tempConfigPath)
            }
            AppLogger.shared.log("❌ [Validation-CLI] Validation process failed: \(error)")
            AppLogger.shared.log("❌ [Validation-CLI] Error type: \(type(of: error))")
            notifyValidationFailure(
                ["Validation failed: \(error.localizedDescription)"],
                context: "cli"
            )
            return (false, ["Validation failed: \(error.localizedDescription)"])
        }
    }

    private func validateConfigurationInTestMode(_ config: String) -> (
        isValid: Bool, errors: [String]
    ) {
        guard !config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, ["Configuration content is empty"])
        }

        do {
            _ = try parseConfigurationFromString(config)
            return (true, [])
        } catch {
            return (false, ["Mock validation failed: \(error.localizedDescription)"])
        }
    }

    private func notifyValidationFailure(_ errors: [String], context: String) {
        guard !errors.isEmpty, !TestEnvironment.isRunningTests else { return }
        NotificationCenter.default.post(
            name: .configValidationFailed,
            object: nil,
            userInfo: [
                "errors": errors,
                "context": context
            ]
        )
    }

    private func buildKanataArguments(checkOnly: Bool = false) -> [String] {
        var args = ["--cfg", configurationPath]
        if checkOnly {
            args.append("--check")
        }

        // Add TCP port argument for actual runs (not validation checks)
        if !checkOnly {
            let tcpPort = PreferencesService.shared.tcpServerPort
            args.append(contentsOf: ["--port", "\(tcpPort)"])
            AppLogger.shared.log("📡 [ConfigService] Added TCP port argument: --port \(tcpPort)")
        }

        return args
    }
}
