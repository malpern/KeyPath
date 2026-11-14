import Foundation
@testable import KeyPathAppKit
import XCTest

/// Round trip through a throwaway login-Keychain item. Skipped where the
/// Keychain refuses writes (a locked keychain on a headless runner).
@MainActor
final class KeychainStringSetTests: XCTestCase {
    func testInsertRemoveAndReloadFromKeychain() throws {
        let account = "keypath-tests-\(UUID().uuidString)"
        let set = KeychainStringSet(service: "com.keypath.tests", account: account)
        defer { set.removeAll() }
        guard set.insert("a") else { throw XCTSkip("The Keychain refused the write here") }
        XCTAssertTrue(set.insert("b"))

        let reloaded = KeychainStringSet(service: "com.keypath.tests", account: account)
        XCTAssertEqual(reloaded.members, ["a", "b"])

        XCTAssertTrue(reloaded.remove("a"))
        XCTAssertEqual(KeychainStringSet(service: "com.keypath.tests", account: account).members, ["b"])

        reloaded.removeAll()
        XCTAssertTrue(KeychainStringSet(service: "com.keypath.tests", account: account).members.isEmpty)
    }

    func testScriptApprovalsRoundTrip() throws {
        let items = KeychainStringSet(service: "com.keypath.tests", account: "keypath-tests-\(UUID().uuidString)")
        defer { items.removeAll() }
        let store = KeychainScriptApprovalStore(items: items)
        guard store.approve(path: "/tmp/x.sh", digest: "d1") else { throw XCTSkip("The Keychain refused the write here") }
        XCTAssertTrue(store.isApproved(path: "/tmp/x.sh", digest: "d1"))
        XCTAssertFalse(store.isApproved(path: "/tmp/x.sh", digest: "d2"))
        XCTAssertEqual(store.count, 1)
    }
}
