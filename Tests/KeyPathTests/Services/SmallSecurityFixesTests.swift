import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Project review S10: the config folder is the user's alone, and Karabiner
/// import shows what each launch or script shortcut will do.
@MainActor
final class SmallSecurityFixesTests: XCTestCase {
    func testConfigFolderIsTightenedToItsOwner() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: folder) }
        ConfigurationService.restrictToOwner(directory: folder.path)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o777, 0o700)
    }

    func testCLIUninstallStopsUnlessThePersonConfirms() async {
        var asked = 0
        let withoutYes = await RuntimeControlHandler.uninstallRefusal(confirmed: false, ask: { asked += 1; return true })
        XCTAssertNotNil(withoutYes)
        XCTAssertEqual(asked, 0, "Without --yes, KeyPath does not even ask")
        let cancelled = await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: { asked += 1; return false })
        XCTAssertNotNil(cancelled)
        let confirmed = await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: { asked += 1; return true })
        XCTAssertNil(confirmed)
        XCTAssertEqual(asked, 2)
        XCTAssertLessThan(RuntimeControlHandler.cliConfirmationTimeout, 120, "The dialog closes before the CLI stops waiting")
    }

    func testSecondCLIUninstallIsRefusedWhileOneIsAsking() async {
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: {
                await withCheckedContinuation { release = $0 }
                return false
            })
        }
        while release == nil {
            await Task.yield()
        }
        let second = await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: { true })
        XCTAssertEqual(second, "KeyPath is already asking about an uninstall; nothing was changed.")
        release?.resume()
        _ = await first.value
    }

    func testImportReviewShowsTheFullTarget() {
        XCTAssertEqual(KeyAction.runScript(path: "curl x | sh", name: "Build").importReviewDescription,
                       "Runs curl x | sh")
        XCTAssertEqual(KeyAction.openURL("https://example.com/a?b").importReviewDescription,
                       "Opens https://example.com/a?b")
        XCTAssertEqual(KeyAction.openFolder(path: "~/Work", name: nil).importReviewDescription,
                       "Opens the folder ~/Work")
        XCTAssertEqual(KeyAction.launchApp(name: "Safari", bundleId: "com.apple.Safari").importReviewDescription,
                       "Opens com.apple.Safari")
    }

    func testControlClientDisconnectIsDetected() {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        defer { close(fds[0]) }
        XCTAssertTrue(RuntimeControlServer.isConnected(fds[0]), "A waiting client is connected")
        close(fds[1])
        XCTAssertFalse(RuntimeControlServer.isConnected(fds[0]), "A client that went away is not")
    }

    /// A half-closed client reads as gone, which is why the CLI never half-closes.
    func testHalfClosedClientReadsAsGone() {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        defer { close(fds[0]); close(fds[1]) }
        shutdown(fds[1], SHUT_WR)
        XCTAssertFalse(RuntimeControlServer.isConnected(fds[0]))
    }

    /// `--reset-permissions` survives the trip over the control socket and reaches the uninstall.
    func testResetPermissionsArgumentReachesTheUninstall() throws {
        let sent = RuntimeControl.Request(operation: .uninstall, confirmed: true,
                                          argument: RuntimeControl.Request.resetPermissionsArgument)
        let received = try JSONDecoder().decode(RuntimeControl.Request.self, from: JSONEncoder().encode(sent))
        XCTAssertTrue(RuntimeControlHandler.wantsPermissionReset(received))
        XCTAssertFalse(RuntimeControlHandler.wantsPermissionReset(.init(operation: .uninstall, confirmed: true)))
        XCTAssertFalse(RuntimeControlHandler.wantsPermissionReset(
            .init(operation: .changeLayer, argument: RuntimeControl.Request.resetPermissionsArgument)
        ))
    }

    /// A click that lands after the keypath command stopped waiting changes nothing.
    func testLateConfirmationAfterTheCommandLeftIsRefused() async {
        let late = await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: { true }, connected: { false })
        XCTAssertEqual(late, "The keypath command stopped waiting; nothing was changed.")
        var checked = false
        let cancelled = await RuntimeControlHandler.uninstallRefusal(
            confirmed: true, ask: { false }, connected: { checked = true; return false }
        )
        XCTAssertEqual(cancelled, "Uninstall was not confirmed in KeyPath; nothing was changed.")
        XCTAssertFalse(checked, "A declined dialog is reported as declined")
    }

    /// A linked config folder (dotfiles) tightens the real folder.
    func testLinkedConfigFolderTightensItsTarget() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("link-\(UUID().uuidString)")
        let target = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: base) }
        let link = base.appendingPathComponent("keypath")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        ConfigurationService.restrictToOwner(directory: link.path)
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o700)
    }

    /// Unticking the launcher shortcuts in the import review saves none of them,
    /// and leaves nothing to count when they were all there was.
    func testUntickedLauncherShortcutsAreNotImported() {
        XCTAssertEqual(WizardKarabinerImportPage.launchersToImport([1, 2, 3], keep: true), [1, 2, 3])
        XCTAssertEqual(WizardKarabinerImportPage.launchersToImport([1, 2, 3], keep: false), [])
        let onlyLaunchers = WizardKarabinerImportPage.importCount(
            collections: 0, appKeymaps: 0,
            launcherMappings: WizardKarabinerImportPage.launchersToImport([1, 2], keep: false).count
        )
        XCTAssertEqual(onlyLaunchers, 0, "The Import button is disabled at zero")
    }
}
