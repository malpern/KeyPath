import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// A worker runs only the canonical config, for an owner that is KeyPath.
final class SessionWorkerLaunchCheckTests: XCTestCase {
    private let canonical = "/Users/someone/.config/keypath/keypath.kbd"

    func testCanonicalConfigAndKeyPathOwnerStart() {
        XCTAssertNil(SessionWorkerLaunchCheck.refusal(
            configPath: canonical, canonicalConfigPath: canonical, ownerPID: 42,
            ownerSatisfiesOwnRequirement: { _ in true }
        ))
    }

    func testOtherConfigIsRefused() {
        XCTAssertEqual(SessionWorkerLaunchCheck.refusal(
            configPath: "/tmp/attacker.kbd", canonicalConfigPath: canonical, ownerPID: 42,
            ownerSatisfiesOwnRequirement: { _ in true }
        ), .nonCanonicalConfig)
    }

    func testAnyDotDotIsRefused() {
        for path in ["/Users/someone/.config/keypath/../other/keypath.kbd",
                     "/Users/someone/.config/keypath/sub/../keypath.kbd", "keypath.kbd"]
        {
            XCTAssertEqual(SessionWorkerLaunchCheck.refusal(
                configPath: path, canonicalConfigPath: canonical, ownerPID: 42,
                ownerSatisfiesOwnRequirement: { _ in true }
            ), .nonCanonicalConfig, path)
        }
    }

    func testSymlinksAreResolvedOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("launch-check-\(UUID().uuidString)")
        let config = root.appendingPathComponent("keypath")
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalFile = config.appendingPathComponent("keypath.kbd")
        try Data().write(to: canonicalFile)
        try Data().write(to: elsewhere.appendingPathComponent("keypath.kbd"))
        // A link inside the config folder to another folder.
        try FileManager.default.createSymbolicLink(at: config.appendingPathComponent("sub"), withDestinationURL: elsewhere)
        // A link to the canonical file itself.
        let alias = root.appendingPathComponent("alias.kbd")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: canonicalFile)

        XCTAssertFalse(SessionWorkerLaunchCheck.isSameFile(config.path + "/sub/keypath.kbd", canonicalFile.path))
        XCTAssertTrue(SessionWorkerLaunchCheck.isSameFile(alias.path, canonicalFile.path))
        XCTAssertTrue(SessionWorkerLaunchCheck.isSameFile(canonicalFile.path, canonicalFile.path))
    }

    func testTheAppLaunchesWorkersWithTheCanonicalConfig() throws {
        let arguments = ServiceLifecycleCoordinator.sessionLaunchArguments(
            capabilitiesOnly: false, reportPath: "/tmp/report.json", nonce: UUID().uuidString,
            ownerPID: 42, ownerPIDVersion: 1, configPath: KeyPathConstants.Config.mainConfigPath
        )
        let index = try XCTUnwrap(arguments.firstIndex(of: "--session-config"))
        // Under test, mainConfigPath points at the test sandbox; production passes the real one.
        XCTAssertNil(SessionWorkerLaunchCheck.refusal(
            configPath: arguments[index + 1], canonicalConfigPath: KeyPathConstants.Config.mainConfigPath,
            ownerPID: 42, ownerSatisfiesOwnRequirement: { _ in true }
        ))
    }

    func testAdmissionIgnoresTestModeRedirection() {
        // A test-mode environment redirects mainConfigPath; admission must not follow it.
        XCTAssertNotEqual(SessionWorkerLaunchCheck.accountConfigPath, KeyPathConstants.Config.mainConfigPath)
        XCTAssertTrue(SessionWorkerLaunchCheck.accountConfigPath.hasSuffix("/.config/keypath/keypath.kbd"))
        XCTAssertEqual(SessionWorkerLaunchCheck.refusal(
            configPath: KeyPathConstants.Config.mainConfigPath, ownerPID: 42,
            ownerSatisfiesOwnRequirement: { _ in true }
        ), .nonCanonicalConfig)
    }

    func testOwnerThatIsNotKeyPathIsRefused() {
        XCTAssertEqual(SessionWorkerLaunchCheck.refusal(
            configPath: canonical, canonicalConfigPath: canonical, ownerPID: 42,
            ownerSatisfiesOwnRequirement: { _ in false }
        ), .ownerNotKeyPath)
        XCTAssertEqual(SessionWorkerLaunchCheck.refusal(
            configPath: canonical, canonicalConfigPath: canonical, ownerPID: 0,
            ownerSatisfiesOwnRequirement: { _ in true }
        ), .ownerNotKeyPath)
    }

    func testRealSignatureCheck() throws {
        // This checks the Security calls against the test host's own signature,
        // not KeyPath.app's; the app's requirement is exercised by a real launch.
        XCTAssertTrue(SessionWorkerLaunchCheck.ownerSatisfiesOwnRequirement(getpid()),
                      "A process satisfies its own designated requirement")
        let other = Process()
        other.executableURL = URL(fileURLWithPath: "/bin/sleep")
        other.arguments = ["5"]
        try other.run()
        defer {
            other.terminate()
            other.waitUntilExit()
        }
        XCTAssertFalse(SessionWorkerLaunchCheck.ownerSatisfiesOwnRequirement(other.processIdentifier),
                       "Other code does not satisfy KeyPath's requirement")
        XCTAssertFalse(SessionWorkerLaunchCheck.ownerSatisfiesOwnRequirement(999_999))
    }
}
