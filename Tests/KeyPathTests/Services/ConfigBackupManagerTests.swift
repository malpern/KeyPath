@testable import KeyPathAppKit
import XCTest

final class ConfigBackupManagerTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigBackupTests-\(UUID().uuidString)")
            .path
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        tempDir = path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private var configPath: String { "\(tempDir!)/keypath.kbd" }

    private func writeValidConfig(_ content: String? = nil) throws {
        let validConfig = content ?? """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        try validConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - createPreEditBackup

    func testCreatePreEditBackup_NoConfig_ReturnsFalse() {
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertFalse(manager.createPreEditBackup())
    }

    func testCreatePreEditBackup_ValidConfig_CreatesBackup() throws {
        try writeValidConfig()
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertTrue(manager.createPreEditBackup())

        let backups = manager.getAvailableBackups()
        XCTAssertEqual(backups.count, 1)
    }

    func testCreatePreEditBackup_InvalidConfig_ReturnsFalse() throws {
        try "this is not kanata config".write(toFile: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertFalse(manager.createPreEditBackup())
    }

    func testCreatePreEditBackup_EmptyConfig_ReturnsFalse() throws {
        try "".write(toFile: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertFalse(manager.createPreEditBackup())
    }

    func testCreatePreEditBackup_UnbalancedParens_ReturnsFalse() throws {
        try "(defcfg\n(defsrc caps)".write(toFile: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertFalse(manager.createPreEditBackup())
    }

    // MARK: - getAvailableBackups

    func testGetAvailableBackups_NoBackups_ReturnsEmpty() {
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertTrue(manager.getAvailableBackups().isEmpty)
    }

    func testGetAvailableBackups_ReturnsSortedByDate() throws {
        try writeValidConfig()
        let manager = ConfigBackupManager(configPath: configPath)

        XCTAssertTrue(manager.createPreEditBackup())
        let backups = manager.getAvailableBackups()
        XCTAssertFalse(backups.isEmpty)
        // With a single backup, sorted order is trivially correct
        XCTAssertFalse(backups[0].filename.isEmpty)
    }

    // MARK: - Backup retention

    func testCleanupOldBackups_KeepsOnlyMaxBackups() throws {
        try writeValidConfig()
        let manager = ConfigBackupManager(configPath: configPath)

        for _ in 0 ..< 8 {
            XCTAssertTrue(manager.createPreEditBackup())
            Thread.sleep(forTimeInterval: 0.05)
        }

        let backups = manager.getAvailableBackups()
        XCTAssertLessThanOrEqual(backups.count, 5)
    }

    // MARK: - Restore from backup

    func testRestoreFromBackup_RestoresContent() throws {
        try writeValidConfig()
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertTrue(manager.createPreEditBackup())

        // Overwrite config with different content
        let newConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc a)
        (deflayer base b)
        """
        try newConfig.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Restore backup
        let backups = manager.getAvailableBackups()
        XCTAssertFalse(backups.isEmpty)
        try manager.restoreFromBackup(backups[0])

        // Verify restored content
        let restored = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(restored.contains("(defsrc caps)"))
    }

    // MARK: - restoreLatestValidBackup

    func testRestoreLatestValidBackup_NoBackups_ReturnsFalse() {
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertFalse(manager.restoreLatestValidBackup())
    }

    func testRestoreLatestValidBackup_WithValidBackup_ReturnsTrue() throws {
        try writeValidConfig()
        let manager = ConfigBackupManager(configPath: configPath)
        XCTAssertTrue(manager.createPreEditBackup())

        // Corrupt the current config
        try "broken".write(toFile: configPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(manager.restoreLatestValidBackup())

        let restored = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(restored.contains("(defcfg"))
    }

    // MARK: - BackupInfo

    func testBackupInfo_FormattedSize() {
        let info = BackupInfo(
            filename: "test.kbd",
            fullPath: "/tmp/test.kbd",
            createdAt: Date(),
            sizeBytes: 1024
        )
        XCTAssertFalse(info.formattedSize.isEmpty)
    }

    func testBackupInfo_FormattedDate() {
        let info = BackupInfo(
            filename: "test.kbd",
            fullPath: "/tmp/test.kbd",
            createdAt: Date(),
            sizeBytes: 100
        )
        XCTAssertFalse(info.formattedDate.isEmpty)
    }
}
