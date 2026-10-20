@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// Phase 3 of docs/architecture/rules-admission-review.md.
/// Golden cases: every conflict today's detector reports comes back as exactly
/// one verdict with the same key, layer and parties — now attributed to ids.
/// New cases: unmet needs, the reserved Caps intermediate, another app holding
/// Caps Lock, and pack conflicts and requirements.
@MainActor
final class AdmissionEngineTests: XCTestCase {
    private let allowAll = BackendCapabilityProfile(backend: .session) { _ in true }

    private func collection(_ name: String, _ mappings: [(String, String)], layer: RuleCollectionLayer = .base,
                            enabled: Bool = true, activator: MomentaryActivator? = nil) -> RuleCollection
    {
        RuleCollection(id: UUID(), name: name, summary: name, category: .custom,
                       mappings: mappings.map { KeyMapping(input: $0.0, action: .keystroke(key: $0.1)) },
                       isEnabled: enabled, icon: "star", tags: [], targetLayer: layer,
                       momentaryActivator: activator, configuration: .list)
    }

    private func evaluate(_ state: AdmissionEngine.State,
                          profile: BackendCapabilityProfile? = nil) -> [AdmissionVerdict]
    {
        AdmissionEngine.evaluate(state, profile: profile ?? allowAll, fileExists: { _ in true })
    }

    // MARK: - Golden: conflicts match today's detector

    @discardableResult
    private func assertConflictsMatchDetector(_ state: AdmissionEngine.State, file: StaticString = #filePath,
                                              line: UInt = #line) -> Int
    {
        // The save gate's view of the same state must agree with evaluate's.
        let detector = AdmissionEngine.mappingConflicts(
            in: state.collections + state.customRules.map { $0.asRuleCollection() }, leaderKey: state.leaderKey
        )
        let conflicts = evaluate(state).compactMap { verdict -> (String, String)? in
            guard case let .conflict(key, layer, _, _) = verdict.reason else { return nil }
            XCTAssertEqual(verdict.severity, .needsChoice, file: file, line: line)
            return (key, layer)
        }
        XCTAssertEqual(conflicts.map { "\($0.0)@\($0.1)" }.sorted(),
                       detector.map { "\($0.inputKey)@\($0.layer)" }.sorted(), file: file, line: line)
        return detector.count
    }

    func testGoldenScenariosMatchTheDetector() {
        let navActivatorA = MomentaryActivator(input: "space", targetLayer: .navigation)
        let navActivatorB = MomentaryActivator(input: "space", targetLayer: .custom("symbol"))
        let scenarios: [AdmissionEngine.State] = [
            .init(collections: [collection("A", [("a", "1")]), collection("B", [("a", "2")]), collection("C", [("a", "3")])]),
            .init(collections: [collection("A", [("a", "1"), ("b", "1")]), collection("B", [("a", "2"), ("b", "2")])]),
            .init(collections: [collection("A", [("a", "1")]), collection("B", [("a", "2")], enabled: false)]),
            .init(collections: [collection("A", [("h", "left")], layer: .navigation), collection("B", [("h", "h")])]),
            .init(collections: [collection("A", [("x", "1")], layer: .custom("sym")), collection("B", [("x", "2")], layer: .custom("sym"))]),
            .init(collections: [collection("A", [], activator: navActivatorA), collection("B", [], activator: navActivatorB)]),
            .init(collections: [collection("A", [("q", "1")])],
                  customRules: [CustomRule(title: "Mine", input: "q", action: .keystroke(key: "2"))]),
            .init(collections: [collection("A", [("q", "1")], layer: .navigation)],
                  customRules: [CustomRule(title: "Mine", input: "q", action: .keystroke(key: "2"))]),
            .init(collections: [collection("Nav", [("x", "y")], layer: .navigation)],
                  leaderKey: LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)),
            .init(collections: []),
        ]
        let total = scenarios.reduce(0) { $0 + assertConflictsMatchDetector($1) }
        // Guard against a vacuous pass: the scenarios must exercise real conflicts.
        XCTAssertGreaterThanOrEqual(total, 5, "golden scenarios found only \(total) conflicts")
    }

