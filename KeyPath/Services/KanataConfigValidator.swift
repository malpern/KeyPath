import Foundation

class KanataConfigValidator {
    private let executableFinder = KanataExecutableFinder()

    func validateRule(_ rule: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        print("🔧 DEBUG: Starting validation for rule: \(rule)")

        // Step 1: Semantic validation
        let semanticValidation = validateRuleSemantically(rule)
        if case .failure(let error) = semanticValidation {
            completion(.failure(error))
            return
        }

        // Step 2: Check for Karabiner conflict
        print("🔧 DEBUG: About to check if Karabiner is running...")
        let karabinerRunning = executableFinder.isKarabinerRunning()
        print("🔧 DEBUG: Karabiner running check: \(karabinerRunning)")
        if karabinerRunning {
            print("🔧 DEBUG: Karabiner conflict detected, failing validation")
            completion(.failure(.karabinerConflict))
            return
        }
        print("🔧 DEBUG: No Karabiner conflict, proceeding...")

        // Step 3: Ensure config is set up
        print("🔧 DEBUG: Checking kanata setup...")
        let setupChecker = KanataSetupChecker()
        let setupResult = setupChecker.checkKanataSetup()
        print("🔧 DEBUG: Setup result: \(setupResult)")
        if case .failure(let error) = setupResult {
            print("🔧 DEBUG: Setup failed: \(error)")
            completion(.failure(error))
            return
        }

        // Step 4: Generate and validate full config
        validateFullConfig(withRule: rule, completion: completion)
    }

    private func validateRuleSemantically(_ rule: String) -> Result<Bool, KanataValidationError> {
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
            let keyValidator = KanataKeyValidator()
            let correctedFromKey = keyValidator.suggestKeyCorrection(fromKey)
            let correctedToKey = keyValidator.suggestKeyCorrection(toKey)

            if !keyValidator.isValidKeyName(fromKey) {
                return .failure(.recoverableValidationError(
                    "Invalid source key '\(fromKey)'",
                    suggestedFix: correctedFromKey.isEmpty ? "Use standard key names like 'a', 'caps', 'esc'" : "Did you mean '\(correctedFromKey)'?"
                ))
            }

            if !keyValidator.isValidKeyName(toKey) {
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
            let keyValidator = KanataKeyValidator()
            if !keyValidator.isValidKeyName(aliasName) {
                let suggestion = keyValidator.suggestKeyCorrection(aliasName)
                return .failure(.recoverableValidationError(
                    "Invalid alias name '\(aliasName)'",
                    suggestedFix: suggestion.isEmpty ? "Use standard key names" : "Did you mean '\(suggestion)'?"
                ))
            }

            return .success(true)
        }

        // Try to guess user intent and provide helpful suggestions
        let suggestionProvider = KanataRuleSuggestionProvider()
        let suggestion = suggestionProvider.suggestRuleFormat(cleanRule)
        return .failure(.recoverableValidationError(
            "Unrecognized rule format",
            suggestedFix: suggestion
        ))
    }

    private func validateFullConfig(withRule rule: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        let tempFile = NSTemporaryDirectory() + "kanata_test_\(UUID().uuidString).kbd"
        print("🔧 DEBUG: Creating temp file: \(tempFile)")

        do {
            // Read existing config
            let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
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
            guard let kanataPath = executableFinder.findKanataPath() else {
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

    private func validateConfigStructure(_ config: String) -> Result<Bool, KanataValidationError> {
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
}
