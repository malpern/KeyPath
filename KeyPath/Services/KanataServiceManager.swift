import Foundation

class KanataServiceManager {
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    private let fileManager = FileManager.default
    private let executableFinder = KanataExecutableFinder()

    func installRule(_ rule: KanataRule, completion: @escaping (Result<String, KanataValidationError>) -> Void) {
        print("🐛 DEBUG: KanataServiceManager.installRule called")
        print("🐛 DEBUG: Rule received: \(rule)")
        print("🐛 DEBUG: Rule.kanataRule: '\(rule.kanataRule)'")
        print("🐛 DEBUG: Config path: \(configPath)")
        
        // Check for Karabiner conflict first
        if executableFinder.isKarabinerRunning() {
            print("🐛 DEBUG: Karabiner conflict detected, aborting")
            completion(.failure(.karabinerConflict))
            return
        }

        do {
            // Read existing config
            print("🐛 DEBUG: Attempting to read existing config...")
            let existingConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            print("🐛 DEBUG: Successfully read existing config (\(existingConfig.count) characters)")
            print("🐛 DEBUG: Existing config preview: \(String(existingConfig.prefix(200)))...")

            // Parse current config
            print("🐛 DEBUG: Creating KanataConfigManager and parsing config...")
            let configManager = KanataConfigManager()
            var parsedConfig = configManager.parseConfig(existingConfig)
            print("🐛 DEBUG: Parsed config - defsrc: \(parsedConfig.defsrc)")
            print("🐛 DEBUG: Parsed config - deflayer keys: \(parsedConfig.deflayer.keys)")
            print("🐛 DEBUG: Parsed config - deflayer default: \(parsedConfig.deflayer["default"] ?? [])")

            // Add the new rule using the kanata rule (simple format like "a -> b")
            print("🐛 DEBUG: Adding simple mapping: '\(rule.kanataRule)'")
            configManager.addSimpleMapping(rule.kanataRule, to: &parsedConfig)
            print("🐛 DEBUG: After adding mapping - defsrc: \(parsedConfig.defsrc)")
            print("🐛 DEBUG: After adding mapping - deflayer default: \(parsedConfig.deflayer["default"] ?? [])")

            // Generate new config
            print("🐛 DEBUG: Generating new config...")
            let newConfig = configManager.generateConfig(parsedConfig)
            print("🐛 DEBUG: Generated new config (\(newConfig.count) characters)")
            print("🐛 DEBUG: New config preview:")
            print("🐛 DEBUG: \(String(newConfig.prefix(500)))")

            // Create backup
            let backupPath = configPath + ".keypath-backup-\(Date().timeIntervalSince1970)"
            print("🐛 DEBUG: Creating backup at: \(backupPath)")
            try fileManager.copyItem(atPath: configPath, toPath: backupPath)
            print("🐛 DEBUG: Backup created successfully")

            // Write new config
            print("🐛 DEBUG: Writing new config to: \(configPath)")
            try newConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            print("🐛 DEBUG: New config written successfully")
            
            // Verify the write
            let verifyConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            print("🐛 DEBUG: Verification read (\(verifyConfig.count) characters)")
            print("🐛 DEBUG: Config contains '5': \(verifyConfig.contains("5"))")
            print("🐛 DEBUG: Config contains '6': \(verifyConfig.contains("6"))")

            // For now, skip kanata reload since it requires service management
            // TODO: Implement proper service management as per installerPlan.md
            print("🐛 DEBUG: Installation completed successfully")
            completion(.success(backupPath))
        } catch {
            print("🐛 DEBUG: Installation failed with error: \(error)")
            completion(.failure(.writeFailed(error.localizedDescription)))
        }
    }

    func reloadKanata(completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        guard let kanataPath = executableFinder.findKanataPath() else {
            completion(.failure(.kanataNotFound))
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["sudo", kanataPath, "--reload"]

        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe

        task.terminationHandler = { process in
            if process.terminationStatus == 0 {
                completion(.success(true))
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                completion(.failure(.reloadFailed(output)))
            }
        }

        do {
            try task.run()
        } catch {
            completion(.failure(.reloadFailed(error.localizedDescription)))
        }
    }

    func getCurrentConfig() -> String? {
        return try? String(contentsOfFile: configPath, encoding: .utf8)
    }

    func undoLastRule(backupPath: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        do {
            // Restore the backup
            try fileManager.removeItem(atPath: configPath)
            try fileManager.copyItem(atPath: backupPath, toPath: configPath)

            // For now, skip kanata reload since it requires service management
            // TODO: Implement proper service management as per installerPlan.md
            // Clean up the backup file
            try? self.fileManager.removeItem(atPath: backupPath)
            completion(.success(true))
        } catch {
            completion(.failure(.writeFailed("Failed to restore backup: \(error.localizedDescription)")))
        }
    }
}