    func testConflictsAreAttributedToRuleIds() throws {
        let a = collection("A", [("a", "1")]), b = collection("B", [("a", "2")])
        let rule = CustomRule(title: "Mine", input: "a", action: .keystroke(key: "3"))
        let verdict = try XCTUnwrap(evaluate(.init(collections: [a, b], customRules: [rule])).first)
        guard case let .conflict(key, _, parties, _) = verdict.reason else { return XCTFail("not a conflict") }
        XCTAssertEqual(key, "a")
        XCTAssertEqual(Set(parties), [.collection(a.id), .collection(b.id), .customRule(rule.id)])
        XCTAssertEqual(Set(verdict.fixes), Set(parties.map { AdmissionVerdict.Fix.disable($0) }))
    }

    /// Names are not identities: two rules titled alike, one colliding, must
    /// blame only the one that collides (the old detector reported names).
    func testSameTitledRulesAreToldApart() {
        let colliding = CustomRule(title: "Mine", input: "a", action: .keystroke(key: "2"))
        let innocent = CustomRule(title: "Mine", input: "b", action: .keystroke(key: "3"))
        let a = collection("A", [("a", "1")])
        let verdicts = evaluate(.init(collections: [a], customRules: [colliding, innocent]))
        XCTAssertEqual(verdicts.count, 1)
        guard case let .conflict(_, _, parties, _)? = verdicts.first?.reason else { return XCTFail("not a conflict") }
        XCTAssertEqual(Set(parties), [.collection(a.id), .customRule(colliding.id)])
        XCTAssertFalse(parties.contains(.customRule(innocent.id)))
        // The save gate's error names them too, from the same verdicts.
        let gate = AdmissionEngine.mappingConflicts(in: [a] + [colliding, innocent].map { $0.asRuleCollection() })
        XCTAssertEqual(gate.map(\.conflictingCollections), [["A", "Mine"]])
    }

