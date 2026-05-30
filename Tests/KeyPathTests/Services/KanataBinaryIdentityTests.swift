@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

/// Tests for stale-kanata-binary detection (#638): the pure adopt decision,
/// cdhash extraction guards, and persistence of the adopted identity.
final class KanataBinaryIdentityTests: XCTestCase {
    // MARK: - shouldAdoptBundled decision

    func testShouldAdopt_firstRun_noRecord_adopts() {
        // No record yet (first run, or a daemon already running an older binary).
        XCTAssertTrue(KanataBinaryIdentity.shouldAdoptBundled(adopted: nil, bundled: "abc123"))
    }

    func testShouldAdopt_alreadyCurrent_doesNotAdopt() {
        XCTAssertFalse(KanataBinaryIdentity.shouldAdoptBundled(adopted: "abc123", bundled: "abc123"))
    }

    func testShouldAdopt_upgrade_differentHash_adopts() {
        XCTAssertTrue(KanataBinaryIdentity.shouldAdoptBundled(adopted: "oldhash", bundled: "newhash"))
    }

    func testShouldAdopt_bundledUnknown_doesNotAdopt() {
        // Can't read the bundled cdhash → don't act on uncertainty (never restart).
        XCTAssertFalse(KanataBinaryIdentity.shouldAdoptBundled(adopted: "abc123", bundled: nil))
        XCTAssertFalse(KanataBinaryIdentity.shouldAdoptBundled(adopted: nil, bundled: nil))
    }

    // MARK: - codeHash extraction

    func testCodeHash_missingPath_returnsNil() {
        XCTAssertNil(KanataBinaryIdentity.codeHash(atPath: "/nonexistent/path/to/kanata"))
    }

    // MARK: - Persistence round-trip

    func testAdoptedCodeHash_persistsAcrossReload() {
        let key = "KeyPath.Kanata.AdoptedCodeHash"
        let original = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        let writer = PreferencesService()
        writer.adoptedKanataCodeHash = "deadbeef"
        let reloaded = PreferencesService()
        XCTAssertEqual(reloaded.adoptedKanataCodeHash, "deadbeef")

        writer.adoptedKanataCodeHash = nil
        let cleared = PreferencesService()
        XCTAssertNil(cleared.adoptedKanataCodeHash)
    }
}
