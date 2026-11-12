import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import Synchronization
import XCTest

final class KanataConfigMigrationServiceTests: XCTestCase {
    var tempDirectory: URL!
    var destination: URL!
    var migrationService: KanataConfigMigrationService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        destination = tempDirectory.appendingPathComponent(".config/keypath/keypath.kbd")
        migrationService = KanataConfigMigrationService(configPath: destination.path)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testDetectExistingKanataConfigs() throws {
        let home = tempDirectory.appendingPathComponent("home")
        let system = tempDirectory.appendingPathComponent("system")
        let expected: [(url: URL, displayName: String)] = [
            (home.appendingPathComponent(".config/kanata/kanata.kbd"), "~/.config/kanata/kanata.kbd"),
            (home.appendingPathComponent(".config/keypath/config.kbd"), "~/.config/keypath/config.kbd"),
            (system.appendingPathComponent("config.kbd"), "\(system.path)/config.kbd"),
            (home.appendingPathComponent(".kanata.kbd"), "~/.kanata.kbd")
        ]
        let canonicalConfig = home.appendingPathComponent(".config/keypath/keypath.kbd")
        for config in expected.map(\.url) + [canonicalConfig] {
            try FileManager.default.createDirectory(
                at: config.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "(defcfg\n)\n".write(to: config, atomically: true, encoding: .utf8)
        }

        let detected = WizardSystemPaths.detectExistingKanataConfigs(
            homeDirectory: home.path,
            systemConfigDirectory: system.path
        )
        XCTAssertEqual(detected.map(\.path), expected.map(\.url.path))
        XCTAssertEqual(detected.map(\.displayName), expected.map(\.displayName))
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

        // Verify content includes the include line
        let destContent = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(destContent.contains("(include keypath-apps.kbd)"), "Should prepend include line")
        XCTAssertTrue(destContent.contains("deflayer base"), "Should preserve original content")

        XCTAssertNil(backupPath, "A fresh destination needs no backup")
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

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.path),
            sourcePath.path
        )
    }

    func testConcurrentMigrationsKeepDestinationsAndBackupsSeparate() throws {
        let fixtures = try (0 ..< 2).map { index in
            let root = tempDirectory.appendingPathComponent("migration-\(index)")
            let source = root.appendingPathComponent("kanata.kbd")
            let config = root.appendingPathComponent(".config/keypath/keypath.kbd")
            let sourceContent = ";; imported config \(index)\n(defcfg\n)\n"
            let originalContent = ";; previous config \(index)\n(defcfg\n)\n"
            try FileManager.default.createDirectory(
                at: config.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try sourceContent.write(to: source, atomically: true, encoding: .utf8)
            try originalContent.write(to: config, atomically: true, encoding: .utf8)
            return (source: source, config: config, sourceContent: sourceContent, originalContent: originalContent)
        }
        let results = Mutex<[Int: Result<String?, Error>]>([:])

        DispatchQueue.concurrentPerform(iterations: fixtures.count) { index in
            let fixture = fixtures[index]
            let service = KanataConfigMigrationService(configPath: fixture.config.path)
            let result = Result {
                try service.migrateConfig(from: fixture.source.path, method: .copy, prependInclude: false)
            }
            results.withLock { $0[index] = result }
        }

        let migrations = results.withLock { $0 }
        for (index, fixture) in fixtures.enumerated() {
            let result = try XCTUnwrap(migrations[index])
            let backupPath = try XCTUnwrap(result.get())
            let backupDirectory = fixture.config.deletingLastPathComponent().appendingPathComponent(".backups")
            XCTAssertEqual((backupPath as NSString).deletingLastPathComponent, backupDirectory.path)
            XCTAssertEqual(try String(contentsOfFile: backupPath, encoding: .utf8), fixture.originalContent)
            XCTAssertEqual(try String(contentsOf: fixture.config, encoding: .utf8), fixture.sourceContent)
            XCTAssertEqual(try String(contentsOf: fixture.source, encoding: .utf8), fixture.sourceContent)
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
