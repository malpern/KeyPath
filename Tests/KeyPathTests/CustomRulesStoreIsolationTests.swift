import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// The shared store must never resolve to the developer's real config under test.
final class CustomRulesStoreIsolationTests: XCTestCase {
    func testSharedStoreUsesTestSandboxNotRealConfig() async {
        let path = await CustomRulesStore.shared.persistenceURL.path
        XCTAssertFalse(path.hasPrefix(NSHomeDirectory() + "/.config/keypath"),
                       "Tests must not write the real CustomRules.json (\(path))")
        XCTAssertTrue(path.hasPrefix(AppPaths.configDirectory.path))
    }
}
