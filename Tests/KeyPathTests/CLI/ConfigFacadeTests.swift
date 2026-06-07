@testable import KeyPathAppKit
import XCTest

final class ConfigFacadeTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigFacadeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testBackupConfigSnapshotsResolvedSymlinkDirectory() throws {
        let liveTarget = tempRoot.appendingPathComponent("dotfiles-keypath", isDirectory: true)
        let configLink = tempRoot.appendingPathComponent(".config/keypath", isDirectory: true)
        let backup = tempRoot.appendingPathComponent("backup", isDirectory: true)

        try createSymlinkedConfig(link: configLink, target: liveTarget)
        try "original".write(to: liveTarget.appendingPathComponent("RuleCollections.json"), atomically: true, encoding: .utf8)

        let facade = ConfigFacade(configDirectory: configLink.path)
        let result = try facade.backupConfig(outputPath: backup.path)

        XCTAssertEqual(result.sourcePath, configLink.path)
        XCTAssertEqual(result.backupPath, backup.path)
        XCTAssertEqual(result.copiedItems, ["RuleCollections.json"])
        XCTAssertFalse(isSymbolicLink(backup), "Backup must be an immutable directory snapshot, not a symlink.")

        try "mutated".write(to: liveTarget.appendingPathComponent("RuleCollections.json"), atomically: true, encoding: .utf8)
        let restored = try String(contentsOf: backup.appendingPathComponent("RuleCollections.json"), encoding: .utf8)
        XCTAssertEqual(restored, "original")
    }

    func testRestoreConfigPreservesDestinationSymlinkAndRestoresSnapshotContents() async throws {
        let liveTarget = tempRoot.appendingPathComponent("dotfiles-keypath", isDirectory: true)
        let configLink = tempRoot.appendingPathComponent(".config/keypath", isDirectory: true)
        let backup = tempRoot.appendingPathComponent("backup", isDirectory: true)

        try createSymlinkedConfig(link: configLink, target: liveTarget)
        try "original".write(to: liveTarget.appendingPathComponent("RuleCollections.json"), atomically: true, encoding: .utf8)

        let facade = ConfigFacade(configDirectory: configLink.path)
        _ = try facade.backupConfig(outputPath: backup.path)

        try "mutated".write(to: liveTarget.appendingPathComponent("RuleCollections.json"), atomically: true, encoding: .utf8)
        _ = try await facade.restoreConfig(from: backup.path, reload: false)

        let restored = try String(contentsOf: liveTarget.appendingPathComponent("RuleCollections.json"), encoding: .utf8)
        XCTAssertEqual(restored, "original")
        XCTAssertTrue(isSymbolicLink(configLink), "Restore should preserve the configured ~/.config/keypath symlink.")
    }

    func testRestoreConfigRejectsBackupPathThatResolvesToActiveConfigDirectory() async throws {
        let liveTarget = tempRoot.appendingPathComponent("dotfiles-keypath", isDirectory: true)
        let configLink = tempRoot.appendingPathComponent(".config/keypath", isDirectory: true)

        try createSymlinkedConfig(link: configLink, target: liveTarget)

        let facade = ConfigFacade(configDirectory: configLink.path)
        do {
            _ = try await facade.restoreConfig(from: liveTarget.path, reload: false)
            XCTFail("Expected restore to reject backup paths that resolve to the active config directory.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("active config directory"))
        }
    }

    func testApplyConfigurationDryRunDoesNotWriteActiveConfigOrReload() async throws {
        let configDirectory = tempRoot.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("keypath.kbd")
        try "original config".write(to: configFile, atomically: true, encoding: .utf8)

        let reloadProbe = ReloadProbe()
        let facade = ConfigFacade(
            configDirectory: configDirectory.path,
            ruleCollectionLoader: { [] },
            customRuleLoader: { [] },
            reloadHandler: { await reloadProbe.reload() }
        )

        let result = try await facade.applyConfiguration(dryRun: true)
        let reloadCount = await reloadProbe.count

        XCTAssertEqual(result.dryRun, true)
        XCTAssertFalse(result.reloadSuccess)
        XCTAssertEqual(reloadCount, 0)
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), "original config")

        let activeItems = try FileManager.default.contentsOfDirectory(atPath: configDirectory.path)
        XCTAssertEqual(activeItems, ["keypath.kbd"])
    }

    private func createSymlinkedConfig(link: URL, target: URL) throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType
        else {
            return false
        }
        return type == .typeSymbolicLink
    }
}

private actor ReloadProbe {
    private var reloadCount = 0

    var count: Int {
        reloadCount
    }

    func reload() async -> Bool {
        reloadCount += 1
        return true
    }
}
