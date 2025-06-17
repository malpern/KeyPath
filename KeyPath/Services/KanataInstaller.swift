import Foundation

class KanataInstaller {
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    private let fileManager = FileManager.default
    
    // Find kanata executable in common locations
    private func findKanataPath() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/kanata",
            "/usr/local/bin/kanata",
            "/usr/bin/kanata"
        ]
        
        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                print("Kanata found at: \(path)")
                return path
            }
        }
        
        // Try using which command as fallback
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "kanata"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    print("Kanata found via which: \(path)")
                    return path
                }
            }
        } catch {
            print("Failed to run which command: \(error)")
        }
        
        return nil
    }
    
    enum InstallError: Error, LocalizedError {
        case configDirectoryNotFound
        case configFileNotFound
        case kanataNotFound
        case validationFailed(String)
        case writeFailed(String)
        case reloadFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .configDirectoryNotFound:
                return "Kanata configuration directory not found at ~/.config/kanata/"
            case .configFileNotFound:
                return "Kanata configuration file not found at ~/.config/kanata/kanata.kbd"
            case .kanataNotFound:
                return "Kanata executable not found. Please install Kanata using 'brew install kanata' or download from GitHub."
            case .validationFailed(let message):
                return "Rule validation failed: \(message)"
            case .writeFailed(let message):
                return "Failed to write configuration: \(message)"
            case .reloadFailed(let message):
                return "Failed to reload Kanata: \(message)"
            }
        }
    }
    
    // Check if Kanata is installed and config exists (create if needed)
    func checkKanataSetup() -> Result<Bool, InstallError> {
        let configDir = (configPath as NSString).deletingLastPathComponent
        
        // Create config directory if it doesn't exist
        if !fileManager.fileExists(atPath: configDir) {
            do {
                try fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
                print("Created Kanata config directory: \(configDir)")
            } catch {
                return .failure(.configDirectoryNotFound)
            }
        }
        
        // Create config file if it doesn't exist
        if !fileManager.fileExists(atPath: configPath) {
            let defaultConfig = """
            ;; KeyPath Generated Kanata Configuration
            ;; This file was automatically created by KeyPath
            
            (defcfg
              process-unmapped-keys yes
            )
            
            ;; KeyPath rules will be added below
            """
            
            do {
                try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
                print("Created default Kanata config: \(configPath)")
            } catch {
                return .failure(.configFileNotFound)
            }
        }
        
        return .success(true)
    }
    
    // Validate a rule using kanata --check
    func validateRule(_ rule: String, completion: @escaping (Result<Bool, InstallError>) -> Void) {
        // Create a temporary file with the rule
        let tempFile = NSTemporaryDirectory() + "kanata_test_\(UUID().uuidString).kbd"
        
        do {
            // Read existing config
            let existingConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            
            // Append new rule to test full config
            let testConfig = existingConfig + "\n\n;; KeyPath generated rule\n" + rule
            
            try testConfig.write(toFile: tempFile, atomically: true, encoding: .utf8)
            
            // Find kanata executable
            guard let kanataPath = findKanataPath() else {
                try? FileManager.default.removeItem(atPath: tempFile)
                completion(.failure(.kanataNotFound))
                return
            }
            
            // Run kanata --check
            let task = Process()
            task.executableURL = URL(fileURLWithPath: kanataPath)
            task.arguments = ["--check", "--cfg", tempFile]
            
            let pipe = Pipe()
            task.standardError = pipe
            task.standardOutput = pipe
            
            task.terminationHandler = { process in
                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempFile)
                
                if process.terminationStatus == 0 {
                    completion(.success(true))
                } else {
                    // Read error output
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                    completion(.failure(.validationFailed(output)))
                }
            }
            
            try task.run()
        } catch {
            try? FileManager.default.removeItem(atPath: tempFile)
            completion(.failure(.validationFailed(error.localizedDescription)))
        }
    }
    
    // Install a validated rule
    func installRule(_ rule: KanataRule, completion: @escaping (Result<String, InstallError>) -> Void) {
        do {
            // Read existing config
            var config = try String(contentsOfFile: configPath, encoding: .utf8)
            
            // Add timestamp and description
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let ruleSection = """
            
            ;; KeyPath Rule: \(rule.explanation)
            ;; Generated at: \(timestamp)
            ;; \(rule.visualization.title): \(rule.visualization.description)
            \(rule.kanataRule)
            """
            
            // Append to config
            config += ruleSection
            
            // Create backup
            let backupPath = configPath + ".keypath-backup-\(Date().timeIntervalSince1970)"
            try fileManager.copyItem(atPath: configPath, toPath: backupPath)
            
            // Write new config
            try config.write(toFile: configPath, atomically: true, encoding: .utf8)
            
            // Reload Kanata
            reloadKanata { result in
                switch result {
                case .success:
                    completion(.success(backupPath))
                case .failure(let error):
                    // Restore backup on failure
                    try? self.fileManager.removeItem(atPath: self.configPath)
                    try? self.fileManager.moveItem(atPath: backupPath, toPath: self.configPath)
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(.writeFailed(error.localizedDescription)))
        }
    }
    
    // Reload Kanata configuration
    private func reloadKanata(completion: @escaping (Result<Bool, InstallError>) -> Void) {
        guard let kanataPath = findKanataPath() else {
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
    
    // Get current config for display
    func getCurrentConfig() -> String? {
        return try? String(contentsOfFile: configPath, encoding: .utf8)
    }
    
    // Undo last rule by restoring from backup
    func undoLastRule(backupPath: String, completion: @escaping (Result<Bool, InstallError>) -> Void) {
        do {
            // Restore the backup
            try fileManager.removeItem(atPath: configPath)
            try fileManager.copyItem(atPath: backupPath, toPath: configPath)
            
            // Reload Kanata
            reloadKanata { result in
                switch result {
                case .success:
                    // Clean up the backup file
                    try? self.fileManager.removeItem(atPath: backupPath)
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(.writeFailed("Failed to restore backup: \(error.localizedDescription)")))
        }
    }
}
