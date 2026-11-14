import Foundation
@testable import KeyPathAppKit
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

    func testDotDotSpellingOfAnotherFileIsRefused() {
        XCTAssertEqual(SessionWorkerLaunchCheck.refusal(
            configPath: "/Users/someone/.config/keypath/../other/keypath.kbd", canonicalConfigPath: canonical,
            ownerPID: 42, ownerSatisfiesOwnRequirement: { _ in true }
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
        XCTAssertTrue(SessionWorkerLaunchCheck.ownerSatisfiesOwnRequirement(getpid()),
                      "A process satisfies its own designated requirement")
        let other = Process()
        other.executableURL = URL(fileURLWithPath: "/bin/sleep")
        other.arguments = ["5"]
        try other.run()
        defer { other.terminate() }
        XCTAssertFalse(SessionWorkerLaunchCheck.ownerSatisfiesOwnRequirement(other.processIdentifier),
                       "Other code does not satisfy KeyPath's requirement")
        XCTAssertFalse(SessionWorkerLaunchCheck.ownerSatisfiesOwnRequirement(999_999))
    }
}
