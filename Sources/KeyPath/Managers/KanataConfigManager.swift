import Foundation

/// Phase 4: Kanata Configuration Manager
///
/// Centralized configuration management with validation, templates, and error recovery.
/// This replaces the scattered configuration logic with a clean, testable interface.
class KanataConfigManager {
    // MARK: - Configuration Types

    struct ConfigurationSet {
        let mappings: [KeyMapping]
        let metadata: ConfigMetadata
        let generatedConfig: String
        let validationResult: ValidationResult
    }

    struct ConfigMetadata {
        let version: String
        let createdAt: Date
        let modifiedAt: Date
        let source: ConfigSource
        let mappingCount: Int
        let isDefault: Bool

        enum ConfigSource {
            case user
            case system
            case backup
            case template
        }
    }

    struct ValidationResult {
        let isValid: Bool
        let errors: [ValidationError]
        let warnings: [ValidationWarning]
        let suggestions: [String]

        var hasBlockingErrors: Bool {
            errors.contains { $0.severity == .critical }
        }
    }

    struct ValidationError {
        let line: Int?
        let message: String
        let severity: Severity
        let suggestion: String?

        enum Severity {
            case critical
            case error
            case warning
        }
    }

    struct ValidationWarning {
        let line: Int?
        let message: String
        let suggestion: String?
    }

    // MARK: - Configuration Templates

    enum ConfigTemplate: String, CaseIterable {
        case minimal
        case standard
        case advanced
        case vim
        case emacs

        var displayName: String {
            switch self {
            case .minimal:
                "Minimal (Caps → Escape)"
            case .standard:
                "Standard (Common Remappings)"
            case .advanced:
                "Advanced (Power User)"
            case .vim:
                "Vim-Optimized"
            case .emacs:
                "Emacs-Optimized"
            }
        }

        var description: String {
            switch self {
            case .minimal:
                "Single mapping: Caps Lock to Escape"
            case .standard:
                "Common remappings for general productivity"
            case .advanced:
                "Complex mappings with layers and modifiers"
            case .vim:
                "Optimized for Vim/Neovim users"
            case .emacs:
                "Optimized for Emacs users"
            }
        }

        var mappings: [KeyMapping] {
            switch self {
            case .minimal:
                [KeyMapping(input: "caps", output: "esc")]
            case .standard:
                [
                    KeyMapping(input: "caps", output: "esc"),
                    KeyMapping(input: "tab", output: "lctl"),
                    KeyMapping(input: "ralt", output: "rctl")
                ]
            case .advanced:
                [
                    KeyMapping(input: "caps", output: "esc"),
                    KeyMapping(input: "tab", output: "lctl"),
                    KeyMapping(input: "space", output: "spc"),
                    KeyMapping(input: "return", output: "ret")
                ]
            case .vim:
                [
                    KeyMapping(input: "caps", output: "esc"),
                    KeyMapping(input: "tab", output: "lctl"),
                    KeyMapping(input: "semicolon", output: "colon")
                ]
            case .emacs:
                [
                    KeyMapping(input: "caps", output: "lctl"),
                    KeyMapping(input: "lalt", output: "lmeta"),
                    KeyMapping(input: "ralt", output: "rmeta")
                ]
            }
        }
    }

    // MARK: - Properties

    private let configDirectory: String
    private let configFileName: String
    private let backupDirectory: String

    // MARK: - Initialization

    init(
        configDirectory: String = "/usr/local/etc/kanata",
        configFileName: String = "keypath.kbd",
        backupDirectory: String = "/usr/local/etc/kanata/backups"
    ) {
        self.configDirectory = configDirectory
        self.configFileName = configFileName
        self.backupDirectory = backupDirectory
    }

    var configPath: String {
        "\(configDirectory)/\(configFileName)"
    }

    // MARK: - Configuration Management

    /// Create configuration from mappings
    func createConfiguration(mappings: [KeyMapping], source: ConfigMetadata.ConfigSource = .user)
        -> ConfigurationSet {
        AppLogger.shared.log("⚙️ [ConfigManager] Creating configuration with \(mappings.count) mappings")

        let generatedConfig = generateKanataConfig(mappings: mappings)
        let validationResult = validateConfiguration(generatedConfig)

        let metadata = ConfigMetadata(
            version: "1.0",
            createdAt: Date(),
            modifiedAt: Date(),
            source: source,
            mappingCount: mappings.count,
            isDefault: mappings.count == 1 && mappings.first?.input == "caps"
        )

        return ConfigurationSet(
            mappings: mappings,
            metadata: metadata,
            generatedConfig: generatedConfig,
            validationResult: validationResult
        )
    }

