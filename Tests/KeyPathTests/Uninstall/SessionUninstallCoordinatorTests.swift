@testable import KeyPathAppKit
import XCTest
import KeyPathInstallationWizard

@MainActor
final class SessionUninstallCoordinatorTests: XCTestCase {
    private var root: URL!
    private var app: URL!
    private var defaults: UserDefaults!
    private var domain: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = root.appendingPathComponent("Applications/KeyPath.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.keypath.KeyPath", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        domain = "KeyPath-UninstallTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: domain)!
        defaults.set(true, forKey: "wizard_has_seen_welcome")
        try write(".config/keypath/keypath.kbd", "rules")
        try write("Library/Application Support/KeyPath/rules.json", "saved rules")
        try write("Library/Caches/com.keypath.KeyPath/cache", "cached")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ value: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Downloads"), includingPropertiesForKeys: nil)
    }

    func testBacksUpBeforeRemovingSettingsAndTrashesOnlyCurrentApp() async throws {
        var trashed: URL?
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
            prepare: { true }, resume: { XCTFail("Unexpected failure") }, trash: { url in
                trashed = url
                let backup = try XCTUnwrap(self.backups().first)
                XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("0-keypath/keypath.kbd"), encoding: .utf8), "rules")
                let prefs = try Data(contentsOf: backup.appendingPathComponent("preferences.plist"))
                let decoded = try PropertyListSerialization.propertyList(from: prefs, format: nil) as? [String: Any]
                XCTAssertEqual(decoded?["wizard_has_seen_welcome"] as? Bool, true)
                try FileManager.default.removeItem(at: url)
            })
        let result = await coordinator.performUninstall(deleteConfig: true, removeVirtualHID: false, allowAdminFallback: false)
        XCTAssertTrue(result.success, result.failureReason ?? "")
        XCTAssertEqual(trashed, app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".config/keypath").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/Application Support/KeyPath").path))
        XCTAssertFalse(defaults.bool(forKey: "wizard_has_seen_welcome"))
        XCTAssertTrue(WizardWelcomeGate.shouldShowWelcome(helperInstalled: false,
            hasSeenWelcome: defaults.bool(forKey: "wizard_has_seen_welcome"), forced: false))
        XCTAssertTrue(result.logs.first?.contains("KeyPath-Uninstall-Backup-") == true)
    }

    func testCleanupRefusalRemovesNothing() async {
        var resumed = false
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
            prepare: { false }, resume: { resumed = true }, trash: { _ in XCTFail("Must not trash") })
        let result = await coordinator.performUninstall(deleteConfig: true, removeVirtualHID: false, allowAdminFallback: false)
        XCTAssertFalse(result.success)
        XCTAssertTrue(resumed)
        XCTAssertTrue(defaults.bool(forKey: "wizard_has_seen_welcome"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".config/keypath/keypath.kbd").path))
    }

    func testBackupFailurePreservesSettingsAndApp() async throws {
        try write("Downloads", "not a directory")
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
            prepare: { true }, resume: {}, trash: { _ in XCTFail("Must not trash") })
        let result = await coordinator.performUninstall(deleteConfig: true, removeVirtualHID: false, allowAdminFallback: false)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.failureReason?.contains("Backup failed") == true)
        XCTAssertTrue(defaults.bool(forKey: "wizard_has_seen_welcome"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".config/keypath/keypath.kbd").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testSymlinkedRulesAreBackedUpButExternalTargetIsPreserved() async throws {
        let config = root.appendingPathComponent(".config/keypath")
        let external = root.appendingPathComponent("dotfiles/keypath")
        try FileManager.default.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: config, to: external)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: external)
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
            prepare: { true }, resume: {}, trash: { try FileManager.default.removeItem(at: $0) })
        let result = await coordinator.performUninstall(deleteConfig: true, removeVirtualHID: false, allowAdminFallback: false)
        XCTAssertTrue(result.success)
        XCTAssertEqual(try String(contentsOf: external.appendingPathComponent("keypath.kbd"), encoding: .utf8), "rules")
        let backup = try XCTUnwrap(backups().first)
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("0-keypath/keypath.kbd"), encoding: .utf8), "rules")
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testTrashFailureReportsBackupForRecovery() async throws {
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
            prepare: { true }, resume: {}, trash: { _ in throw CocoaError(.fileWriteNoPermission) })
        let result = await coordinator.performUninstall(deleteConfig: true, removeVirtualHID: false, allowAdminFallback: false)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.failureReason?.contains("Your backup is at") == true)
        XCTAssertEqual(try backups().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }
    func testLinkedParentIsRefusedWithoutDeletingExternalRules() async throws {
        let configParent = root.appendingPathComponent(".config")
        let external = root.appendingPathComponent("dotfiles")
        try FileManager.default.moveItem(at: configParent, to: external)
        try FileManager.default.createSymbolicLink(at: configParent, withDestinationURL: external)
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
            prepare: { XCTFail("Must refuse before shutdown"); return true }, resume: {},
            trash: { _ in XCTFail("Must not trash") })
        let result = await coordinator.performUninstall(deleteConfig: true, removeVirtualHID: false, allowAdminFallback: false)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.failureReason?.contains("linked folder") == true)
        XCTAssertEqual(try String(contentsOf: external.appendingPathComponent("keypath/keypath.kbd"), encoding: .utf8), "rules")
    }

    func testWriteAdmissionDrainsThenStaysClosedUntilFailureRecovery() async throws {
        let directory = root.appendingPathComponent(".config/keypath")
        let gate = ConfigurationOperationGate(configurationDirectory: directory)
        let lock = ConfigurationOperationGate.lockFileURL(for: directory)
        defer { try? FileManager.default.removeItem(at: lock) }
        let entered = expectation(description: "Existing write admitted")
        let release = AsyncStream<Void>.makeStream()
        let writer = Task {
            try await gate.withOperation { _ in
                entered.fulfill()
                for await _ in release.stream { break }
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        let suspended = Task { await gate.suspendForUninstall() }
        release.continuation.finish()
        try await writer.value
        await suspended.value
        do {
            _ = try await gate.withOperation { _ in true }
            XCTFail("Uninstall must block writes")
        } catch {}
        await gate.resumeAfterFailedUninstall()
        let resumed = try await gate.withOperation { _ in true }
        XCTAssertTrue(resumed)
    }

}