    /// What each party does with the key travels with the verdict.
    func testConflictDetailsNameTheHoldAndTheActivator() throws {
        let mods = collection("Mods", [("f", "f")])
        var withHold = mods
        withHold.mappings = [KeyMapping(input: "f", action: .keystroke(key: "f"),
                                        behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "f"), holdAction: .keystroke(key: "lsft"))))]
        let arrows = collection("Arrows", [], activator: MomentaryActivator(input: "f", targetLayer: .navigation))
        let verdict = try XCTUnwrap(evaluate(.init(collections: [withHold, arrows])).first)
        guard case let .conflict(key, layer, parties, details) = verdict.reason else { return XCTFail("not a conflict") }
        XCTAssertEqual(key, "f"); XCTAssertEqual(layer, "Base")
        XCTAssertEqual(parties, [.collection(arrows.id), .collection(withHold.id)])
        XCTAssertEqual(details, ["Arrows: activates Navigation", "Mods: maps f"])
        let text = AdmissionVerdictPresenter.present(verdict) { $0 == .collection(arrows.id) ? "Arrows" : "Mods" }
        XCTAssertEqual(text.explanation, "Arrows and Mods both map f on the Base layer (Arrows: activates Navigation; Mods: maps f). Only one can win.")
    }

    // MARK: - New: environment needs

    func testMediaOutputIsBlockingOnTheSessionBackend() {
        let profile = BackendCapabilityProfile(backend: .session) { !["volu", "mute"].contains($0) }
        let media = collection("Media", [("f12", "volu"), ("f10", "mute"), ("f1", "f1")])
        let verdicts = evaluate(.init(collections: [media]), profile: profile)
        XCTAssertEqual(Set(verdicts.map(\.reason)), [.unmetNeed(.emits(key: "volu")), .unmetNeed(.emits(key: "mute"))])
        XCTAssertTrue(verdicts.allSatisfy { $0.severity == .blocking && $0.subject == .collection(media.id) })
        // The same rules on a driver backend are fine.
        let driver = BackendCapabilityProfile(backend: .driverKit) { _ in false }
        XCTAssertTrue(evaluate(.init(collections: [media]), profile: driver).isEmpty)
    }

    func testOtherAppHoldingCapsBlocksCapsRulesOnly() {
        let caps = collection("Caps", [("caps", "esc")]), other = collection("Other", [("a", "b")])
        let verdicts = evaluate(.init(collections: [caps, other], foreignCapsOwner: "Raycast"))
        XCTAssertEqual(verdicts, [AdmissionVerdict(severity: .blocking, subject: .collection(caps.id),
                                                   reason: .capsLockHeldByOtherApp("Raycast"))])
    }

    // MARK: - New: reserved Caps intermediate (decision 1)

    func testRuleTakingTheIntermediateMovesItAutomatically() throws {
        let rule = collection("F18 rule", [("f18", "a")])
        let verdict = try XCTUnwrap(evaluate(.init(collections: [rule], capsIntermediate: "f18")).first)
        XCTAssertEqual(verdict.severity, .automatic)
        XCTAssertEqual(verdict.reason, .reservedKey(key: "f18"))
        guard case let .moveCapsIntermediate(candidates) = verdict.fixes.first else { return XCTFail("no move fix") }
        XCTAssertFalse(candidates.contains("f18"))
        XCTAssertEqual(Set(candidates), ["f13", "f14", "f15", "f16", "f17", "f19", "f20"])
    }

    func testOutputOnTheIntermediateCountsToo() {
        let rule = collection("Emits F18", [("a", "f18")])
        XCTAssertEqual(evaluate(.init(collections: [rule], capsIntermediate: "f18")).first?.reason, .reservedKey(key: "f18"))
    }

    func testIntermediateBlocksOnlyWhenNoCandidateIsFree() {
        let rule = collection("F18 rule", [("f18", "a"), ("f13", "b"), ("f14", "c")])
        let occupied: Set = ["f15", "f16", "f17", "f19", "f20"]
        let verdict = evaluate(.init(collections: [rule], capsIntermediate: "f18", occupiedIntermediates: occupied)).first
        XCTAssertEqual(verdict?.severity, .blocking)
        XCTAssertEqual(verdict?.fixes, [.disable(.collection(rule.id))])
    }

    func testNoReservationWithoutManagedCaps() {
        XCTAssertTrue(evaluate(.init(collections: [collection("F18 rule", [("f18", "a")])])).isEmpty)
    }

    // MARK: - New: packs

    func testInstalledConflictingPacksAreReportedOnce() {
        let verdicts = evaluate(.init(collections: [],
                                      installedPackIDs: ["com.keypath.pack.home-row-arrows", "com.keypath.pack.home-row-mods"]))
        let packConflicts = verdicts.filter { if case .packConflict = $0.reason { true } else { false } }
        XCTAssertEqual(packConflicts.count, 1)
        XCTAssertEqual(packConflicts.first?.severity, .needsChoice)
    }

    func testMissingRequiredAppIsBlockingWithAnInstallFix() {
        let verdicts = AdmissionEngine.evaluate(.init(collections: [], installedPackIDs: ["com.keypath.pack.kindavim"]),
                                                profile: allowAll, fileExists: { _ in false })
        XCTAssertEqual(verdicts.count, 1)
        XCTAssertEqual(verdicts.first?.severity, .blocking)
        XCTAssertEqual(verdicts.first?.fixes, [.installApp(name: "KindaVim", path: "/Applications/kindaVim.app")])
    }

    // MARK: - Whole default profile

    func testFreshDefaultProfileAdmitsCleanlyAgainstTheRealBridge() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let host = SessionBridgeTestFixture.runtimeHost
        let profile = BackendCapabilityProfile(backend: .session) { key in
            KanataHostBridge.sessionOutputKeySupported(runtimeHost: host, keyName: key,
                                                       supportedUsages: SessionKeyMap.sessionOutputUsages)
        }
        let defaults = RuleCollectionCatalog().defaultCollections()
        let verdicts = AdmissionEngine.evaluate(.init(collections: defaults, capsIntermediate: "f18"),
                                                profile: profile, fileExists: { _ in true })
        XCTAssertEqual(verdicts, [], "A fresh profile must admit with no findings: \(verdicts)")
    }
}
