import AppKit
@testable import KeyPathAppKit
import KeyPathRulesCore
import Observation
@preconcurrency import XCTest

@MainActor
final class KanataViewModelTests: KeyPathTestCase {
    func testRuntimeStatusIsAvailableImmediatelyAndObservedFromItsOwners() {
        let manager = RuntimeCoordinator()
        manager.lastError = "Runtime stopped"
        let viewModel = KanataViewModel(manager: manager)

        assertObserved({ viewModel.lastError }, changing: { manager.lastError = nil },
                       from: "Runtime stopped", to: nil)
        assertObserved({ viewModel.currentLayerName }, changing: {
            manager.ruleCollectionsManager.onLayerChanged?("nav")
        }, from: RuleCollectionLayer.base.displayName, to: "nav")
        assertObserved({ viewModel.capsPausedMessage }, changing: {
            manager.serviceLifecycleCoordinator.sessionCapsPaused = "Selected keyboard disconnected"
        }, from: nil, to: "Selected keyboard disconnected")
        assertObserved({ viewModel.capsPausedMessage }, changing: {
            manager.serviceLifecycleCoordinator.sessionCapsPaused = nil
        }, from: "Selected keyboard disconnected", to: nil)
    }

    func testRepeatedRuntimeErrorCanPresentAgainWithoutClearingStatus() throws {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let message = "Could not write configuration"

        manager.ruleCollectionsManager.onError?(message)
        let first = try XCTUnwrap(viewModel.reportedError)
        XCTAssertEqual(first.message, message)
        XCTAssertEqual(viewModel.lastError, message)

        let changed = observeChange { viewModel.reportedError }
        manager.ruleCollectionsManager.onError?(message)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 0), .completed)
        let retry = try XCTUnwrap(viewModel.reportedError)
        XCTAssertNotEqual(retry, first)
        XCTAssertEqual(retry.message, message)
        XCTAssertEqual(viewModel.lastError, message)
    }

    func testWarningsReachToastOncePerChangeAndCanRepeatAfterClear() {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let lifecycle = manager.serviceLifecycleCoordinator
        let warning = "Caps Lock rules are off"

        lifecycle.onWarning?(warning)
        XCTAssertEqual(viewModel.toastMessage, warning)
        XCTAssertEqual(viewModel.toastType, .warning)

        viewModel.toastMessage = nil
        lifecycle.onWarning?(warning)
        manager.lastError = "Runtime stopped"
        XCTAssertNil(viewModel.toastMessage)

        lifecycle.onWarning?(nil)
        lifecycle.onWarning?(warning)
        XCTAssertEqual(viewModel.toastMessage, warning)
    }

    func testRuleConflictChoiceClosesObservedSheetAndResumesRequest() async {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let context = RuleConflictContext(
            newRule: .init(name: "New", icon: "keyboard", summary: "", mappings: []),
            existingRule: .init(name: "Existing", icon: "keyboard", summary: "", mappings: []),
            conflictingKeys: ["a"]
        )
        let opened = observeChange { viewModel.showRuleConflictDialog }
        let request = Task { await manager.promptForConflictResolution(context) }
        defer { request.cancel() }
        let presentation = await XCTWaiter.fulfillment(of: [opened], timeout: 2)
        guard presentation == .completed else { return XCTFail("Rule conflict did not present") }
        XCTAssertEqual(viewModel.pendingRuleConflict, context)

        assertObserved({ viewModel.showRuleConflictDialog }, changing: {
            viewModel.resolveRuleConflict(with: .keepNew)
        }, from: true, to: false)
        guard viewModel.pendingRuleConflict == nil else { return XCTFail("Rule conflict was not resolved") }
        let choice = await request.value
        XCTAssertEqual(choice, .keepNew)
    }

    func testDismissingMappingConflictCancelsPendingSave() async {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let context = MappingConflictContext(
            explanation: "Two collections claim A",
            options: [.init(id: UUID(), name: "Existing", icon: "keyboard")]
        )
        let opened = observeChange { viewModel.showMappingConflictDialog }
        let request = Task { await manager.promptForMappingConflict(context) }
        defer { request.cancel() }
        let presentation = await XCTWaiter.fulfillment(of: [opened], timeout: 2)
        guard presentation == .completed else { return XCTFail("Mapping conflict did not present") }
        XCTAssertEqual(viewModel.pendingMappingConflict, context)

        assertObserved({ viewModel.showMappingConflictDialog }, changing: {
            viewModel.showMappingConflictDialog = false
        }, from: true, to: false)
        guard viewModel.pendingMappingConflict == nil else { return XCTFail("Mapping conflict was not cancelled") }
        let choice = await request.value
        XCTAssertNil(choice)
    }

    func testRuleSetupSessionIsObservedAndCancellationReturnsToSave() async throws {
        _ = NSApplication.shared
        defer { SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsRules) }
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let presentSetup = try XCTUnwrap(manager.ruleCollectionsManager.onPrerequisiteSetup)
        let context = RulePrerequisiteResolutionContext(
            operation: .enable,
            candidate: RuleCollection(
                id: UUID(), name: "Quick Launcher", summary: "", category: .custom,
                mappings: [], isEnabled: false
            ),
            prerequisites: [], affectedConsumers: [], availableProviders: []
        )
        let opened = observeChange { viewModel.pendingRuleSetup?.id }
        let request = Task {
            let result = await presentSetup(context) { _ in
                XCTFail("Cancelling rule setup must not apply any changes")
                return .failure(CancellationError())
            }
            return !result.success && result.error is CancellationError
        }
        let presentation = await XCTWaiter.fulfillment(of: [opened], timeout: 2)
        guard presentation == .completed else { return XCTFail("Rule setup did not present") }
        let session = try XCTUnwrap(viewModel.pendingRuleSetup)
        XCTAssertEqual(session.context, context)

        assertObserved({ viewModel.pendingRuleSetup?.id }, changing: {
            session.finish(.failure(CancellationError()))
        }, from: session.id, to: nil)
        guard viewModel.pendingRuleSetup == nil else { return XCTFail("Rule setup was not cancelled") }
        let cancelled = await request.value
        XCTAssertTrue(cancelled)
    }

    func testConfirmingDependentResolutionClosesSheetAndResumesDisable() async {
        _ = NSApplication.shared
        defer { SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsRules) }
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let context = RuleDependentResolutionContext(
            providerID: UUID(), providerName: "Leader Key",
            dependents: [], affectedConsumers: [], availableProviders: []
        )
        let opened = observeChange { viewModel.showDependentResolutionDialog }
        let request = Task { await manager.promptForDependentResolution(context) }
        defer { request.cancel() }
        let presentation = await XCTWaiter.fulfillment(of: [opened], timeout: 2)
        guard presentation == .completed else { return XCTFail("Dependent resolution did not present") }
        XCTAssertEqual(viewModel.pendingDependentResolution?.providerName, "Leader Key")

        assertObserved({ viewModel.showDependentResolutionDialog }, changing: {
            viewModel.resolveDependentResolution(with: .disableAnyway)
        }, from: true, to: false)
        guard viewModel.pendingDependentResolution == nil else { return XCTFail("Dependent request was not resolved") }
        let choice = await request.value
        XCTAssertEqual(choice, .disableAnyway)
    }

    private func observeChange(_ read: () -> some Any) -> XCTestExpectation {
        let changed = XCTestExpectation(description: "Observed UI state changed")
        _ = withObservationTracking(read, onChange: { changed.fulfill() })
        return changed
    }

    private func assertObserved<Value: Equatable>(
        _ read: () -> Value, changing mutate: () -> Void, from old: Value, to new: Value,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(read(), old, file: file, line: line)
        let changed = observeChange(read)
        mutate()
        XCTAssertEqual(read(), new, file: file, line: line)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 0), .completed, file: file, line: line)
    }
}
