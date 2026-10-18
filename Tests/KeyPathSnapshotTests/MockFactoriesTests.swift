import Foundation
import XCTest

final class MockFactoriesTests: XCTestCase {
    func testLauncherIdentityIsStableAcrossProcesses() {
        // A known identity detects process-randomized Swift hashes and UUID fallbacks.
        XCTAssertEqual(MockFactories.launcherMapping(key: "s").id.uuidString.lowercased(),
                       "043a7187-74c5-72bd-8a25-adbeb1bfcd5c")
    }

    func testEveryLauncherLetterHasDistinctIdentity() {
        let mappings = (97 ... 122).map { value in
            MockFactories.launcherMapping(key: String(UnicodeScalar(value)!))
        }
        XCTAssertEqual(Set(mappings.map(\.id)).count, mappings.count,
                       "Duplicate ForEach identities silently remove launcher cards")
        XCTAssertEqual(MockFactories.defaultLauncherMappings.map(\.id),
                       MockFactories.defaultLauncherMappings.map(\.id))
    }
}
