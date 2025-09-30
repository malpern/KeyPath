import Foundation

/// Service for managing configuration backups to protect against corruption
///
/// This service provides:
/// - Automatic backup creation when user opens config for editing
/// - Rolling backup retention (keeps last 5 valid backups)
/// - Recovery from backups when corruption is detected
/// - Validation of config files before backup to ensure we only store valid configs
public final class ConfigBackupManager {
    // MARK: - Properties

    private let backupDirectory: String
    private let configPath: String
    private let maxBackups = 5

    // MARK: - Initialization

    public init(configPath: String) {
        self.configPath = configPath
        let configDir = (configPath as NSString).deletingLastPathComponent
        backupDirectory = "\(configDir)/.backups"

        // Create backup directory if needed
        createBackupDirectoryIfNeeded()
    }

    // MARK: - Public Methods

    /// Create a backup of the current config file before user editing
    /// Returns true if backup was created, false if current config is invalid
    public func createPreEditBackup() -> Bool {
        guard FileManager.default.fileExists(atPath: configPath) else {
            AppLogger.shared.log("⚠️ [BackupManager] No config file to backup at: \(configPath)")
            return false
        }

        do {
            // Read current config content
            let content = try String(contentsOfFile: configPath, encoding: .utf8)

            // Validate content before backing up (don't backup corrupted configs)
            guard isValidConfig(content: content) else {
                AppLogger.shared.log("❌ [BackupManager] Current config is invalid - skipping backup")
                return false
            }

            // Create timestamped backup filename
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "T", with: "_")
                .replacingOccurrences(of: "Z", with: "")

            let backupFileName = "keypath_\(timestamp).kbd"
            let backupPath = "\(backupDirectory)/\(backupFileName)"

            // Write backup file
            try content.write(toFile: backupPath, atomically: true, encoding: .utf8)

            AppLogger.shared.log("✅ [BackupManager] Created pre-edit backup: \(backupFileName)")

            // Cleanup old backups
            cleanupOldBackups()

            return true

        } catch {
            AppLogger.shared.log("❌ [BackupManager] Failed to create backup: \(error)")
            return false
        }
    }

    /// Get list of available backup files, sorted by date (newest first)
    public func getAvailableBackups() -> [BackupInfo] {
        guard FileManager.default.fileExists(atPath: backupDirectory) else {
            return []
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: backupDirectory)
            let backupFiles = files.filter { $0.hasSuffix(".kbd") }

            var backups: [BackupInfo] = []

            for file in backupFiles {
                let fullPath = "\(backupDirectory)/\(file)"

                if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
                   let modDate = attributes[.modificationDate] as? Date,
                   let size = attributes[.size] as? Int64 {
                    backups.append(BackupInfo(
                        filename: file,
                        fullPath: fullPath,
                        createdAt: modDate,
                        sizeBytes: size
                    ))
                }
            }

            // Sort by creation date, newest first
            return backups.sorted { $0.createdAt > $1.createdAt }

        } catch {
            AppLogger.shared.log("❌ [BackupManager] Failed to list backups: \(error)")
            return []
        }
    }

    /// Restore config from a specific backup
    public func restoreFromBackup(_ backup: BackupInfo) throws {
        guard FileManager.default.fileExists(atPath: backup.fullPath) else {
            throw KeyPathError.configuration(.backupNotFound(path: backup.fullPath))
        }

        // Read backup content
        let content = try String(contentsOfFile: backup.fullPath, encoding: .utf8)

        // Validate backup content
        guard isValidConfig(content: content) else {
            throw KeyPathError.configuration(.corruptedFormat(details: "Invalid backup: \(backup.filename)"))
        }

        // Create a backup of current config (if it exists) before restoring
        if FileManager.default.fileExists(atPath: configPath) {
            let currentBackupPath = "\(backupDirectory)/before_restore_\(Date().timeIntervalSince1970).kbd"
            try? FileManager.default.copyItem(atPath: configPath, toPath: currentBackupPath)
        }

        // Restore the backup
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)

        AppLogger.shared.log("✅ [BackupManager] Restored config from backup: \(backup.filename)")
    }

    /// Find and restore the most recent valid backup
    public func restoreLatestValidBackup() -> Bool {
        let backups = getAvailableBackups()

        for backup in backups {
            do {
                let content = try String(contentsOfFile: backup.fullPath, encoding: .utf8)
                if isValidConfig(content: content) {
                    try restoreFromBackup(backup)
                    AppLogger.shared.log("✅ [BackupManager] Auto-restored from latest valid backup: \(backup.filename)")
                    return true
                }
            } catch {
                AppLogger.shared.log("⚠️ [BackupManager] Failed to check backup \(backup.filename): \(error)")
                continue
            }
        }

        AppLogger.shared.log("❌ [BackupManager] No valid backups found for auto-restore")
        return false
    }

    // MARK: - Private Methods

    private func createBackupDirectoryIfNeeded() {
        guard !FileManager.default.fileExists(atPath: backupDirectory) else { return }

        do {
            try FileManager.default.createDirectory(
                atPath: backupDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            AppLogger.shared.log("✅ [BackupManager] Created backup directory: \(backupDirectory)")
        } catch {
            AppLogger.shared.log("❌ [BackupManager] Failed to create backup directory: \(error)")
        }
    }

    private func cleanupOldBackups() {
        let backups = getAvailableBackups()

        // Keep only the most recent maxBackups
        if backups.count > maxBackups {
            let backupsToDelete = Array(backups.dropFirst(maxBackups))

            for backup in backupsToDelete {
                do {
                    try FileManager.default.removeItem(atPath: backup.fullPath)
                    AppLogger.shared.log("🗑️ [BackupManager] Deleted old backup: \(backup.filename)")
                } catch {
                    AppLogger.shared.log("⚠️ [BackupManager] Failed to delete old backup \(backup.filename): \(error)")
                }
            }
        }
    }

    /// Basic validation to ensure config has proper Kanata syntax
    private func isValidConfig(content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty config is invalid
        guard !trimmed.isEmpty else { return false }

        // Must contain basic Kanata structure
        let hasDefcfg = trimmed.contains("(defcfg")
        _ = trimmed.contains("(defsrc") || trimmed.isEmpty // Allow empty defsrc
        _ = trimmed.contains("(deflayer") || trimmed.isEmpty // Allow empty deflayer

        // Basic parentheses balance check
        let openParens = trimmed.filter { $0 == "(" }.count
        let closeParens = trimmed.filter { $0 == ")" }.count
        let balancedParens = openParens == closeParens

        let isValid = hasDefcfg && balancedParens

        if !isValid {
            AppLogger.shared.log("❌ [BackupManager] Config validation failed - defcfg: \(hasDefcfg), balanced: \(balancedParens)")
        }

        return isValid
    }
}

// MARK: - Supporting Types

public struct BackupInfo {
    public let filename: String
    public let fullPath: String
    public let createdAt: Date
    public let sizeBytes: Int64

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// (Removed deprecated ConfigBackupError - now using KeyPathError directly)
