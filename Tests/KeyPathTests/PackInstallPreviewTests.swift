import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// Phase 4c: pack installs go through admission. One click when nothing the
/// user has would change; a preview only on a choice or a block; automatic
/// resolutions summarised; declared pack conflicts and requirements enforced.
@MainActor
final class PackInstallPreviewTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private var tracker: InstalledPackTracker!
    private let allowAll = BackendCapabilityProfile(backend: .session) { _ in true }

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
        try await service.saveRuleState(ruleCollections: [], customRules: [], collectionStore: collections, customStore: rules)
        tracker = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"))
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        manager = nil; tracker = nil; directory = nil
        try await super.tearDown()
    }

    private func bindingPack(id: String = "com.keypath.test.preview", inputs: [String]) -> Pack {
        Pack(id: id, version: "1", name: "Preview Pack", tagline: "t", shortDescription: "s", longDescription: "",
             category: "Test", iconSymbol: "testtube.2",
             bindings: inputs.map { PackBindingTemplate(input: $0, output: "f14", title: $0) })
    }

    func testCleanPackNeedsNoConfirmation() async {
        let preview = await PackInstaller.shared.admissionPreview(for: bindingPack(inputs: ["f13"]), manager: manager,
                                                                  installedPackTracker: tracker, profile: allowAll)
        XCTAssertFalse(preview.requiresConfirmation)
        XCTAssertTrue(preview.items.isEmpty)
        XCTAssertTrue(preview.summaryLines.isEmpty)
    }

    func testConflictWithAnExistingRuleNeedsAChoiceAndOffersThatRule() async throws {
        let mine = CustomRule(title: "Mine", input: "f13", action: .keystroke(key: "f15"))
        manager.customRules = [mine]
        let pack = bindingPack(inputs: ["f13"])
        let preview = await PackInstaller.shared.admissionPreview(for: pack, manager: manager,
                                                                  installedPackTracker: tracker, profile: allowAll)
        XCTAssertTrue(preview.needsChoice)
        XCTAssertFalse(preview.isBlocked)
        XCTAssertEqual(preview.disableOptions.map(\.id), [mine.id])
        XCTAssertEqual(preview.disableOptions.first?.label, "Turn off Mine")
        XCTAssertEqual(preview.items.first?.presentation.title, "Key conflict on f13")

        // A checked install stops and hands the preview to the UI.
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker, admission: .checked)
            XCTFail("expected needsReview")
        } catch let PackInstaller.InstallError.needsReview(p) {
            XCTAssertEqual(p.disableOptions.map(\.id), [mine.id])
        }
        let installedAfterReview: Bool = await tracker.isInstalled(packID: pack.id)
        XCTAssertFalse(installedAfterReview)
    }

    func testConfirmedInstallTurnsOffTheChosenRuleAndInstalls() async throws {
        let mine = CustomRule(title: "Mine", input: "f13", action: .keystroke(key: "f15"))
        manager.customRules = [mine]
        try await manager.configurationService.saveRuleState(
            ruleCollections: [], customRules: [mine],
            collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore
        )
        let pack = bindingPack(inputs: ["f13"])
        _ = try await PackInstaller.shared.install(
            pack, manager: manager, installedPackTracker: tracker,
            admission: .confirmed(disablingCollections: [], disablingRules: [mine.id], removingPacks: [])
        )
        let installedAfterConfirm: Bool = await tracker.isInstalled(packID: pack.id)
        XCTAssertTrue(installedAfterConfirm)
        XCTAssertEqual(manager.customRules.first { $0.id == mine.id }?.isEnabled, false)
        XCTAssertTrue(manager.customRules.contains { $0.packSource == pack.id && $0.input == "f13" && $0.isEnabled })
    }

    func testCollectionPackConflictOffersTheOtherCollection() async {
        let other = RuleCollection(id: UUID(), name: "Other", summary: "", category: .custom,
                                   mappings: [KeyMapping(input: "f", action: .keystroke(key: "x"))],
                                   isEnabled: true, icon: "star", tags: [], targetLayer: .base,
                                   momentaryActivator: nil, configuration: .list)
        manager.ruleCollections = [other]
        let preview = await PackInstaller.shared.admissionPreview(for: PackRegistry.homeRowArrows, manager: manager,
                                                                  installedPackTracker: tracker, profile: allowAll)
        XCTAssertTrue(preview.needsChoice, "\(preview.items)")
        XCTAssertTrue(preview.disableOptions.contains { $0.id == other.id })
        XCTAssertFalse(preview.disableOptions.contains { $0.id == RuleCollectionIdentifier.homeRowArrows })
    }

    func testMissingRequiredAppBlocksWithAnInstallLink() async {
        let preview = await PackInstaller.shared.admissionPreview(for: PackRegistry.kindaVim, manager: manager,
                                                                  installedPackTracker: tracker, profile: allowAll,
                                                                  fileExists: { _ in false })
        XCTAssertTrue(preview.isBlocked)
        XCTAssertEqual(preview.blockingItems.first?.presentation.options.map(\.label), ["Install KindaVim"])
        XCTAssertTrue(preview.disableOptions.isEmpty)
    }

    func testDeclaredPackConflictOffersRemovingTheInstalledPack() async throws {
        try await tracker.upsert(InstalledPackRecord(packID: PackRegistry.kindaVim.id, version: "1", installedAt: Date()))
        let vim = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.vim-navigation"))
        let preview = await PackInstaller.shared.admissionPreview(for: vim, manager: manager,
                                                                  installedPackTracker: tracker, profile: allowAll,
                                                                  fileExists: { _ in true })
        XCTAssertTrue(preview.needsChoice, "\(preview.items)")
        XCTAssertEqual(preview.removeOptions.map(\.packID), [PackRegistry.kindaVim.id])
    }

    func testUncheckedInstallKeepsTheOldBehaviour() async throws {
        let mine = CustomRule(title: "Mine", input: "f13", action: .keystroke(key: "f15"))
        manager.customRules = [mine]
        let pack = bindingPack(inputs: ["f13"])
        // Pack wins silently, as before this phase (onboarding and programmatic callers).
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker, admission: .unchecked)
        let installedUnchecked: Bool = await tracker.isInstalled(packID: pack.id)
        XCTAssertTrue(installedUnchecked)
    }
}