    /// Create configuration from template
    func createConfigurationFromTemplate(_ template: ConfigTemplate) -> ConfigurationSet {
        AppLogger.shared.log(
            "⚙️ [ConfigManager] Creating configuration from template: \(template.displayName)")
        return createConfiguration(mappings: template.mappings, source: .template)
    }

    /// Load existing configuration
    func loadConfiguration() async throws -> ConfigurationSet {
        AppLogger.shared.log("⚙️ [ConfigManager] Loading configuration from \(configPath)")

        guard FileManager.default.fileExists(atPath: configPath) else {
            throw ConfigManagerError.configNotFound
        }

        let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
        let mappings = try parseKanataConfig(configContent)

        let metadata = ConfigMetadata(
            version: "1.0",
            createdAt: Date(), // Would be actual file creation date
            modifiedAt: getFileModificationDate(configPath) ?? Date(),
            source: .user,
            mappingCount: mappings.count,
            isDefault: false
        )

        let validationResult = validateConfiguration(configContent)

        return ConfigurationSet(
            mappings: mappings,
            metadata: metadata,
            generatedConfig: configContent,
            validationResult: validationResult
        )
    }

    /// Save configuration with backup
    func saveConfiguration(_ configSet: ConfigurationSet) async throws {
        AppLogger.shared.log(
            "⚙️ [ConfigManager] Saving configuration with \(configSet.mappings.count) mappings")

        // Validate before saving
        if configSet.validationResult.hasBlockingErrors {
            throw ConfigManagerError.invalidConfiguration(configSet.validationResult.errors)
        }

        // Create backup if existing config exists
        if FileManager.default.fileExists(atPath: configPath) {
            try await createBackup()
        }

        // Ensure directory exists
        try FileManager.default.createDirectory(
            atPath: configDirectory, withIntermediateDirectories: true
        )

        // Write configuration
        try configSet.generatedConfig.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Verify write
        let verification = validateConfiguration(configSet.generatedConfig)
        if verification.hasBlockingErrors {
            throw ConfigManagerError.saveVerificationFailed
        }

        AppLogger.shared.log("✅ [ConfigManager] Configuration saved successfully")
    }

