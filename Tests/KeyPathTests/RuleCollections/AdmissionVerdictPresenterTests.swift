@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// Phase 4b: dialogs render engine verdicts through one presenter, the save-time
/// dialog is built from verdicts by id, and synthetic parties can be shown.
@MainActor
final class AdmissionVerdictPresenterTests: XCTestCase {
    private func collection(_ name: String, _ mappings: [(String, String)], layer: RuleCollectionLayer = .base,
                            activator: MomentaryActivator? = nil) -> RuleCollection
    {
        RuleCollection(id: UUID(), name: name, summary: name, category: .custom,
                       mappings: mappings.map { KeyMapping(input: $0.0, action: .keystroke(key: $0.1)) },
                       isEnabled: true, icon: "star", tags: [], targetLayer: layer,
                       momentaryActivator: activator, configuration: .list)
    }

    private let names: (AdmissionSubject) -> String = { subject in
        switch subject {
        case .collection: "Home Row Mods"
        case .customRule: "My rule"
        case let .pack(id): id == "p1" ? "Pack One" : "Pack Two"
        case let .named(n): n
        }
    }

    func testConflictReadsAsOneSentenceWithTurnOffOptions() {
        let a = UUID(), b = UUID()
        let verdict = AdmissionVerdict(severity: .needsChoice, subject: .collection(a),
                                       reason: .conflict(key: "f", layer: "base", parties: [.collection(a), .customRule(b)]),
                                       fixes: [.disable(.collection(a)), .disable(.customRule(b))])
        let p = AdmissionVerdictPresenter.present(verdict, name: names)
        XCTAssertEqual(p.title, "Key conflict on f")
        XCTAssertEqual(p.explanation, "Home Row Mods and My rule both map f on the base layer. Only one can win.")
        XCTAssertEqual(p.options.map(\.label), ["Turn off Home Row Mods", "Turn off My rule"])
    }

    func testUnmetNeedNamesTheKeyAndTheRule() {
        let verdict = AdmissionVerdict(severity: .blocking, subject: .collection(UUID()),
                                       reason: .unmetNeed(.emits(key: "volu")), fixes: [.disable(.collection(UUID()))])
        let p = AdmissionVerdictPresenter.present(verdict, name: names)
        XCTAssertEqual(p.title, "Home Row Mods can't run here")
        XCTAssertEqual(p.explanation, "Home Row Mods sends volu, which the current backend can't send.")
    }

    func testReservedKeyMoveIsOneLineAndBlockedFormHasAnOption() {
        let move = AdmissionVerdict(severity: .automatic, subject: .customRule(UUID()), reason: .reservedKey(key: "f18"),
                                    fixes: [.moveCapsIntermediate(candidates: ["f19", "f20"])])
        XCTAssertEqual(AdmissionVerdictPresenter.oneLine(move, name: names),
                       "My rule uses F18, which KeyPath had reserved for Caps Lock. Caps Lock will use F19 instead.")
        let blocked = AdmissionVerdict(severity: .blocking, subject: .customRule(UUID()), reason: .reservedKey(key: "f18"),
                                       fixes: [.disable(.customRule(UUID()))])
        let p = AdmissionVerdictPresenter.present(blocked, name: names)
        XCTAssertEqual(p.title, "F18 is reserved for Caps Lock")
        XCTAssertEqual(p.options.map(\.label), ["Turn off My rule"])
    }

    func testOtherAppAndPackConflictAndMissingApp() {
        let caps = AdmissionVerdict(severity: .blocking, subject: .collection(UUID()), reason: .capsLockHeldByOtherApp("Raycast"))
        XCTAssertEqual(AdmissionVerdictPresenter.present(caps, name: names).title, "Raycast already remaps Caps Lock")
        let pack = AdmissionVerdict(severity: .needsChoice, subject: .pack("p1"),
                                    reason: .packConflict(otherPackID: "p2", description: "Both use F."),
                                    fixes: [.disable(.pack("p1")), .disable(.pack("p2"))])
        let pp = AdmissionVerdictPresenter.present(pack, name: names)
        XCTAssertEqual(pp.title, "Pack One and Pack Two can't both be installed")
        XCTAssertEqual(pp.options.map(\.label), ["Remove Pack One", "Remove Pack Two"])
        let app = AdmissionVerdict(severity: .blocking, subject: .pack("p1"),
                                   reason: .unmetNeed(.externalApp(name: "KindaVim", path: "/Applications/kindaVim.app")),
                                   fixes: [.installApp(name: "KindaVim", path: "/Applications/kindaVim.app")])
        XCTAssertEqual(AdmissionVerdictPresenter.present(app, name: names).options.map(\.label), ["Install KindaVim"])
    }

    // MARK: - Save-time dialog from verdicts

    func testSaveTimeDialogOffersEveryRuleOrCustomRuleById() throws {
        let a = collection("A", [("a", "1")]), b = collection("B", [("a", "2")])
        let rule = CustomRule(title: "Mine", input: "a", action: .keystroke(key: "3"))
        let ctx = try XCTUnwrap(RuleCollectionsManager.mappingConflictContext(
            for: .init(collections: [a, b], customRules: [rule])
        ))
        XCTAssertEqual(Set(ctx.options.map(\.id)), [a.id, b.id, rule.id])
        XCTAssertEqual(ctx.options.first { $0.id == rule.id }?.name, "Mine")
        XCTAssertTrue(ctx.explanation.contains("both map a on the base layer") || ctx.explanation.contains("A, B, Mine"))
    }

    func testSaveTimeDialogFallsBackWhenNothingCanBeTurnedOff() {
        // Leader key vs nothing else: the only party is synthetic.
        let leaderOnly = AdmissionEngine.State(collections: [], customRules: [],
                                               leaderKey: LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true))
        XCTAssertNil(RuleCollectionsManager.mappingConflictContext(for: leaderOnly))
        XCTAssertNil(RuleCollectionsManager.mappingConflictContext(for: .init(collections: [collection("A", [("a", "1")])])))
    }

    func testLeaderKeyConflictNamesTheLeaderAndOffersTheCollection() throws {
        let nav = collection("Nav", [("x", "y")], layer: .navigation,
                             activator: MomentaryActivator(input: "space", targetLayer: .custom("sym")))
        let state = AdmissionEngine.State(collections: [nav], customRules: [],
                                          leaderKey: LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true))
        let ctx = try XCTUnwrap(RuleCollectionsManager.mappingConflictContext(for: state))
        XCTAssertEqual(ctx.options.map(\.id), [nav.id])
        XCTAssertTrue(ctx.explanation.contains("Leader Key"), ctx.explanation)
    }

    // MARK: - Toggle-time synthetic party

    func testToggleTimeShowsTheLeaderKeyWithoutOfferingToDisableIt() throws {
        let manager = RuleCollectionsManager(ruleCollectionStore: .shared, customRulesStore: .shared,
                                             configurationService: ConfigurationService())
        manager.preferencesService.leaderKeyPreference = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)
        defer { manager.preferencesService.leaderKeyPreference = .default }
        let candidate = collection("Nav", [], activator: MomentaryActivator(input: "space", targetLayer: .custom("sym")))
        let info = try XCTUnwrap(manager.conflictInfo(for: candidate))
        guard case .named = info.source else { return XCTFail("expected the leader key, got \(info.source)") }
        XCTAssertFalse(info.source.canBeDisabled)
        let snapshot = RuleConflictSourceSnapshot(from: info.source)
        XCTAssertFalse(snapshot.canBeDisabled)
    }
}
