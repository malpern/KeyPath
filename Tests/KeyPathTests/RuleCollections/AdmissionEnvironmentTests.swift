import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// Phase 4d: the editors and the toggle ask the engine before writing, with
/// the live Caps environment the runtime published. A reserved Caps key is
/// moved and mentioned; a key the backend cannot send, a foreign Caps owner
/// or an exhausted pool refuses with the reason; conflicts keep their dialog.
@MainActor
final class AdmissionEnvironmentTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private let allowAll = BackendCapabilityProfile(backend: .session) { _ in true }
    private let noVolume = BackendCapabilityProfile(backend: .session) { $0 != "volu" }
    /// The driverless backend's actual limit: no consumer-page (media) keys.
    private let noMedia = BackendCapabilityProfile(backend: .session) { !BackendCapabilityProfile.fallbackConsumerKeys.contains($0) }

    override func setUp() async throws {
        try await super.setUp()
        try SessionBridgeTestFixture.requireAvailable()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = []
        manager.customRules = []
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        manager = nil; directory = nil
        try await super.tearDown()
    }

    // MARK: - Environment

    func testEnvironmentFromRuntimeUsagesUsesKanataNames() {
        let environment = AdmissionEngine.Environment(intermediateUsage: 109, occupied: [110, 104], foreignCapsOwner: "Raycast")
        XCTAssertEqual(environment.capsIntermediate, "f18")
        XCTAssertEqual(environment.occupiedIntermediates, ["f19", "f13"])
        XCTAssertEqual(environment.foreignCapsOwner, "Raycast")
        XCTAssertNil(AdmissionEngine.Environment(intermediateUsage: nil, occupied: [], foreignCapsOwner: nil).capsIntermediate)
    }

    func testManagerStateCarriesTheEnvironment() {
        manager.admissionEnvironment = .init(capsIntermediate: "f18", occupiedIntermediates: ["f19"], foreignCapsOwner: "Raycast")
        let state = manager.admissionState(collections: [], customRules: [])
        XCTAssertEqual(state.capsIntermediate, "f18")
        XCTAssertEqual(state.occupiedIntermediates, ["f19"])
        XCTAssertEqual(state.foreignCapsOwner, "Raycast")
    }

    // MARK: - Reserved Caps key (decision 1: move it)

    func testRuleOnTheReservedKeyIsSavedAndTheMoveIsMentioned() {
        manager.admissionEnvironment = .init(capsIntermediate: "f18")
        let rule = CustomRule(title: "Mine", input: "f18", action: .keystroke(key: "a"))
        let review = manager.reviewAdmission(forProposed: rule, profile: allowAll)
        XCTAssertNil(review.refusal)
        XCTAssertEqual(review.notes, ["Mine uses F18, which KeyPath had reserved for Caps Lock. Caps Lock will use F19 instead."])
    }

    /// The key the engine names is the key the runtime's re-pick will take.
    func testTheNamedKeyIsWhatTheRuntimeRepickChooses() {
        manager.admissionEnvironment = .init(intermediateUsage: 109, occupied: [110], foreignCapsOwner: nil)
        let rule = CustomRule(title: "Mine", input: "f18", action: .keystroke(key: "a"))
        let review = manager.reviewAdmission(forProposed: rule, profile: allowAll)
        guard case let .moveCapsIntermediate(candidates)? = review.verdicts.first?.fixes.first else {
            return XCTFail("expected a move, got \(review.verdicts)")
        }
        let runtimePick = SessionCapsIntermediate.choose(preferred: 109, occupied: [110]) { $0 != 109 }
        XCTAssertEqual(candidates.first, runtimePick.map { SessionCapsIntermediate.kanataName($0) })
        XCTAssertEqual(candidates.first, "f20")
    }

    func testEveryAlternativeTakenRefuses() {
        let taken = Set(SessionCapsIntermediate.pool.filter { $0 != 109 })
        manager.admissionEnvironment = .init(intermediateUsage: 109, occupied: taken, foreignCapsOwner: nil)
        let rule = CustomRule(title: "Mine", input: "f18", action: .keystroke(key: "a"))
        let review = manager.reviewAdmission(forProposed: rule, profile: allowAll)
        XCTAssertEqual(review.refusal, "Mine uses F18, and every alternative (F13–F20) is already taken.")
        XCTAssertTrue(review.notes.isEmpty)
    }

    func testEnablingACollectionOnTheReservedKeyIsReviewedTheSameWay() {
        manager.admissionEnvironment = .init(capsIntermediate: "f18")
        let collection = RuleCollection(
            id: UUID(), name: "Mine", summary: "", category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "f18"))],
            isEnabled: false, icon: "", tags: [], targetLayer: .base, momentaryActivator: nil, configuration: .list
        )
        manager.ruleCollections = [collection]
        let review = manager.reviewAdmission(forEnabling: collection, profile: allowAll)
        XCTAssertNil(review.refusal)
        XCTAssertEqual(review.notes.first, "Mine uses F18, which KeyPath had reserved for Caps Lock. Caps Lock will use F19 instead.")
    }

    // MARK: - Refusals

    func testCapsRuleIsRefusedWhileAnotherAppHoldsCapsLock() {
        manager.admissionEnvironment = .init(capsIntermediate: "f18", foreignCapsOwner: "Raycast")
        let rule = CustomRule(title: "Hyper", input: "caps", action: .keystroke(key: "esc"))
        let review = manager.reviewAdmission(forProposed: rule, profile: allowAll)
        XCTAssertEqual(review.refusal, "Hyper needs Caps Lock, but Raycast is remapping it. Turn that off first.")
    }

    func testOutputTheBackendCannotSendIsRefusedNamingTheKey() {
        let rule = CustomRule(title: "Louder", input: "f12", action: .keystroke(key: "volu"))
        let review = manager.reviewAdmission(forProposed: rule, profile: noVolume)
        XCTAssertEqual(review.refusal, "Louder sends Volume Up, which the current backend can't send.")
        XCTAssertNil(manager.reviewAdmission(forProposed: rule, profile: allowAll).refusal)
    }

    func testConflictsAreLeftToTheDialog() {
        manager.customRules = [CustomRule(title: "Theirs", input: "f13", action: .keystroke(key: "f15"))]
        let rule = CustomRule(title: "Mine", input: "f13", action: .keystroke(key: "a"))
        XCTAssertEqual(manager.reviewAdmission(forProposed: rule, profile: allowAll), .clear)
        XCTAssertNotNil(manager.conflictInfo(for: rule), "the conflict is still there for the dialog")
    }

    // MARK: - Catalog

    func testCatalogReasonIsTheEngineSentence() {
        let reason = RuleCollectionCatalog.driverlessUnavailableReason(for: RuleCollectionIdentifier.funLayer, profile: noMedia)
        XCTAssertEqual(reason?.hasSuffix("which the current backend can't send."), true, reason ?? "nil")
        XCTAssertNil(RuleCollectionCatalog.driverlessUnavailableReason(for: RuleCollectionIdentifier.funLayer, profile: allowAll))
    }

    // MARK: - Mapper

    func testMapperRefusesBeforeWritingAndSaysWhy() async {
        BackendCapabilityProfile.testOverride = noVolume
        defer { BackendCapabilityProfile.testOverride = nil }
        let coordinator = RuntimeCoordinator()
        let vm = MapperViewModel()
        vm.inputSequence = KeySequence(keys: [KeyPress(baseKey: "f12", modifiers: [], keyCode: 111)], captureMode: .single)
        vm.outputSequence = KeySequence(keys: [KeyPress(baseKey: "volumeup", modifiers: [], keyCode: 72)], captureMode: .single)
        let before = coordinator.ruleCollectionsManager.customRules.count
        await vm.save(kanataManager: coordinator)
        XCTAssertTrue(vm.statusIsError)
        XCTAssertEqual(vm.statusMessage?.hasSuffix("sends Volume Up, which the current backend can't send."), true, vm.statusMessage ?? "nil")
        XCTAssertEqual(coordinator.ruleCollectionsManager.customRules.count, before, "nothing was written")
    }
}
