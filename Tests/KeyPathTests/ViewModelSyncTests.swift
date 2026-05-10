@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests that KanataViewModel.ruleCollections stays in sync
/// after collection config updates. Catches the bug where
/// Pack Detail views showed stale data after convention/picker changes.
@MainActor
final class ViewModelSyncTests: XCTestCase {

    private func createTestVM() async -> KanataViewModel {
        TestEnvironment.forceTestMode = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-sync-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let coordinator = RuntimeCoordinator(
            injectedConfigurationService: ConfigurationService(configDirectory: tempDir.path)
        )
        let vm = KanataViewModel(manager: coordinator)
        return vm
    }

    func testWindowConventionUpdate_SyncsRuleCollections() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let vm = await createTestVM()

        // Enable window snapping
        await vm.toggleRuleCollection(RuleCollectionIdentifier.windowSnapping, enabled: true)

        let before = vm.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        let beforeConvention = before?.windowKeyConvention ?? .standard

        // Change convention
        let newConvention: WindowKeyConvention = beforeConvention == .standard ? .vim : .standard
        await vm.updateWindowKeyConvention(RuleCollectionIdentifier.windowSnapping, convention: newConvention)

        let after = vm.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        XCTAssertEqual(after?.windowKeyConvention, newConvention,
                       "View model ruleCollections should reflect updated convention immediately")
    }

    func testTapOutputUpdate_SyncsRuleCollections() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let vm = await createTestVM()

        await vm.toggleRuleCollection(RuleCollectionIdentifier.capsLockRemap, enabled: true)

        await vm.updateCollectionTapOutput(RuleCollectionIdentifier.capsLockRemap, tapOutput: "bspc")

        let collection = vm.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        if case let .tapHoldPicker(config) = collection?.configuration {
            XCTAssertEqual(config.selectedTapOutput, "bspc",
                           "View model should reflect updated tap output")
        } else {
            XCTFail("Caps Lock collection should have tapHoldPicker config")
        }
    }

    func testHoldOutputUpdate_SyncsRuleCollections() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let vm = await createTestVM()

        await vm.toggleRuleCollection(RuleCollectionIdentifier.capsLockRemap, enabled: true)

        await vm.updateCollectionHoldOutput(RuleCollectionIdentifier.capsLockRemap, holdOutput: "lctl")

        let collection = vm.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        if case let .tapHoldPicker(config) = collection?.configuration {
            XCTAssertEqual(config.selectedHoldOutput, "lctl",
                           "View model should reflect updated hold output")
        } else {
            XCTFail("Caps Lock collection should have tapHoldPicker config")
        }
    }

    func testToggleCollection_SyncsRuleCollections() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let vm = await createTestVM()

        let wasBefore = vm.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.homeRowMods }?.isEnabled ?? false

        await vm.toggleRuleCollection(RuleCollectionIdentifier.homeRowMods, enabled: !wasBefore)

        let isAfter = vm.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.homeRowMods }?.isEnabled ?? wasBefore

        XCTAssertNotEqual(wasBefore, isAfter,
                          "View model should reflect toggled state")
    }
}
