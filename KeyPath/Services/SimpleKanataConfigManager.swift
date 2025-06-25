import Foundation

/// Simple Kanata configuration manager following Karabiner-Elements pattern
/// Individual rules are complete, self-contained configs that get concatenated
class SimpleKanataConfigManager {
    private let llmProvider: AnthropicModelProvider?
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    
    init(llmProvider: AnthropicModelProvider? = nil) {
        self.llmProvider = llmProvider
    }

    /// Generate complete Kanata configuration from individual rules
    func generateConfig(with activeRules: [KanataRule]) throws -> String {
        let baseConfig = """
        ;; KeyPath Generated Kanata Configuration
        ;; This file was automatically created by KeyPath

        (defcfg
          process-unmapped-keys yes
          live-reload-file \(configPath)
        )

        """

        // Simply concatenate all active rules
        let rulesConfig = activeRules.map { rule in
            """
            ;; Rule: \(rule.explanation)
            \(rule.completeKanataConfig)
            """
        }.joined(separator: "\n\n")

        return baseConfig + "\n" + rulesConfig
    }

    /// Write the complete configuration to file
    func writeConfig(_ config: String) throws {
        // Ensure the directory exists
        let configDir = NSString(string: configPath).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        // Create backup if file exists
        if FileManager.default.fileExists(atPath: configPath) {
            let backupPath = "\(configPath).keypath-backup-\(Date().timeIntervalSince1970)"
            try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
        }

        // Write new config
        try config.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Generate and write config for active rules
    func updateConfig(with activeRules: [KanataRule]) throws {
        let config = try generateConfig(with: activeRules)
        try writeConfig(config)
    }

    /// Validate configuration using Kanata binary (if available)
    func validateConfig(_ config: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let validator = KanataConfigValidator(llmProvider: llmProvider)

        // Create a temporary file with the complete config
        let tempFile = NSTemporaryDirectory() + "kanata_validate_\(UUID().uuidString).kbd"

        do {
            try config.write(toFile: tempFile, atomically: true, encoding: .utf8)

            // Use existing validator to check the complete config
            validator.validateConfigFile(tempFile) { result in
                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempFile)

                // Convert KanataValidationError to Error
                switch result {
                case .success(let value):
                    completion(.success(value))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
}

// MARK: - KanataConfigValidator Extension

extension KanataConfigValidator {
    /// Validate a complete config file
    func validateConfigFile(_ filePath: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        let executableFinder = KanataExecutableFinder()

        // Find kanata executable
        guard let kanataPath = executableFinder.findKanataPath() else {
            completion(.failure(.kanataNotFound))
            return
        }

        // Run kanata --check
        let task = Process()
        task.executableURL = URL(fileURLWithPath: kanataPath)
        task.arguments = ["--check", "--cfg", filePath]

        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe

        task.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"

            if process.terminationStatus == 0 {
                completion(.success(true))
            } else {
                completion(.failure(.validationFailed(output)))
            }
        }

        do {
            try task.run()
        } catch {
            completion(.failure(.validationFailed(error.localizedDescription)))
        }
    }
}