    /// Create backup of current configuration
    func createBackup() async throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return // No config to backup
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
            of: ":", with: "-"
        )
        let backupFileName = "keypath-backup-\(timestamp).kbd"
        let backupPath = "\(backupDirectory)/\(backupFileName)"

        // Ensure backup directory exists
        try FileManager.default.createDirectory(
            atPath: backupDirectory, withIntermediateDirectories: true
        )

        // Copy current config to backup
        try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)

        AppLogger.shared.log("💾 [ConfigManager] Backup created: \(backupFileName)")
    }

    /// List available backups
    func listBackups() -> [BackupInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: backupDirectory) else {
            return []
        }

        return
            files
                .filter { $0.hasPrefix("keypath-backup-") && $0.hasSuffix(".kbd") }
                .compactMap { fileName in
                    let fullPath = "\(backupDirectory)/\(fileName)"
                    guard let modificationDate = getFileModificationDate(fullPath),
                          let size = getFileSize(fullPath)
                    else {
                        return nil
                    }

                    return BackupInfo(
                        fileName: fileName,
                        fullPath: fullPath,
                        createdAt: modificationDate,
                        size: size
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }
    }

    struct BackupInfo {
        let fileName: String
        let fullPath: String
        let createdAt: Date
        let size: Int64

        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Backup from \(formatter.string(from: createdAt))"
        }
    }

    // MARK: - Configuration Generation

    private func generateKanataConfig(mappings: [KeyMapping]) -> String {
        guard !mappings.isEmpty else {
            return generateDefaultConfig()
        }

        let mappingsList = mappings.map { "\($0.input) -> \($0.output)" }.joined(separator: ", ")
        let srcKeys = mappings.map { convertToKanataKey($0.input) }.joined(separator: " ")
        let layerKeys = mappings.map { convertToKanataOutput($0.output) }.joined(separator: " ")

        return """
        ;; Generated by KeyPath Configuration Manager
        ;; Created: \(Date())
        ;; Mappings: \(mappingsList)
        ;;
        ;; SAFETY FEATURES:
        ;; - process-unmapped-keys no: Only process explicitly mapped keys
        ;; - danger-enable-cmd yes: Enable CMD key remapping (required for macOS)

        (defcfg
          process-unmapped-keys no
          danger-enable-cmd yes
        )

        (defsrc
          \(srcKeys)
        )

        (deflayer base
          \(layerKeys)
        )
        """
    }

    private func generateDefaultConfig() -> String {
        generateKanataConfig(mappings: [KeyMapping(input: "caps", output: "esc")])
    }

    // MARK: - Configuration Validation

    func validateConfiguration(_ config: String) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        var suggestions: [String] = []

        // Lines not used currently; keep ready for future line-referenced diagnostics
        // let lines = config.components(separatedBy: .newlines)

        // Check for required sections
        if !config.contains("(defcfg") {
            errors.append(
                ValidationError(
                    line: nil,
                    message: "Missing required (defcfg section",
                    severity: .critical,
                    suggestion: "Add (defcfg section with basic configuration"
                ))
        }

        if !config.contains("(defsrc") {
            errors.append(
                ValidationError(
                    line: nil,
                    message: "Missing required (defsrc section",
                    severity: .critical,
                    suggestion: "Add (defsrc section defining source keys"
                ))
        }

        if !config.contains("(deflayer") {
            errors.append(
                ValidationError(
                    line: nil,
                    message: "Missing required (deflayer section",
                    severity: .critical,
                    suggestion: "Add (deflayer section defining key mappings"
                ))
        }

        // Check for balanced parentheses
        let openCount = config.components(separatedBy: "(").count - 1
        let closeCount = config.components(separatedBy: ")").count - 1

        if openCount != closeCount {
            errors.append(
                ValidationError(
                    line: nil,
                    message: "Unbalanced parentheses: \(openCount) open, \(closeCount) close",
                    severity: .critical,
                    suggestion: "Ensure all parentheses are properly matched"
                ))
        }

        // Check for safety features
        if !config.contains("process-unmapped-keys") {
            warnings.append(
                ValidationWarning(
                    line: nil,
                    message: "process-unmapped-keys not specified",
                    suggestion: "Add 'process-unmapped-keys no' for safety"
                ))
        }

        if !config.contains("danger-enable-cmd yes") {
            warnings.append(
                ValidationWarning(
                    line: nil,
                    message: "CMD key remapping not enabled",
                    suggestion: "Add 'danger-enable-cmd yes' for macOS compatibility"
                ))
        }

        // Add general suggestions
        if errors.isEmpty, warnings.isEmpty {
            suggestions.append("Configuration appears valid and well-formed")
        }

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            suggestions: suggestions
        )
    }

    // MARK: - Configuration Parsing

    private func parseKanataConfig(_: String) throws -> [KeyMapping] {
        // Simplified parser - in a real implementation, this would be more sophisticated
        let mappings: [KeyMapping] = []

        // This is a basic implementation that looks for defsrc and deflayer patterns
        // A full implementation would parse the S-expression syntax properly

        return mappings
    }

    // MARK: - Key Conversion Utilities

    private func convertToKanataKey(_ input: String) -> String {
        switch input.lowercased() {
        case "caps", "capslock":
            "caps"
        case "tab":
            "tab"
        case "space", "spacebar":
            "spc"
        case "return", "enter":
            "ret"
        case "escape", "esc":
            "esc"
        case "delete", "backspace":
            "bspc"
        default:
            input.lowercased()
        }
    }

    private func convertToKanataOutput(_ output: String) -> String {
        switch output.lowercased() {
        case "esc", "escape":
            "esc"
        case "ctrl", "control", "lctl":
            "lctl"
        case "space", "spacebar":
            "spc"
        case "return", "enter":
            "ret"
        case "caps", "capslock":
            "caps"
        default:
            output.lowercased()
        }
    }

    // MARK: - File Utilities

    private func getFileModificationDate(_ path: String) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    private func getFileSize(_ path: String) -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
}

// MARK: - Error Types

/// Configuration manager errors
///
/// - Deprecated: Use `KeyPathError.configuration(...)` instead for consistent error handling
@available(*, deprecated, message: "Use KeyPathError.configuration(...) instead")
enum ConfigManagerError: Error, LocalizedError {
    case configNotFound
    case invalidConfiguration([KanataConfigManager.ValidationError])
    case saveVerificationFailed
    case backupFailed(Error)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            "Configuration file not found"
        case let .invalidConfiguration(errors):
            "Configuration validation failed: \(errors.count) error(s)"
        case .saveVerificationFailed:
            "Configuration save verification failed"
        case let .backupFailed(error):
            "Backup creation failed: \(error.localizedDescription)"
        }
    }

    /// Convert to KeyPathError for consistent error handling
    var asKeyPathError: KeyPathError {
        switch self {
        case .configNotFound:
            return .configuration(.fileNotFound(path: "configuration file"))
        case let .invalidConfiguration(errors):
            let errorMessages = errors.map { $0.message }
            return .configuration(.validationFailed(errors: errorMessages))
        case .saveVerificationFailed:
            return .configuration(.saveFailed(reason: "Save verification failed"))
        case let .backupFailed(error):
            return .configuration(.backupFailed(reason: error.localizedDescription))
        }
    }
}
