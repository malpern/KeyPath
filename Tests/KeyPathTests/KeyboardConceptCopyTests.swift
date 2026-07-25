@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class KeyboardConceptCopyTests: XCTestCase {
    func testDefinitionsDistinguishLeaderFromHyper() {
        XCTAssertTrue(KeyboardConceptCopy.leaderDefinition.contains("starting key"))
        XCTAssertTrue(KeyboardConceptCopy.leaderDefinition.contains("Space by default"))
        XCTAssertTrue(KeyboardConceptCopy.hyperDefinition.contains("Control, Option, Command, and Shift"))
        XCTAssertTrue(KeyboardConceptCopy.hyperDefinition.contains("Caps Lock Remap"))
        XCTAssertNotEqual(KeyboardConceptCopy.leaderDefinition, KeyboardConceptCopy.hyperDefinition)
    }

    func testPackDescriptionsReuseCanonicalDefinitions() {
        XCTAssertTrue(
            PackRegistry.launcher.shortDescription.hasPrefix(KeyboardConceptCopy.hyperDefinition)
        )
        XCTAssertTrue(
            PackRegistry.leaderKey.shortDescription.hasPrefix(KeyboardConceptCopy.leaderDefinition)
        )
    }

    func testCatalogDescriptionsReuseCanonicalDefinitions() throws {
        let collections = RuleCollectionCatalog().defaultCollections()
        let launcher = try XCTUnwrap(
            collections.first { $0.id == RuleCollectionIdentifier.launcher }
        )
        let leader = try XCTUnwrap(
            collections.first { $0.id == RuleCollectionIdentifier.leaderKey }
        )

        XCTAssertEqual(launcher.summary, KeyboardConceptCopy.launcherCatalogSummary)
        XCTAssertEqual(leader.summary, KeyboardConceptCopy.leaderCatalogSummary)
    }

    func testLauncherActivationDescriptionsExplainSelectedConcept() {
        let hyperDescription = KeyboardConceptCopy.launcherActivationDescription(
            mode: .holdHyper,
            hyperTriggerMode: .hold
        )
        let leaderDescription = KeyboardConceptCopy.launcherActivationDescription(
            mode: .leaderSequence,
            hyperTriggerMode: .hold
        )

        XCTAssertTrue(hyperDescription.hasPrefix(KeyboardConceptCopy.hyperDefinition))
        XCTAssertTrue(hyperDescription.hasSuffix("Hold your Hyper key, then press a shortcut key."))
        XCTAssertTrue(leaderDescription.hasPrefix(KeyboardConceptCopy.leaderDefinition))
        XCTAssertTrue(leaderDescription.hasSuffix("Press your Leader key, then L, then a shortcut key."))
    }
}
