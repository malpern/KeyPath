@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// Phase 4a: toggle-time conflict checks ask the same engine as the save path.
@MainActor
final class AdmissionToggleParityTests: XCTestCase {
    private func makeManager(collections: [RuleCollection], rules: [CustomRule] = []) -> RuleCollectionsManager {
        let manager = RuleCollectionsManager(ruleCollectionStore: .shared, customRulesStore: .shared,
                                             configurationService: ConfigurationService())
        manager.ruleCollections = collections
        manager.customRules = rules
        return manager
    }

    private func collection(_ name: String, _ mappings: [(String, String)], layer: RuleCollectionLayer = .base,
                            enabled: Bool = true, activator: MomentaryActivator? = nil) -> RuleCollection
    {
        RuleCollection(id: UUID(), name: name, summary: name, category: .custom,
                       mappings: mappings.map { KeyMapping(input: $0.0, action: .keystroke(key: $0.1)) },
                       isEnabled: enabled, icon: "star", tags: [], targetLayer: layer,
                       momentaryActivator: activator, configuration: .list)
    }

    /// For each scenario, enabling the candidate conflicts at toggle time exactly
    /// when the save-time detector would refuse the resulting state.
    func testToggleTimeAgreesWithSaveTimeDetector() {
        let cases: [(others: [RuleCollection], rules: [CustomRule], candidate: RuleCollection)] = [
            ([collection("A", [("a", "1")])], [], collection("B", [("a", "2")])),
            ([collection("A", [("a", "1")])], [], collection("B", [("b", "2")])),
            ([collection("A", [("h", "left")], layer: .navigation)], [], collection("B", [("h", "h")])),
            ([collection("A", [("x", "1")], layer: .custom("sym"))], [], collection("B", [("x", "2")], layer: .custom("sym"))),
            ([collection("A", [("a", "1")], enabled: false)], [], collection("B", [("a", "2")])),
            ([collection("A", [], activator: MomentaryActivator(input: "space", targetLayer: .navigation))], [],
             collection("B", [], activator: MomentaryActivator(input: "space", targetLayer: .custom("sym")))),
            ([collection("A", [], activator: MomentaryActivator(input: "f", targetLayer: .navigation))], [],
             collection("B", [("f", "lmet")])),
            ([], [CustomRule(title: "Mine", input: "q", action: .keystroke(key: "2"))], collection("B", [("q", "1")])),
            ([], [CustomRule(title: "Mine", input: "q", action: .keystroke(key: "2"))], collection("B", [("q", "1")], layer: .navigation)),
        ]
        var conflicts = 0
        for (index, c) in cases.enumerated() {
            let manager = makeManager(collections: c.others, rules: c.rules)
            var proposed = c.candidate
            proposed.isEnabled = true
            let saveTime = RuleCollectionDeduplicator.detectConflicts(
                in: c.others + [proposed] + c.rules.map { $0.asRuleCollection() }
            )
            let toggleTime = manager.conflictInfo(for: c.candidate)
            XCTAssertEqual(toggleTime != nil, !saveTime.isEmpty, "case \(index) disagrees: toggle=\(String(describing: toggleTime?.keys)) save=\(saveTime)")
            if toggleTime != nil { conflicts += 1 }
        }
        XCTAssertGreaterThanOrEqual(conflicts, 5, "the parity cases must include real conflicts")
    }

    func testConflictReportsEveryCollidingKeyWithTheOtherParty() throws {
        let a = collection("A", [("a", "1"), ("b", "1"), ("c", "1")])
        let manager = makeManager(collections: [a])
        let info = try XCTUnwrap(manager.conflictInfo(for: collection("B", [("a", "2"), ("b", "2"), ("z", "2")])))
        XCTAssertEqual(info.keys, ["a", "b"])
        guard case let .collection(source) = info.source else { return XCTFail("expected a collection") }
        XCTAssertEqual(source.id, a.id)
    }

    /// The old toggle-time check compared custom rules ignoring their layer.
    func testCustomRulesOnDifferentLayersNoLongerConflict() {
        let base = CustomRule(title: "Base", input: "q", action: .keystroke(key: "1"))
        let nav = CustomRule(title: "Nav", input: "q", action: .keystroke(key: "2"), targetLayer: .navigation)
        let manager = makeManager(collections: [], rules: [base])
        XCTAssertNil(manager.conflictInfo(for: nav))
        let sameLayer = CustomRule(title: "Same", input: "q", action: .keystroke(key: "3"))
        XCTAssertNotNil(manager.conflictInfo(for: sameLayer))
    }

    func testNeovimTerminalStillNeverConflictsAtToggleTime() throws {
        let neovim = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.neovimTerminal })
        let key = try XCTUnwrap(KanataConfiguration.effectiveMappings(for: neovim).first?.input)
        let other = collection("Other", [(key, "x")], layer: neovim.targetLayer)
        let manager = makeManager(collections: [other])
        XCTAssertNil(manager.conflictInfo(for: neovim))
        XCTAssertNil(makeManager(collections: [neovim]).conflictInfo(for: other))
    }
}
