import Foundation
import KeyPathCore

/// Service for migrating existing Kanata configurations to KeyPath
/// Handles safe copying, symlinking, and include line prepending without parsing configs
public final class KanataConfigMigrationService {
    // MARK: - Types

    public enum MigrationError: LocalizedError {
        case sourceNotFound(String)
        case destinationExists(String)
        case copyFailed(String, Error)
        case symlinkFailed(String, Error)
        case readFailed(String, Error)
        case writeFailed(String, Error)
        case backupFailed(String, Error)
        case includeAlreadyPresent

        public var errorDescription: String? {
            switch self {
            case let .sourceNotFound(path):
                "Source config file not found: \(path)"
            case let .destinationExists(path):
                "Destination already exists: \(path)"
            case let .copyFailed(path, error):
                "Failed to copy config from \(path): \(error.localizedDescription)"
            case let .symlinkFailed(path, error):
                "Failed to create symlink from \(path): \(error.localizedDescription)"
            case let .readFailed(path, error):
                "Failed to read config from \(path): \(error.localizedDescription)"
            case let .writeFailed(path, error):
                "Failed to write config to \(path): \(error.localizedDescription)"
            case let .backupFailed(path, error):
                "Failed to create backup at \(path): \(error.localizedDescription)"
            case .includeAlreadyPresent:
                "Include line already present in config"
            }
        }
    }

    public enum MigrationMethod {
        case copy
        case symlink
    }

    // MARK: - Properties

    private let fileManager = FileManager.default
    // Use the same config path as ConfigurationService (KeyPathConstants.Config.mainConfigPath)
    // which is ~/.config/keypath/keypath.kbd, not Application Support
    private let keyPathConfigPath = WizardSystemPaths.userConfigPath
    private let keyPathConfigDirectory = WizardSystemPaths.userConfigDirectory
    private let includeLine = "(include keypath-apps.kbd)"

    // MARK: - Public Methods

    /// Migrate an existing Kanata config to KeyPath's location
    /// - Parameters:
    ///   - sourcePath: Path to existing Kanata config file
    ///   - method: Whether to copy or symlink
    ///   - prependInclude: If true, prepends include line if missing
    /// - Returns: Path to backup file if one was created
    /// - Throws: MigrationError if migration fails
    @discardableResult
    public func migrateConfig(
        from sourcePath: String,
        method: MigrationMethod,
        prependInclude: Bool = true
    ) throws -> String? {
        // Validate source exists
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw MigrationError.sourceNotFound(sourcePath)
        }

        // Ensure KeyPath config directory exists
        try createKeyPathConfigDirectoryIfNeeded()

        // Create backup if destination exists
        var backupPath: String?
        if fileManager.fileExists(atPath: keyPathConfigPath) {
            backupPath = try createBackup(of: keyPathConfigPath)
        }

        // Perform migration
        switch method {
        case .copy:
            try copyConfig(from: sourcePath, to: keyPathConfigPath, prependInclude: prependInclude)
        case .symlink:
            try createSymlink(from: sourcePath, to: keyPathConfigPath)
            // For symlinks, we can't modify the file, so skip include prepending
            // User will need to add it manually or we'll handle it differently
        }

        return backupPath
    }

    /// Check if config already has the include line
    /// - Parameter configPath: Path to config file
    /// - Returns: True if include line is present
    public func hasIncludeLine(configPath: String) -> Bool {
        guard fileManager.fileExists(atPath: configPath) else { return false }

        do {
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            return content.contains(includeLine)
        } catch {
            AppLogger.shared.log("⚠️ [MigrationService] Failed to check include line: \(error)")
            return false
        }
    }

    /// Prepend include line to config if missing
    /// - Parameter configPath: Path to config file
    /// - Returns: Path to backup file if one was created
    /// - Throws: MigrationError if operation fails
    @discardableResult
    public func prependIncludeLineIfMissing(to configPath: String) throws -> String? {
        guard fileManager.fileExists(atPath: configPath) else {
            throw MigrationError.sourceNotFound(configPath)
        }

        // Check if already present
        if hasIncludeLine(configPath: configPath) {
            throw MigrationError.includeAlreadyPresent
        }

        // Create backup
        let backupPath = try createBackup(of: configPath)

        // Read existing content
        let existingContent: String
        do {
            existingContent = try String(contentsOfFile: configPath, encoding: .utf8)
        } catch {
            throw MigrationError.readFailed(configPath, error)
        }

        // Prepend include line
        let newContent = "\(includeLine)\n\n\(existingContent)"

        // Write back
        do {
            try newContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            AppLogger.shared.log("✅ [MigrationService] Prepended include line to: \(configPath)")
        } catch {
            throw MigrationError.writeFailed(configPath, error)
        }

        return backupPath
    }

    // MARK: - Private Methods

    private func createKeyPathConfigDirectoryIfNeeded() throws {
        guard !fileManager.fileExists(atPath: keyPathConfigDirectory) else { return }

        try fileManager.createDirectory(
            atPath: keyPathConfigDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        AppLogger.shared.log("✅ [MigrationService] Created KeyPath config directory: \(keyPathConfigDirectory)")
    }

    private func copyConfig(from sourcePath: String, to destPath: String, prependInclude: Bool) throws {
        // Read source content
        let sourceContent: String
        do {
            sourceContent = try String(contentsOfFile: sourcePath, encoding: .utf8)
        } catch {
            throw MigrationError.readFailed(sourcePath, error)
        }

        // Prepend include if needed and requested
        let finalContent: String = if prependInclude, !hasIncludeLine(configPath: sourcePath) {
            "\(includeLine)\n\n\(sourceContent)"
        } else {
            sourceContent
        }

        // Write to destination
        do {
            try finalContent.write(toFile: destPath, atomically: true, encoding: .utf8)
            AppLogger.shared.log("✅ [MigrationService] Copied config from \(sourcePath) to \(destPath)")
        } catch {
            throw MigrationError.writeFailed(destPath, error)
        }
    }

    private func createSymlink(from sourcePath: String, to destPath: String) throws {
        // Remove existing file/symlink if present
        if fileManager.fileExists(atPath: destPath) || fileManager.fileExists(atPath: destPath) {
            try? fileManager.removeItem(atPath: destPath)
        }

        // Create symlink
        do {
            try fileManager.createSymbolicLink(atPath: destPath, withDestinationPath: sourcePath)
            AppLogger.shared.log("✅ [MigrationService] Created symlink from \(sourcePath) to \(destPath)")
        } catch {
            throw MigrationError.symlinkFailed(sourcePath, error)
        }
    }

    private func createBackup(of configPath: String) throws -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .replacingOccurrences(of: "Z", with: "")

        let backupDir = "\(keyPathConfigDirectory)/.backups"
        let backupPath = "\(backupDir)/migration_backup_\(timestamp).kbd"

        // Create backup directory if needed
        if !fileManager.fileExists(atPath: backupDir) {
            try fileManager.createDirectory(
                atPath: backupDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }

        // Copy to backup
        do {
            try fileManager.copyItem(atPath: configPath, toPath: backupPath)
            AppLogger.shared.log("✅ [MigrationService] Created backup: \(backupPath)")
            return backupPath
        } catch {
            throw MigrationError.backupFailed(backupPath, error)
        }
    }
}
