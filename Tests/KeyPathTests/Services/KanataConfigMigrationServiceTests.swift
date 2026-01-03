import Foundation
import KeyPathCore
import XCTest

@testable import KeyPathAppKit

final class KanataConfigMigrationServiceTests: XCTestCase {
    var tempDirectory: URL!
    var migrationService: KanataConfigMigrationService!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Set test environment override for paths
        setenv("KEYPATH_HOME_DIR_OVERRIDE", tempDirectory.path, 1)

        migrationService = KanataConfigMigrationService()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        unsetenv("KEYPATH_HOME_DIR_OVERRIDE")
        super.tearDown()
    }

    func testDetectExistingKanataConfigs() {
        // Create test configs in common locations
        let configDir1 = tempDirectory.appendingPathComponent(".config/kanata")
        let configDir2 = tempDirectory.appendingPathComponent(".config/keypath")
        try? FileManager.default.createDirectory(at: configDir1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: configDir2, withIntermediateDirectories: true)

        let config1 = configDir1.appendingPathComponent("kanata.kbd")
        let config2 = configDir2.appendingPathComponent("config.kbd")
        let config3 = tempDirectory.appendingPathComponent(".kanata.kbd")

        try? "(defcfg\n)\n".write(to: config1, atomically: true, encoding: .utf8)
        try? "(defcfg\n)\n".write(to: config2, atomically: true, encoding: .utf8)
        try? "(defcfg\n)\n".write(to: config3, atomically: true, encoding: .utf8)

        let detected = WizardSystemPaths.detectExistingKanataConfigs()
        XCTAssertGreaterThanOrEqual(detected.count, 3, "Should detect all test configs")
    }

    func testMigrateConfigCopy() throws {
        // Create source config
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourcePath = sourceDir.appendingPathComponent("kanata.kbd")
        let sourceContent = "(defcfg\n)\n(deflayer base\n  a b c\n)"
        try sourceContent.write(to: sourcePath, atomically: true, encoding: .utf8)

        // Migrate
        let backupPath = try migrationService.migrateConfig(
            from: sourcePath.path,
            method: .copy,
            prependInclude: true
        )

        // Verify destination exists
        let destPath = WizardSystemPaths.userConfigPath
        XCTAssertTrue(FileManager.default.fileExists(atPath: destPath), "Config should be copied")

        // Verify content includes the include line
        let destContent = try String(contentsOfFile: destPath, encoding: .utf8)
        XCTAssertTrue(destContent.contains("(include keypath-apps.kbd)"), "Should prepend include line")
        XCTAssertTrue(destContent.contains("deflayer base"), "Should preserve original content")

        // Verify backup was created if destination existed
        if backupPath != nil {
            XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath!), "Backup should exist")
        }
    }

    func testMigrateConfigSymlink() throws {
        // Create source config
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourcePath = sourceDir.appendingPathComponent("kanata.kbd")
        let sourceContent = "(defcfg\n)\n"
        try sourceContent.write(to: sourcePath, atomically: true, encoding: .utf8)

        // Migrate with symlink
        try migrationService.migrateConfig(
            from: sourcePath.path,
            method: .symlink,
            prependInclude: false
        )

        // Verify symlink exists
        let destPath = WizardSystemPaths.userConfigPath
        let attributes = try FileManager.default.attributesOfItem(atPath: destPath)
        XCTAssertNotNil(attributes[FileAttributeKey.type] as? FileAttributeType)
        if let type = attributes[FileAttributeKey.type] as? FileAttributeType {
            XCTAssertEqual(type, .typeSymbolicLink, "Should be a symlink")
        }
    }

    func testHasIncludeLine() throws {
        // Create config with include line
        let configPath = tempDirectory.appendingPathComponent("test.kbd")
        let contentWithInclude = "(include keypath-apps.kbd)\n(defcfg\n)\n"
        try contentWithInclude.write(to: configPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(migrationService.hasIncludeLine(configPath: configPath.path))

        // Create config without include line
        let configPath2 = tempDirectory.appendingPathComponent("test2.kbd")
        let contentWithoutInclude = "(defcfg\n)\n"
        try contentWithoutInclude.write(to: configPath2, atomically: true, encoding: .utf8)

        XCTAssertFalse(migrationService.hasIncludeLine(configPath: configPath2.path))
    }

    func testPrependIncludeLineIfMissing() throws {
        // Create config without include
        let configPath = tempDirectory.appendingPathComponent("test.kbd")
        let originalContent = "(defcfg\n)\n(deflayer base\n  a b c\n)"
        try originalContent.write(to: configPath, atomically: true, encoding: .utf8)

        // Prepend include
        let backupPath = try migrationService.prependIncludeLineIfMissing(to: configPath.path)

        // Verify include was added
        let newContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(newContent.hasPrefix("(include keypath-apps.kbd)"), "Should prepend include")
        XCTAssertTrue(newContent.contains("deflayer base"), "Should preserve original content")

        // Verify backup was created
        XCTAssertNotNil(backupPath)
        if let backup = backupPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: backup), "Backup should exist")
        }
    }

    func testPrependIncludeLineAlreadyPresent() throws {
        // Create config with include already present
        let configPath = tempDirectory.appendingPathComponent("test.kbd")
        let contentWithInclude = "(include keypath-apps.kbd)\n(defcfg\n)\n"
        try contentWithInclude.write(to: configPath, atomically: true, encoding: .utf8)

        // Should throw error
        XCTAssertThrowsError(try migrationService.prependIncludeLineIfMissing(to: configPath.path)) { error in
            guard let migrationError = error as? KanataConfigMigrationService.MigrationError,
                  case .includeAlreadyPresent = migrationError
            else {
                XCTFail("Expected MigrationError.includeAlreadyPresent")
                return
            }
        }
    }

    func testMigrationErrorSourceNotFound() {
        XCTAssertThrowsError(
            try migrationService.migrateConfig(
                from: "/nonexistent/path.kbd",
                method: .copy,
                prependInclude: true
            )
        ) { error in
            if let migrationError = error as? KanataConfigMigrationService.MigrationError {
                if case .sourceNotFound = migrationError {
                    // Expected
                } else {
                    XCTFail("Expected sourceNotFound error")
                }
            } else {
                XCTFail("Expected MigrationError")
            }
        }
    }
}
