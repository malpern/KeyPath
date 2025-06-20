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

    // Auto-install Kanata using Homebrew
    func autoInstallKanata(completion: @escaping (Result<Bool, InstallError>) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["brew", "install", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { process in
            if process.terminationStatus == 0 {
                completion(.success(true))
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                completion(.failure(.kanataInstallationFailed(output)))
            }
        }

        do {
            try task.run()
        } catch {
            completion(.failure(.kanataInstallationFailed("Failed to run brew command: \(error.localizedDescription)")))
        }
    }

    // Check if Homebrew is installed
    func isHomebrewInstalled() -> Bool {
        let commonBrewPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for path in commonBrewPaths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    // Check if Karabiner-Elements is running
    func isKarabinerRunning() -> Bool {
        print("🔧 DEBUG: Skipping Karabiner check for testing")
        // TODO: Re-enable Karabiner conflict detection after testing
        // For now, allow KeyPath to work even with Karabiner running
        return false
    }

    enum InstallError: Error, LocalizedError {
        case configDirectoryNotFound
        case configFileNotFound
        case kanataNotFound
        case kanataInstallationFailed(String)
        case karabinerConflict
        case validationFailed(String)
        case writeFailed(String)
        case reloadFailed(String)
        case recoverableValidationError(String, suggestedFix: String)

        var errorDescription: String? {
            switch self {
            case .configDirectoryNotFound:
                return "Kanata configuration directory not found at ~/.config/kanata/"
            case .configFileNotFound:
                return "Kanata configuration file not found at ~/.config/kanata/kanata.kbd"
            case .kanataNotFound:
                return "Kanata executable not found. Please install Kanata using 'brew install kanata' or download from GitHub."
            case .kanataInstallationFailed(let message):
                return "Failed to install Kanata: \(message)"
            case .karabinerConflict:
                return "Karabiner-Elements is running and conflicts with Kanata. Please quit Karabiner-Elements before using KeyPath."
            case .validationFailed(let message):
                return "Rule validation failed: \(message)"
            case .writeFailed(let message):
                return "Failed to write configuration: \(message)"
            case .reloadFailed(let message):
                return "Failed to reload Kanata: \(message)"
            case .recoverableValidationError(let error, let suggestedFix):
                return "⚠️ \(error)\n\n💡 Suggested fix: \(suggestedFix)"
            }
        }

        var isRecoverable: Bool {
            switch self {
            case .recoverableValidationError:
                return true
            default:
                return false
            }
        }

        var userFriendlyMessage: String {
            switch self {
            case .configDirectoryNotFound, .configFileNotFound:
                return "📁 Kanata setup incomplete. KeyPath will create the necessary files automatically."
            case .kanataNotFound:
                return "⚙️ Kanata not installed. Please install it with: brew install kanata"
            case .karabinerConflict:
                return "⚠️ Karabiner-Elements conflicts with Kanata. Please quit Karabiner-Elements first."
            case .validationFailed(let message):
                return createUserFriendlyValidationMessage(message)
            case .recoverableValidationError(let error, let fix):
                return "⚠️ \(error)\n\n💡 Try: \(fix)"
            case .kanataInstallationFailed, .writeFailed, .reloadFailed:
                return "❌ Installation failed. Please check your Kanata setup and try again."
            }
        }

        private func createUserFriendlyValidationMessage(_ message: String) -> String {
            let lowercased = message.lowercased()

            if lowercased.contains("invalid key") {
                return "🔤 Invalid key name. Please use standard key names like 'a', 'caps', 'esc', etc."
            } else if lowercased.contains("empty") {
                return "📝 Empty rule detected. Please specify which keys to remap."
            } else if lowercased.contains("format") {
                return "📋 Invalid format. Try using 'caps lock to escape' or 'a to b' format."
            } else if lowercased.contains("parentheses") {
                return "🔧 Syntax error detected. KeyPath will try to fix this automatically."
            } else if lowercased.contains("undefined alias") {
                return "🔗 Configuration error detected. KeyPath will rebuild the config."
            } else {
                return "⚠️ Rule validation failed. KeyPath will try to create a corrected version."
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

            (defsrc
              ;; Default source layout - will be updated by KeyPath rules
              caps
            )

            (deflayer default
              ;; Default layer - will be updated by KeyPath rules
              caps
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

    // Validate a rule using kanata --check and semantic validation
    func validateRule(_ rule: String, completion: @escaping (Result<Bool, InstallError>) -> Void) {
        print("🔧 DEBUG: Starting validation for rule: \(rule)")

        // Step 1: Semantic validation
        let semanticValidation = validateRuleSemantically(rule)
        if case .failure(let error) = semanticValidation {
            completion(.failure(error))
            return
        }

        // Step 2: Check for Karabiner conflict
        print("🔧 DEBUG: About to check if Karabiner is running...")
        let karabinerRunning = isKarabinerRunning()
        print("🔧 DEBUG: Karabiner running check: \(karabinerRunning)")
        if karabinerRunning {
            print("🔧 DEBUG: Karabiner conflict detected, failing validation")
            completion(.failure(.karabinerConflict))
            return
        }
        print("🔧 DEBUG: No Karabiner conflict, proceeding...")

        // Step 3: Ensure config is set up
        print("🔧 DEBUG: Checking kanata setup...")
        let setupResult = checkKanataSetup()
        print("🔧 DEBUG: Setup result: \(setupResult)")
        if case .failure(let error) = setupResult {
            print("🔧 DEBUG: Setup failed: \(error)")
            completion(.failure(error))
            return
        }

        // Step 4: Generate and validate full config
        validateFullConfig(withRule: rule, completion: completion)
    }

    // Semantic validation of the rule structure with automatic recovery
    private func validateRuleSemantically(_ rule: String) -> Result<Bool, InstallError> {
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for basic structure issues
        if cleanRule.isEmpty {
            return .failure(.recoverableValidationError(
                "Empty rule detected",
                suggestedFix: "Please describe your keyboard mapping, like 'caps lock to escape' or 'a to b'"
            ))
        }

        // Validate simple "a -> b" format
        if cleanRule.contains(" -> ") {
            let components = cleanRule.components(separatedBy: " -> ")
            if components.count != 2 {
                return .failure(.recoverableValidationError(
                    "Invalid mapping format",
                    suggestedFix: "Use format like 'a -> b' or 'caps -> esc'"
                ))
            }

            let fromKey = components[0].trimmingCharacters(in: .whitespaces)
            let toKey = components[1].trimmingCharacters(in: .whitespaces)

            if fromKey.isEmpty || toKey.isEmpty {
                return .failure(.recoverableValidationError(
                    "Empty key names detected",
                    suggestedFix: "Specify both keys, like 'caps -> esc' or 'a -> b'"
                ))
            }

            // Try to suggest corrections for invalid key names
            let correctedFromKey = suggestKeyCorrection(fromKey)
            let correctedToKey = suggestKeyCorrection(toKey)

            if !isValidKeyName(fromKey) {
                return .failure(.recoverableValidationError(
                    "Invalid source key '\(fromKey)'",
                    suggestedFix: correctedFromKey.isEmpty ? "Use standard key names like 'a', 'caps', 'esc'" : "Did you mean '\(correctedFromKey)'?"
                ))
            }

            if !isValidKeyName(toKey) {
                return .failure(.recoverableValidationError(
                    "Invalid target key '\(toKey)'",
                    suggestedFix: correctedToKey.isEmpty ? "Use standard key names like 'a', 'caps', 'esc'" : "Did you mean '\(correctedToKey)'?"
                ))
            }

            return .success(true)
        }

        // Validate defalias format
        if cleanRule.hasPrefix("(defalias ") && cleanRule.hasSuffix(")") {
            let content = String(cleanRule.dropFirst(10).dropLast(1)) // Remove "(defalias " and ")"
            let components = content.components(separatedBy: " ").filter { !$0.isEmpty }

            if components.count < 2 {
                return .failure(.recoverableValidationError(
                    "Incomplete defalias rule",
                    suggestedFix: "Use format: (defalias source_key target_key)"
                ))
            }

            let aliasName = components[0]
            if !isValidKeyName(aliasName) {
                let suggestion = suggestKeyCorrection(aliasName)
                return .failure(.recoverableValidationError(
                    "Invalid alias name '\(aliasName)'",
                    suggestedFix: suggestion.isEmpty ? "Use standard key names" : "Did you mean '\(suggestion)'?"
                ))
            }

            return .success(true)
        }

        // Try to guess user intent and provide helpful suggestions
        let suggestion = suggestRuleFormat(cleanRule)
        return .failure(.recoverableValidationError(
            "Unrecognized rule format",
            suggestedFix: suggestion
        ))
    }

    // Suggest corrections for common key name mistakes
    private func suggestKeyCorrection(_ keyName: String) -> String {
        let lower = keyName.lowercased()

        // Common corrections
        let corrections: [String: String] = [
            "capslock": "caps",
            "cap": "caps",
            "escape": "esc",
            "control": "lctl",
            "ctrl": "lctl",
            "shift": "lsft",
            "command": "lmet",
            "cmd": "lmet",
            "option": "lalt",
            "alt": "lalt",
            "space": "spc",
            "spacebar": "spc",
            "enter": "ret",
            "return": "ret",
            "backspace": "bspc",
            "delete": "del",
            "tab": "tab"
        ]

        if let correction = corrections[lower] {
            return correction
        }

        // Fuzzy matching for single character typos
        let validKeys = ["caps", "esc", "lctl", "rctl", "lsft", "rsft", "lalt", "ralt", "spc", "ret", "tab", "bspc", "del"]

        for validKey in validKeys {
            if levenshteinDistance(lower, validKey) <= 2 {
                return validKey
            }
        }

        return ""
    }

    // Suggest rule format based on user input
    private func suggestRuleFormat(_ input: String) -> String {
        let lower = input.lowercased()

        if lower.contains("caps") && lower.contains("esc") {
            return "Try: 'caps -> esc'"
        } else if lower.contains("space") && lower.contains("shift") {
            return "Try: 'spc -> lsft' for space to shift"
        } else if input.count == 1 {
            return "Try: '\(input) -> [target_key]' format"
        } else if lower.contains("to") {
            // Try to parse "x to y" format
            let parts = lower.components(separatedBy: " to ")
            if parts.count == 2 {
                let from = parts[0].trimmingCharacters(in: .whitespaces)
                let to = parts[1].trimmingCharacters(in: .whitespaces)
                return "Try: '\(from) -> \(to)'"
            }
        }

        return "Use format like 'caps -> esc' or 'a -> b'"
    }

    // Simple Levenshtein distance for fuzzy matching
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Length = s1Array.count
        let s2Length = s2Array.count

        var matrix = Array(repeating: Array(repeating: 0, count: s2Length + 1), count: s1Length + 1)

        for i in 0...s1Length { matrix[i][0] = i }
        for j in 0...s2Length { matrix[0][j] = j }

        for i in 1...s1Length {
            for j in 1...s2Length {
                if s1Array[i-1] == s2Array[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(matrix[i-1][j], matrix[i][j-1], matrix[i-1][j-1]) + 1
                }
            }
        }

        return matrix[s1Length][s2Length]
    }

    // Validate that a key name is reasonable
    private func isValidKeyName(_ keyName: String) -> Bool {
        let validKeys = [
            // Letters
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            // Numbers
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
            // Special keys
            "caps", "esc", "ret", "spc", "tab", "bspc", "del",
            "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
            "home", "end", "pgup", "pgdn", "up", "down", "left", "right",
            "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
            // Symbols
            "minus", "equal", "lbkt", "rbkt", "bslh", "scln", "quot", "grv",
            "comm", "dot", "slsh"
        ]

        return validKeys.contains(keyName.lowercased()) || keyName.count == 1
    }

    // Validate the full configuration with the new rule
    private func validateFullConfig(withRule rule: String, completion: @escaping (Result<Bool, InstallError>) -> Void) {
        let tempFile = NSTemporaryDirectory() + "kanata_test_\(UUID().uuidString).kbd"
        print("🔧 DEBUG: Creating temp file: \(tempFile)")

        do {
            // Read existing config
            print("🔧 DEBUG: Reading existing config from: \(configPath)")
            let existingConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            print("🔧 DEBUG: Existing config length: \(existingConfig.count) characters")

            // Parse the existing config and add the rule properly
            let configManager = KanataConfigManager()
            var parsedConfig = configManager.parseConfig(existingConfig)

            print("🔧 DEBUG: Parsed config - defsrc: \(parsedConfig.defsrc), deflayer: \(parsedConfig.deflayer)")

            // Add the rule using the config manager
            configManager.addSimpleMapping(rule, to: &parsedConfig)

            print("🔧 DEBUG: After adding rule - defsrc: \(parsedConfig.defsrc), deflayer: \(parsedConfig.deflayer)")

            // Generate the test config
            let testConfig = configManager.generateConfig(parsedConfig)
            print("🔧 DEBUG: Generated test config:\n\(testConfig)")

            // Validate the generated config structure
            let structuralValidation = validateConfigStructure(testConfig)
            if case .failure(let error) = structuralValidation {
                completion(.failure(error))
                return
            }

            print("🔧 DEBUG: Test config length: \(testConfig.count) characters")

            try testConfig.write(toFile: tempFile, atomically: true, encoding: .utf8)
            print("🔧 DEBUG: Temp file written successfully")

            // Find kanata executable
            print("🔧 DEBUG: Finding kanata executable...")
            guard let kanataPath = findKanataPath() else {
                print("🔧 DEBUG: Kanata not found!")
                try? FileManager.default.removeItem(atPath: tempFile)
                completion(.failure(.kanataNotFound))
                return
            }
            print("🔧 DEBUG: Kanata found at: \(kanataPath)")

            // Run kanata --check
            print("🔧 DEBUG: Running kanata --check command...")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: kanataPath)
            task.arguments = ["--check", "--cfg", tempFile]
            print("🔧 DEBUG: Command: \(kanataPath) --check --cfg \(tempFile)")

            let pipe = Pipe()
            task.standardError = pipe
            task.standardOutput = pipe

            task.terminationHandler = { process in
                print("🔧 DEBUG: Kanata check completed with status: \(process.terminationStatus)")

                // Read output before cleaning up
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("🔧 DEBUG: Kanata check output: \(output)")

                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempFile)
                print("🔧 DEBUG: Temp file cleaned up")

                if process.terminationStatus == 0 {
                    print("🔧 DEBUG: Validation successful!")
                    completion(.success(true))
                } else {
                    print("🔧 DEBUG: Validation failed with output: \(output)")
                    completion(.failure(.validationFailed(output)))
                }
            }

            print("🔧 DEBUG: Starting kanata process...")
            try task.run()
            print("🔧 DEBUG: Kanata process started successfully")
        } catch {
            try? FileManager.default.removeItem(atPath: tempFile)
            completion(.failure(.validationFailed(error.localizedDescription)))
        }
    }

    // Validate the structure of the generated config
    private func validateConfigStructure(_ config: String) -> Result<Bool, InstallError> {
        // Check for required sections
        if !config.contains("(defcfg") {
            return .failure(.validationFailed("Missing defcfg section"))
        }

        if !config.contains("(defsrc") {
            return .failure(.validationFailed("Missing defsrc section"))
        }

        if !config.contains("(deflayer") {
            return .failure(.validationFailed("Missing deflayer section"))
        }

        // Check for balanced parentheses
        let openParens = config.filter { $0 == "(" }.count
        let closeParens = config.filter { $0 == ")" }.count

        if openParens != closeParens {
            return .failure(.validationFailed("Unbalanced parentheses in config"))
        }

        // Check for proper alias references
        let lines = config.components(separatedBy: .newlines)
        var aliases: Set<String> = []
        var usedAliases: Set<String> = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Find defalias definitions
            if trimmed.hasPrefix("(defalias ") {
                let components = trimmed.dropFirst(10).components(separatedBy: " ")
                if let aliasName = components.first?.trimmingCharacters(in: .whitespaces) {
                    aliases.insert(aliasName)
                }
            }

            // Find alias usage in deflayer
            if trimmed.contains("@") {
                let aliasMatches = trimmed.components(separatedBy: "@")
                for match in aliasMatches.dropFirst() {
                    if let aliasName = match.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespaces) {
                        usedAliases.insert(aliasName)
                    }
                }
            }
        }

        // Check for undefined aliases
        let undefinedAliases = usedAliases.subtracting(aliases)
        if !undefinedAliases.isEmpty {
            return .failure(.validationFailed("Undefined aliases: \(undefinedAliases.joined(separator: ", "))"))
        }

        return .success(true)
    }

    // Install a validated rule
    func installRule(_ rule: KanataRule, completion: @escaping (Result<String, InstallError>) -> Void) {
        // Check for Karabiner conflict first
        if isKarabinerRunning() {
            completion(.failure(.karabinerConflict))
            return
        }

        do {
            // Read existing config
            let existingConfig = try String(contentsOfFile: configPath, encoding: .utf8)

            // Parse current config
            let configManager = KanataConfigManager()
            var parsedConfig = configManager.parseConfig(existingConfig)

            // Add the new rule
            configManager.addSimpleMapping(rule.kanataRule, to: &parsedConfig)

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
