import Foundation

class KanataServiceManager {
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    private let fileManager = FileManager.default
    private let executableFinder = KanataExecutableFinder()
    
    func installRule(_ rule: KanataRule, completion: @escaping (Result<String, KanataValidationError>) -> Void) {
        // Check for Karabiner conflict first
        if executableFinder.isKarabinerRunning() {
            completion(.failure(.karabinerConflict))
            return
        }

        do {
            // Read existing config
            let existingConfig = try String(contentsOfFile: configPath, encoding: .utf8)

            // Parse current config
            let configManager = KanataConfigManager()
            var parsedConfig = configManager.parseConfig(existingConfig)

            // Add the new rule using the complete configuration
            configManager.addSimpleMapping(rule.completeKanataConfig, to: &parsedConfig)

            // Generate new config
            let newConfig = configManager.generateConfig(parsedConfig)

            // Create backup
            let backupPath = configPath + ".keypath-backup-\(Date().timeIntervalSince1970)"
            try fileManager.copyItem(atPath: configPath, toPath: backupPath)

            // Write new config
            try newConfig.write(toFile: configPath, atomically: true, encoding: .utf8)

            // For now, skip kanata reload since it requires service management
            // TODO: Implement proper service management as per installerPlan.md
            completion(.success(backupPath))
        } catch {
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