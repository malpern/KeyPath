import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import Network

// KanataConfiguration struct and generation logic moved to KanataConfigurationGenerator.swift

// MARK: - Configuration Service

/// Centralized configuration management service for Kanata
///
/// This service handles all configuration-related operations:
/// - Loading and saving configuration files
/// - Validation via TCP and file-based checks
/// - File watching and change detection
/// - Key mapping generation and conversion
public final class ConfigurationService: FileConfigurationProviding {
    public typealias Config = KanataConfiguration

    // MARK: - Properties

    public let configurationPath: String
    public let configDirectory: String
    public let configFileName = KeyPathConstants.Config.fileName

    private var currentConfiguration: KanataConfiguration?
    private var fileWatcher: FileWatcher?
    private var observers: [@Sendable (Config) async -> Void] = []

    // Perform blocking file I/O off the main actor
    private let ioQueue = DispatchQueue(label: "com.keypath.configservice.io", qos: .utility)
    // Protect shared state when accessed from multiple threads
    private let stateLock = NSLock()

    // MARK: - Initialization

    public init(configDirectory: String? = nil) {
        if let customDirectory = configDirectory {
            self.configDirectory = customDirectory
        } else {
            self.configDirectory = KeyPathConstants.Config.directory
        }
        configurationPath = "\(self.configDirectory)/\(configFileName)"
    }

    // MARK: - ConfigurationProviding Protocol

    public func current() async -> KanataConfiguration {
        // Fast path: return cached config if available
        if let cached = withLockedCurrentConfig() { return cached }

        // Try to load existing configuration, fallback to empty if not found
        do {
            let config = try await reload()
            return config
        } catch {
            AppLogger.shared.log("⚠️ [ConfigService] Failed to load current config, using empty: \(error)")
            let emptyConfig = KanataConfiguration(
                content: KanataConfiguration.generateFromMappings([]),
                keyMappings: [],
                lastModified: Date(),
                path: configurationPath
            )
            setCurrentConfiguration(emptyConfig)
            return emptyConfig
        }
    }

    public func reload() async throws -> KanataConfiguration {
        var exists = await fileExistsAsync(path: configurationPath)

        if !exists {
            AppLogger.shared.log(
                "⚠️ [ConfigService] Config missing at \(configurationPath) – creating default before reload")
            do {
                try await createInitialConfigIfNeeded()
                exists = await fileExistsAsync(path: configurationPath)
            } catch {
                AppLogger.shared.log(
                    "❌ [ConfigService] Failed to create default config during reload: \(error)")
            }
        }

        guard exists else {
            throw KeyPathError.configuration(.fileNotFound(path: configurationPath))
        }

        do {
            let content = try await readFileAsync(path: configurationPath)
            let config = try validate(content: content)
            setCurrentConfiguration(config)

            // Notify observers on main actor
            let snapshot = observersSnapshot()
            let tasks = snapshot.map { observer in
                Task { @MainActor in await observer(config) }
            }
            for t in tasks {
                await t.value
            }

            return config
        } catch let error as KeyPathError {
            throw error
        } catch {
            throw KeyPathError.configuration(.loadFailed(reason: error.localizedDescription))
        }
    }

    public func observe(_ onChange: @Sendable @escaping (Config) async -> Void)
        -> ConfigurationObservationToken {
        var index = 0
        stateLock.lock()
        observers.append(onChange)
        index = observers.count - 1
        stateLock.unlock()

        return ConfigurationObservationToken {
            self.stateLock.lock()
            if index < self.observers.count { self.observers.remove(at: index) }
            self.stateLock.unlock()
        }
    }

    // MARK: - FileConfigurationProviding Protocol

    public func validate(content: String) throws -> KanataConfiguration {
        // Basic validation - ensure content is not empty
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeyPathError.configuration(.invalidFormat(reason: "Configuration content is empty"))
        }

        // Get file modification date
        let attributes = try? FileManager.default.attributesOfItem(atPath: configurationPath)
        let lastModified = (attributes?[.modificationDate] as? Date) ?? Date()

        // Extract key mappings from content (simplified - could be enhanced)
        let keyMappings = extractKeyMappingsFromContent(content)

