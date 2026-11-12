@testable import KeyPathAppKit
import KeyPathInstallationWizard
import XCTest

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

    func testBacksUpBeforeRemovingSettingsAndTrashesOnlyCurrentApp() async {
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
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertTrue(result.success, result.failureReason ?? "")
        XCTAssertEqual(trashed, app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".config/keypath").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/Application Support/KeyPath").path))
        XCTAssertFalse(defaults.bool(forKey: "wizard_has_seen_welcome"))
        XCTAssertTrue(WizardWelcomeGate.shouldShowWelcome(hasSeenWelcome: defaults.bool(forKey: "wizard_has_seen_welcome"), forced: false))
        XCTAssertTrue(result.logs.first?.contains("KeyPath-Uninstall-Backup-") == true)
    }

    /// The command-line link points into the app being trashed, so uninstall
    /// removes it, but only when it is KeyPath's own link.
    func testUninstallRemovesKeyPathsCommandLineLinkOnly() async throws {
        let link = URL(fileURLWithPath: CommandLineToolInstaller.linkPath(home: root))
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: app.appendingPathComponent("Contents/MacOS/keypath-cli").path
        )
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: {}, trash: { try FileManager.default.removeItem(at: $0) })

        let result = await coordinator.performUninstall(deleteConfig: true)

        XCTAssertTrue(result.success, result.failureReason ?? "")
        var info = stat()
        XCTAssertNotEqual(lstat(link.path, &info), 0, "KeyPath's command-line link should be gone")
    }

    func testUninstallLeavesSomeoneElsesCommandLineFile() async throws {
        let link = URL(fileURLWithPath: CommandLineToolInstaller.linkPath(home: root))
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: link.path, contents: Data("mine".utf8))
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: {}, trash: { try FileManager.default.removeItem(at: $0) })

        let result = await coordinator.performUninstall(deleteConfig: true)

        XCTAssertTrue(result.success, result.failureReason ?? "")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "mine")
    }

    /// Application Support holds sockets (the CLI's runtime.sock, a stale
    /// engine socket). They are not settings and cannot be copied; the backup
    /// must skip them rather than fail the uninstall.
    func testBackupSkipsSocketsInsteadOfFailing() async throws {
        let control = root.appendingPathComponent("Library/Application Support/KeyPath/control")
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        // The fixture path is longer than sun_path allows; bind by relative name.
        let previous = FileManager.default.currentDirectoryPath
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(control.path))
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let name = Array("runtime.sock".utf8)
            raw.copyBytes(from: name)
            raw[name.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        FileManager.default.changeCurrentDirectoryPath(previous)
        defer { close(fd) }
        XCTAssertEqual(bound, 0)

        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: { XCTFail("Unexpected failure") }, trash: { url in
                                                          let backup = try XCTUnwrap(self.backups().first)
                                                          let saved = backup.appendingPathComponent("1-KeyPath")
                                                          XCTAssertEqual(try String(contentsOf: saved.appendingPathComponent("rules.json"), encoding: .utf8), "saved rules")
                                                          XCTAssertFalse(FileManager.default.fileExists(atPath: saved.appendingPathComponent("control/runtime.sock").path))
                                                          try FileManager.default.removeItem(at: url)
                                                      })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertTrue(result.success, result.failureReason ?? "")
    }

    func testLoginItemRemovalFailurePreservesAppAndSettings() async throws {
        var resumed = false
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: { resumed = true }, removeLoginItem: {
                                                          XCTAssertEqual(try self.backups().count, 1, "Backup must already exist")
                                                          throw CocoaError(.fileWriteNoPermission)
                                                      }, trash: { _ in XCTFail("Must not trash before verified login-item removal") })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertFalse(result.success)
        XCTAssertTrue(resumed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".config/keypath/keypath.kbd"), encoding: .utf8), "rules")
        XCTAssertTrue(defaults.bool(forKey: "wizard_has_seen_welcome"))
    }

    func testCleanupRefusalRemovesNothing() async {
        var resumed = false
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { false }, resume: { resumed = true }, trash: { _ in XCTFail("Must not trash") })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertFalse(result.success)
        XCTAssertTrue(resumed)
        XCTAssertTrue(defaults.bool(forKey: "wizard_has_seen_welcome"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".config/keypath/keypath.kbd").path))
    }

    func testWorkersThatDoNotStopRemoveNothing() async {
        var resumed = false
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: { resumed = true },
                                                      stopSessionWorkers: { .stillRunning },
                                                      trash: { _ in XCTFail("Must not trash while a worker runs") })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertFalse(result.success)
        XCTAssertTrue(resumed)
        XCTAssertTrue(result.failureReason?.contains("Nothing was removed") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".config/keypath/keypath.kbd").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    /// An unreadable process table is not reported as a running process.
    func testUnverifiedSweepRemovesNothingAndSaysWhy() async {
        var resumed = false
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: { resumed = true },
                                                      stopSessionWorkers: { .unverified },
                                                      trash: { _ in XCTFail("Must not trash an unverified state") })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertFalse(result.success)
        XCTAssertTrue(resumed)
        XCTAssertTrue(result.failureReason?.contains("could not check") == true)
        XCTAssertFalse(result.failureReason?.contains("did not stop") == true)
    }

    /// The final sweep runs after the app and settings are gone, so a failure
    /// there must not resume watching or starting anything.
    func testFinalSweepFailureDoesNotResume() async {
        var sweeps = 0
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: { XCTFail("Nothing is left to resume") },
                                                      stopSessionWorkers: { sweeps += 1; return sweeps == 1 ? .noneRunning : .unverified },
                                                      trash: { try FileManager.default.removeItem(at: $0) })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.failureReason?.contains("could not check") == true)
    }

    /// Success is reported only after a final sweep finds no worker left.
    func testWorkerFoundAfterRemovalIsNotReportedAsSuccess() async {
        var sweeps = 0
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: {},
                                                      stopSessionWorkers: { sweeps += 1; return sweeps == 1 ? .noneRunning : .stillRunning },
                                                      trash: { try FileManager.default.removeItem(at: $0) })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertEqual(sweeps, 2)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.failureReason?.contains("still running") == true)
        XCTAssertTrue(result.failureReason?.contains("Your backup is at") == true)
    }

    func testSuccessfulUninstallSweepsWorkersBeforeAndAfterRemoval() async {
        var sweepsBeforeTrash = 0
        var sweeps = 0
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: { XCTFail("Unexpected failure") },
                                                      stopSessionWorkers: { sweeps += 1; return .noneRunning },
                                                      trash: { url in
                                                          sweepsBeforeTrash = sweeps
                                                          try FileManager.default.removeItem(at: url)
                                                      })
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertTrue(result.success, result.failureReason ?? "")
        XCTAssertEqual(sweepsBeforeTrash, 1)
        XCTAssertEqual(sweeps, 2)
    }

    func testBackupFailurePreservesSettingsAndApp() async throws {
        try write("Downloads", "not a directory")
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: {}, trash: { _ in XCTFail("Must not trash") })
        let result = await coordinator.performUninstall(deleteConfig: true)
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
        let result = await coordinator.performUninstall(deleteConfig: true)
        XCTAssertTrue(result.success)
        XCTAssertEqual(try String(contentsOf: external.appendingPathComponent("keypath.kbd"), encoding: .utf8), "rules")
        let backup = try XCTUnwrap(backups().first)
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("0-keypath/keypath.kbd"), encoding: .utf8), "rules")
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testTrashFailureReportsBackupForRecovery() async throws {
        let coordinator = SessionUninstallCoordinator(home: root, app: app, defaults: defaults, domain: domain,
                                                      prepare: { true }, resume: {}, trash: { _ in throw CocoaError(.fileWriteNoPermission) })
        let result = await coordinator.performUninstall(deleteConfig: true)
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
        let result = await coordinator.performUninstall(deleteConfig: true)
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
                for await _ in release.stream {
                    break
                }
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
