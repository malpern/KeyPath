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

        if cleanRule.isEmpty {
            return .failure(.recoverableValidationError(
                "Empty rule detected",
                suggestedFix: "Please describe your keyboard mapping, like 'caps lock to escape' or 'a to b'"
            ))
        }

        if cleanRule.contains(" -> ") {
            return validateArrowFormat(cleanRule)
        }

        if cleanRule.hasPrefix("(defalias ") && cleanRule.hasSuffix(")") {
            return validateDefaliasFormat(cleanRule)
        }

        return .failure(.recoverableValidationError(
            "Let me help you create that rule",
            suggestedFix: "I can understand natural language like 'caps lock to escape' or 'map a to b'. Try describing what you want to do."
        ))
    }

    private func validateArrowFormat(_ rule: String) -> Result<Bool, KanataValidationError> {
        let components = rule.components(separatedBy: " -> ")
        guard components.count == 2 else {
            return .failure(.recoverableValidationError(
                "Invalid mapping format",
                suggestedFix: "Use format like 'a -> b' or 'caps -> esc'"
            ))
        }

        let fromKey = components[0].trimmingCharacters(in: .whitespaces)
        let toKey = components[1].trimmingCharacters(in: .whitespaces)

        guard !fromKey.isEmpty && !toKey.isEmpty else {
            return .failure(.recoverableValidationError(
                "Empty key names detected",
                suggestedFix: "Specify both keys, like 'caps -> esc' or 'a -> b'"
            ))
        }

        return validateKeyNames(fromKey: fromKey, toKey: toKey)
    }

    private func validateKeyNames(fromKey: String, toKey: String) -> Result<Bool, KanataValidationError> {
        let keyValidator = KanataKeyValidator()

        if !keyValidator.isValidKeyName(fromKey) {
            let suggestion = keyValidator.suggestKeyCorrection(fromKey)
            return .failure(.recoverableValidationError(
                "Invalid source key '\(fromKey)'",
                suggestedFix: suggestion.isEmpty ? "Use standard key names like 'a', 'caps', 'esc'" : "Did you mean '\(suggestion)'?"
            ))
        }

        if !keyValidator.isValidKeyName(toKey) {
            let suggestion = keyValidator.suggestKeyCorrection(toKey)
            return .failure(.recoverableValidationError(
                "Invalid target key '\(toKey)'",
                suggestedFix: suggestion.isEmpty ? "Use standard key names like 'a', 'caps', 'esc'" : "Did you mean '\(suggestion)'?"
            ))
        }

        return .success(true)
    }

    private func validateDefaliasFormat(_ rule: String) -> Result<Bool, KanataValidationError> {
        let content = String(rule.dropFirst(10).dropLast(1)) // Remove "(defalias " and ")"
        let components = content.components(separatedBy: " ").filter { !$0.isEmpty }

        guard components.count >= 2 else {
            return .failure(.recoverableValidationError(
                "Incomplete defalias rule",
                suggestedFix: "Use format: (defalias source_key target_key)"
            ))
        }

        let aliasName = components[0]
        let keyValidator = KanataKeyValidator()
        guard keyValidator.isValidKeyName(aliasName) else {
            let suggestion = keyValidator.suggestKeyCorrection(aliasName)
            return .failure(.recoverableValidationError(
                "Invalid alias name '\(aliasName)'",
                suggestedFix: suggestion.isEmpty ? "Use standard key names" : "Did you mean '\(suggestion)'?"
            ))
        }

        return .success(true)
    }

    private func validateFullConfig(withRule rule: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        let tempFile = NSTemporaryDirectory() + "kanata_test_\(UUID().uuidString).kbd"
        print("🔧 DEBUG: Creating temp file: \(tempFile)")

        do {
            let testConfig = try generateTestConfig(withRule: rule)
            try testConfig.write(toFile: tempFile, atomically: true, encoding: .utf8)
            print("🔧 DEBUG: Temp file written successfully")

            try runKanataValidation(tempFile: tempFile, completion: completion)
        } catch {
            try? FileManager.default.removeItem(atPath: tempFile)
            completion(.failure(.validationFailed(error.localizedDescription)))
        }
    }

    private func generateTestConfig(withRule rule: String) throws -> String {
        let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
        print("🔧 DEBUG: Reading existing config from: \(configPath)")
        let existingConfig = try String(contentsOfFile: configPath, encoding: .utf8)
        print("🔧 DEBUG: Existing config length: \(existingConfig.count) characters")

        let configManager = KanataConfigManager()
        var parsedConfig = configManager.parseConfig(existingConfig)
        print("🔧 DEBUG: Parsed config - defsrc: \(parsedConfig.defsrc), deflayer: \(parsedConfig.deflayer)")

        configManager.addSimpleMapping(rule, to: &parsedConfig)
        print("🔧 DEBUG: After adding rule - defsrc: \(parsedConfig.defsrc), deflayer: \(parsedConfig.deflayer)")

        let testConfig = configManager.generateConfig(parsedConfig)
        print("🔧 DEBUG: Generated test config:\n\(testConfig)")
        print("🔧 DEBUG: Test config length: \(testConfig.count) characters")

        let structuralValidation = validateConfigStructure(testConfig)
        if case .failure(let error) = structuralValidation {
            throw error
        }

        return testConfig
    }

    private func runKanataValidation(tempFile: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) throws {
        guard let kanataPath = executableFinder.findKanataPath() else {
            print("🔧 DEBUG: Kanata not found!")
            try? FileManager.default.removeItem(atPath: tempFile)
            completion(.failure(.kanataNotFound))
            return
        }
        print("🔧 DEBUG: Kanata found at: \(kanataPath)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: kanataPath)
        task.arguments = ["--check", "--cfg", tempFile]
        print("🔧 DEBUG: Command: \(kanataPath) --check --cfg \(tempFile)")

        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe

        task.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🔧 DEBUG: Kanata check output: \(output)")

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
    }

    private func validateConfigStructure(_ config: String) -> Result<Bool, KanataValidationError> {
        if let sectionError = validateRequiredSections(config) {
            return .failure(sectionError)
        }

        if let syntaxError = validateSyntax(config) {
            return .failure(syntaxError)
        }

        if let aliasError = validateAliases(config) {
            return .failure(aliasError)
        }

        return .success(true)
    }

    private func validateRequiredSections(_ config: String) -> KanataValidationError? {
        if !config.contains("(defcfg") {
            return .validationFailed("Missing defcfg section")
        }
        if !config.contains("(defsrc") {
            return .validationFailed("Missing defsrc section")
        }
        if !config.contains("(deflayer") {
            return .validationFailed("Missing deflayer section")
        }
        return nil
    }

    private func validateSyntax(_ config: String) -> KanataValidationError? {
        let openParens = config.filter { $0 == "(" }.count
        let closeParens = config.filter { $0 == ")" }.count

        if openParens != closeParens {
            return .validationFailed("Unbalanced parentheses in config")
        }
        return nil
    }

    private func validateAliases(_ config: String) -> KanataValidationError? {
        let lines = config.components(separatedBy: .newlines)
        let aliases = extractAliasDefinitions(from: lines)
        let usedAliases = extractAliasUsages(from: lines)

        let undefinedAliases = usedAliases.subtracting(aliases)
        if !undefinedAliases.isEmpty {
            return .validationFailed("Undefined aliases: \(undefinedAliases.joined(separator: ", "))")
        }
        return nil
    }

    private func extractAliasDefinitions(from lines: [String]) -> Set<String> {
        var aliases: Set<String> = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("(defalias ") {
                let components = trimmed.dropFirst(10).components(separatedBy: " ")
                if let aliasName = components.first?.trimmingCharacters(in: .whitespaces) {
                    aliases.insert(aliasName)
                }
            }
        }
        return aliases
    }

    private func extractAliasUsages(from lines: [String]) -> Set<String> {
        var usedAliases: Set<String> = []
        for line in lines where line.contains("@") {
            let aliasMatches = line.components(separatedBy: "@")
            for match in aliasMatches.dropFirst() {
                if let aliasName = match.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespaces) {
                    usedAliases.insert(aliasName)
                }
            }
        }
        return usedAliases
    }
}