        return KanataConfiguration(
            content: content,
            keyMappings: keyMappings,
            lastModified: lastModified,
            path: configurationPath
        )
    }

    public func startFileMonitoring() -> ConfigurationObservationToken {
        guard fileWatcher == nil else {
            // Already monitoring
            return ConfigurationObservationToken { /* no-op */ }
        }

        fileWatcher = FileWatcher(path: configurationPath) { [weak self] in
            Task { @MainActor in
                await self?.handleFileChange()
            }
        }

        return ConfigurationObservationToken { [weak self] in
            self?.stopFileMonitoring()
        }
    }

    // MARK: - Configuration Management

    /// Create the configuration directory and initial config if needed
    public func createInitialConfigIfNeeded() async throws {
        // Create config directory if it doesn't exist (off-main)
        try await createDirectoryAsync(path: configDirectory)
        AppLogger.shared.log("✅ [ConfigService] Config directory created at \(configDirectory)")

        // Check if config file exists
        let exists = await fileExistsAsync(path: configurationPath)
        if !exists {
            AppLogger.shared.log("⚠️ [ConfigService] No existing config found at \(configurationPath)")

            // Rehydrate from persisted rule/custom stores so user state survives file deletion/reset
            let storedCollections = await RuleCollectionStore.shared.loadCollections()
            let storedCustomRules = await CustomRulesStore.shared.loadRules()
            let collectionsToSave = storedCollections.isEmpty
                ? RuleCollectionCatalog().defaultCollections()
                : storedCollections

            AppLogger.shared.log(
                "🆕 [ConfigService] Creating initial config from stores: \(collectionsToSave.count) collections, \(storedCustomRules.count) custom rules"
            )

            try await saveConfiguration(
                ruleCollections: collectionsToSave,
                customRules: storedCustomRules
            )
            AppLogger.shared.log(
                "✅ [ConfigService] Created initial configuration with \(collectionsToSave.count) collections"
            )
        } else {
            AppLogger.shared.log("✅ [ConfigService] Existing config found at \(configurationPath)")
        }
    }

    /// Save configuration using rule collections.
    /// IMPORTANT: Validates config before saving - will throw on invalid config
    public func saveConfiguration(
        ruleCollections: [RuleCollection],
        customRules: [CustomRule] = []
    ) async throws {
        // Custom rules come first so they take priority over preset collections
        let customRuleCollections = customRules.asRuleCollections()
        AppLogger.shared.log("🔧 [ConfigService] Converting \(customRules.count) custom rules to \(customRuleCollections.count) collections")
        for (i, coll) in customRuleCollections.enumerated() {
            let mappingStrs = coll.mappings.map { "'\($0.input)' → '\($0.output)'" }.joined(separator: ", ")
            AppLogger.shared.log("🔧 [ConfigService]   Custom collection \(i): '\(coll.name)' (enabled: \(coll.isEnabled), layer: \(coll.targetLayer)) mappings: [\(mappingStrs)]")
        }
        let allCollections = customRuleCollections + ruleCollections

        // DETECT CONFLICTS BEFORE DEDUPLICATION
        // This catches cases where multiple collections map the same key
        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: allCollections)
        if !conflicts.isEmpty {
            AppLogger.shared.log(
                "⚠️ [ConfigService] Mapping conflicts detected: \(conflicts.map(\.description).joined(separator: "; "))"
            )
            throw KeyPathError.configuration(.mappingConflicts(conflicts: conflicts))
        }
        AppLogger.shared.debug("✅ [ConfigService] No mapping conflicts detected")

        let combinedCollections = RuleCollectionDeduplicator.dedupe(allCollections)
        let mappings = combinedCollections.enabledMappings()
        let configContent = KanataConfiguration.generateFromCollections(combinedCollections)

        // VALIDATE BEFORE SAVING - prevent writing broken configs
        AppLogger.shared.log("🔍 [ConfigService] Validating config before save...")
        let validation = await validateConfiguration(configContent)

        if !validation.isValid {
            AppLogger.shared.log(
                "❌ [ConfigService] Config validation failed: \(validation.errors.joined(separator: ", "))")
            throw KeyPathError.configuration(.validationFailed(errors: validation.errors))
        }

        AppLogger.shared.log("✅ [ConfigService] Config validation passed")

        try await writeFileAsync(string: configContent, to: configurationPath)

        // Update current configuration
        let newConfig = KanataConfiguration(
            content: configContent,
            keyMappings: mappings,
            lastModified: Date(),
            path: configurationPath
        )
        setCurrentConfiguration(newConfig)

        // Notify observers on main actor
        let snapshot = observersSnapshot()
        let tasks = snapshot.map { observer in
            Task { @MainActor in await observer(newConfig) }
        }
        for t in tasks {
            await t.value
        }

        AppLogger.shared.log("✅ [ConfigService] Configuration saved with \(mappings.count) mappings")
    }

    /// Save configuration with key mappings (legacy helper)
    public func saveConfiguration(keyMappings: [KeyMapping]) async throws {
        let collections = [RuleCollection].collection(
            named: "Custom Mappings",
            mappings: keyMappings,
            category: .custom
        )
        try await saveConfiguration(ruleCollections: collections)
    }

    /// Save configuration with specific input/output mapping
    public func saveConfiguration(input: String, output: String) async throws {
        let keyMapping = KeyMapping(input: input, output: output)
        try await saveConfiguration(keyMappings: [keyMapping])
    }

    /// Write raw configuration content to file (for restoration/repair)
    public func writeConfigurationContent(_ content: String) async throws {
        try await writeFileAsync(string: content, to: configurationPath)
        // Update current configuration
        let newConfig = try validate(content: content)
        setCurrentConfiguration(newConfig)
    }

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
                return (false, errors)
            }

        } catch {
            AppLogger.shared.log("❌ [ConfigService] File validation error: \(error)")
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

    // MARK: - Backup and Recovery

    /// Backs up a failed config and applies safe default, returning backup path
    public func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping])
        async throws
        -> String {
        AppLogger.shared.log("🛡️ [Config] Backing up failed config and applying safe default")

        // Create backup directory if it doesn't exist
        let backupDir = "\(configDirectory)/backups"
        let backupDirURL = URL(fileURLWithPath: backupDir)
        try FileManager.default.createDirectory(at: backupDirURL, withIntermediateDirectories: true)

        // Create timestamped backup filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let backupPath = "\(backupDir)/failed_config_\(timestamp).kbd"
        let backupURL = URL(fileURLWithPath: backupPath)

        // Write the failed config to backup
        let backupContent = """
        ;; FAILED CONFIG - AUTOMATICALLY BACKED UP
        ;; Timestamp: \(timestamp)
        ;; Errors: \(mappings.count) mapping(s) could not be applied

        \(failedConfig)
        """
        try await writeFileURLAsync(string: backupContent, to: backupURL)

        AppLogger.shared.log("💾 [Config] Failed config backed up to: \(backupPath)")

        // Apply safe default config using the standard generator
        let safeConfig = KanataConfiguration.generateFromMappings(mappings)

        let configURL = URL(fileURLWithPath: configurationPath)
        try await writeFileURLAsync(string: safeConfig, to: configURL)

        AppLogger.shared.log("✅ [Config] Safe default config applied")

        // Update current configuration
        setCurrentConfiguration(
            KanataConfiguration(
                content: safeConfig,
                keyMappings: [KeyMapping(input: "caps", output: "escape")],
                lastModified: Date(),
                path: configurationPath
            ))

        return backupPath
    }

    /// Repair configuration using rule-based strategies (keeps output Kanata-compatible).
    public func repairConfiguration(config: String, errors: [String], mappings: [KeyMapping])
        async throws
        -> String {
        AppLogger.shared.log("🔧 [Config] Performing rule-based repair for \(errors.count) errors")

        // Common repair strategies
        var repairedConfig = config

        for error in errors {
            let lowerError = error.lowercased()

            // Fix common syntax errors
            if lowerError.contains("missing"), lowerError.contains("defcfg") {
                // Add missing defcfg using the same safe defaults as our generator
                if !repairedConfig.contains("(defcfg") {
                    let defcfgSection = """
                    (defcfg
                      process-unmapped-keys yes
                      danger-enable-cmd yes
                    )

                    """
                    repairedConfig = defcfgSection + repairedConfig
                }
            }

            // Fix empty parentheses issues
            if lowerError.contains("()") || lowerError.contains("empty") {
                repairedConfig = repairedConfig.replacingOccurrences(of: "()", with: "_")
                repairedConfig = repairedConfig.replacingOccurrences(of: "( )", with: "_")
            }

            // Fix mismatched defsrc/deflayer lengths
            if lowerError.contains("mismatch") || lowerError.contains("length") {
                // Regenerate from scratch using our proven template
                return KanataConfiguration.generateFromMappings(mappings)
            }
        }

        return repairedConfig
    }

    // MARK: - Private Methods

    private func handleFileChange() async {
        AppLogger.shared.log("📁 [ConfigService] Configuration file changed - reloading")
        do {
            _ = try await reload()
            AppLogger.shared.log("✅ [ConfigService] Configuration reloaded successfully")
        } catch {
            AppLogger.shared.log("❌ [ConfigService] Failed to reload configuration: \(error)")
        }
    }

    private func stopFileMonitoring() {
        fileWatcher = nil
        AppLogger.shared.log("🛑 [ConfigService] File monitoring stopped")
    }

    /// Extract key mappings from Kanata configuration content
    private func extractKeyMappingsFromContent(_ configContent: String) -> [KeyMapping] {
        var mappings: [KeyMapping] = []
        let lines = configContent.components(separatedBy: .newlines)

        var inDefsrc = false
        var inDeflayer = false
        var srcKeys: [String] = []
        var layerKeys: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("(defsrc") {
                inDefsrc = true
                inDeflayer = false
                continue
            } else if trimmed.hasPrefix("(deflayer") {
                inDefsrc = false
                inDeflayer = true
                continue
            } else if trimmed == ")" {
                inDefsrc = false
                inDeflayer = false
                continue
            }

            if inDefsrc, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
                srcKeys.append(
                    contentsOf: trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
            } else if inDeflayer, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
                layerKeys.append(
                    contentsOf: trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
            }
        }

        // Match up src and layer keys, filtering out invalid keys
        var tempMappings: [KeyMapping] = []
        for (index, srcKey) in srcKeys.enumerated() where index < layerKeys.count {
            // Skip obviously invalid keys
            if srcKey != "invalid", !srcKey.isEmpty {
                tempMappings.append(KeyMapping(input: srcKey, output: layerKeys[index]))
            }
        }

        // Deduplicate mappings - keep only the last mapping for each input key
        var seenInputs: Set<String> = []
        for mapping in tempMappings.reversed() where !seenInputs.contains(mapping.input) {
            mappings.insert(mapping, at: 0)
            seenInputs.insert(mapping.input)
        }

        AppLogger.shared.log(
            "🔍 [Parse] Found \(srcKeys.count) src keys, \(layerKeys.count) layer keys, deduplicated to \(mappings.count) unique mappings"
        )
        return mappings
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

    /// Parse configuration from string content
    public func parseConfigurationFromString(_ content: String) throws -> KanataConfiguration {
        // Use the existing validate method which handles parsing
        try validate(content: content)
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
}

// MARK: - Private helpers (I/O and state)

private extension ConfigurationService {
    func withLockedCurrentConfig() -> KanataConfiguration? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentConfiguration
    }

    func setCurrentConfiguration(_ config: KanataConfiguration) {
        stateLock.lock()
        defer { stateLock.unlock() }
        currentConfiguration = config
    }

    func observersSnapshot() -> [@Sendable (Config) async -> Void] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return observers
    }

    func readFileAsync(path: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            ioQueue.async {
                do {
                    let content = try String(contentsOfFile: path, encoding: .utf8)
                    cont.resume(returning: content)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func writeFileAsync(string: String, to path: String) async throws {
        // SAFETY: Prevent writing empty config files - this is a critical guard
        // against bugs that could wipe the user's config
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.shared.error("🛑 [ConfigService] BLOCKED: Attempted to write empty content to \(path)")
            throw KeyPathError.configuration(.invalidFormat(reason: "Cannot write empty configuration"))
        }

        // Additional safety: config files must have minimum required structure
        if path.hasSuffix(".kbd") {
            guard trimmed.contains("defsrc") || trimmed.contains("deflayer") else {
                AppLogger.shared.error("🛑 [ConfigService] BLOCKED: Config missing required defsrc/deflayer: \(path)")
                throw KeyPathError.configuration(.invalidFormat(reason: "Configuration missing required defsrc or deflayer block"))
            }
        }

        try await withCheckedThrowingContinuation { cont in
            ioQueue.async {
                do {
                    try string.write(toFile: path, atomically: true, encoding: .utf8)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func writeFileURLAsync(string: String, to url: URL) async throws {
        try await withCheckedThrowingContinuation { cont in
            ioQueue.async {
                do {
                    try string.write(to: url, atomically: true, encoding: .utf8)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func createDirectoryAsync(path: String) async throws {
        try await withCheckedThrowingContinuation { cont in
            ioQueue.async {
                do {
                    try FileManager.default.createDirectory(
                        atPath: path,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o755]
                    )
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func fileExistsAsync(path: String) async -> Bool {
        await withCheckedContinuation { cont in
            ioQueue.async {
                cont.resume(returning: FileManager.default.fileExists(atPath: path))
            }
        }
    }
}

// MARK: - Key Conversion Utilities

/// Utility class for converting keys between KeyPath and Kanata formats
public enum KanataKeyConverter {
    /// Convert KeyPath key to Kanata key format for use inside macros
    /// Inside macros, chord syntax like M-right requires UPPERCASE modifier prefixes
    /// This method preserves the case of modifier prefixes (M-, A-, C-, S-)
    public static func convertToKanataKeyForMacro(_ input: String) -> String {
        // Known modifier prefixes that must remain uppercase in macro context
        // Order matters - check longer prefixes first
        let modifierPrefixes = ["M-S-", "C-S-", "A-S-", "M-", "A-", "C-", "S-"]

        for prefix in modifierPrefixes {
            if input.hasPrefix(prefix) {
                // Preserve uppercase prefix, convert base key
                let baseKey = String(input.dropFirst(prefix.count))
                let convertedBase = convertToKanataKey(baseKey)
                return prefix + convertedBase
            }
        }

        // No modifier prefix - use standard conversion
        return convertToKanataKey(input)
    }

    /// Convert KeyPath input key to Kanata key format
    public static func convertToKanataKey(_ input: String) -> String {
        // Use the same key mapping logic as the original RuntimeCoordinator
        let keyMap: [String: String] = [
            "caps": "caps",
            "capslock": "caps",
            "caps lock": "caps",
            "space": "spc",
            "spacebar": "spc",
            "enter": "ret",
            "return": "ret",
            "tab": "tab",
            "escape": "esc",
            "esc": "esc",
            "backspace": "bspc",
            "delete": "del",
            "cmd": "lmet",
            "command": "lmet",
            "lcmd": "lmet",
            "rcmd": "rmet",
            "leftcmd": "lmet",
            "rightcmd": "rmet",
            "left command": "lmet",
            "right command": "rmet",
            "left shift": "lsft",
            "lshift": "lsft",
            "right shift": "rsft",
            "rshift": "rsft",
            "left control": "lctl",
            "lctrl": "lctl",
            "ctrl": "lctl",
            "right control": "rctl",
            "rctrl": "rctl",
            "left option": "lalt",
            "lalt": "lalt",
            "right option": "ralt",
            "ralt": "ralt",
            "(": "lpar",
            ")": "rpar",
            // Punctuation keys - must be converted to kanata's abbreviated names
            "apostrophe": "'",
            "semicolon": ";",
            "comma": ",",
            "dot": ".",
            "period": ".",
            "slash": "/",
            "minus": "min",
            "equal": "eql",
            "equals": "eql",
            "grave": "grv",
            "backslash": "\\",
            "leftbrace": "[",
            "rightbrace": "]",
            "leftbracket": "[",
            "rightbracket": "]",
            // International/locale-specific keys
            // Korean keyboard keys
            "hangeul": "kana", // Korean Hanja key → maps to Japanese kana (similar input mode toggle)
            "hanja": "eisu", // Korean Han/Eng toggle → maps to Japanese eisu (alphanumeric mode)
            // ISO/International keys
            "intlbackslash": "nubs", // ISO key between Left Shift and Z (Non-US Backslash)
            "intlro": "ro", // ABNT2/JIS Ro key (extra key between slash and right shift)
            // JIS keys (already have native Kanata names, but add aliases)
            "eisu": "eisu", // Japanese alphanumeric key
            "kana": "kana" // Japanese kana key
        ]

        let lowercased = input.lowercased()

        // Check if we have a specific mapping
        if let mapped = keyMap[lowercased] {
            return mapped
        }

        // For single characters, return as-is
        if lowercased.count == 1 {
            return lowercased
        }

        // For tokens that would break Kanata syntax, replace parens explicitly
        if lowercased.contains("(") { return "lpar" }
        if lowercased.contains(")") { return "rpar" }

        // For function keys and others, return as-is but lowercased
        return lowercased
    }

    /// Convert KeyPath output sequence to Kanata output format
    public static func convertToKanataSequence(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Split on any whitespace
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // No tokens -> nothing to emit (avoid indexing empty array)
        if tokens.isEmpty {
            return ""
        }

        // Multiple whitespace-separated tokens (e.g., "cmd space") → chord/sequence
        if tokens.count > 1 {
            // Use convertToKanataKeyForMacro to preserve uppercase modifier prefixes
            let kanataKeys = tokens.map { convertToKanataKeyForMacro($0) }
            return "(\(kanataKeys.joined(separator: " ")))"
        }

        // Single token - check if it's a text sequence to type (e.g., "123", "hello")
        let singleToken = tokens[0]

        // If it's a multi-character string that looks like text to type (not a key name)
        // Convert to macro for typing each character
        if singleToken.count > 1, shouldConvertToMacro(singleToken) {
            // Split into individual characters and convert each to a key
            let characters = Array(singleToken)
            let keys = characters.map { String($0) }
            return "(macro \(keys.joined(separator: " ")))"
        }

        // Single key: use convertToKanataKeyForMacro to preserve uppercase modifier prefixes
        // (e.g., A-right, M-left, M-S-g) which are valid in both macro and deflayer contexts
        return convertToKanataKeyForMacro(singleToken)
    }

    /// Determine if a string should be converted to a macro (typed character by character)
    /// vs treated as a single key name like "escape" or "tab"
    private static func shouldConvertToMacro(_ token: String) -> Bool {
        // Check for Kanata modifier prefixes (e.g., A-right, M-left, C-S-a)
        // These should NOT be converted to macros - they are valid Kanata modified key outputs
        let modifierPattern = #"^(A-|M-|C-|S-|RA-|RM-|RC-|RS-|AG-)+"#
        if let regex = try? NSRegularExpression(pattern: modifierPattern, options: .caseInsensitive) {
            let range = NSRange(token.startIndex..., in: token)
            if regex.firstMatch(in: token, options: [], range: range) != nil {
                return false
            }
        }

        // Known key names that shouldn't be split into macros
        let keyNames: Set<String> = [
            "escape", "esc", "return", "ret", "enter",
            "backspace", "bspc", "delete", "del",
            "tab", "space", "spc",
            "capslock", "caps", "capslk",
            "leftshift", "lsft", "rightshift", "rsft",
            "leftctrl", "lctl", "rightctrl", "rctl", "ctrl",
            "leftalt", "lalt", "rightalt", "ralt",
            "leftmeta", "lmet", "rightmeta", "rmet",
            "leftcmd", "rightcmd", "cmd", "command", "lcmd", "rcmd",
            "up", "down", "left", "right",
            "home", "end", "pageup", "pgup", "pagedown", "pgdn",
            "f1", "f2", "f3", "f4", "f5", "f6",
            "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15",
            "f16", "f17", "f18", "f19", "f20",
            // Kanata media/system outputs
            "brdn", "brup", "mission_control", "launchpad",
            "prev", "pp", "next", "mute", "vold", "volu"
        ]

        // If it's a known key name, don't convert to macro
        if keyNames.contains(token.lowercased()) {
            return false
        }

        // If it contains multiple alphanumeric characters or symbols, treat as text to type
        return token.count > 1
    }
}

// MARK: - File Watcher (Simplified)

/// Simple file watcher for configuration changes
private class FileWatcher {
    private let path: String
    private let callback: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(path: String, callback: @escaping () -> Void) {
        self.path = path
        self.callback = callback
        startWatching()
    }

    deinit {
        stopWatching()
    }

    private func startWatching() {
        let fileDescriptor = open(path, O_RDONLY)
        guard fileDescriptor >= 0 else {
            AppLogger.shared.log("❌ [FileWatcher] Could not open file for watching: \(path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            self?.callback()
        }

        source?.setCancelHandler {
            close(fileDescriptor)
        }

        source?.resume()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }
}
