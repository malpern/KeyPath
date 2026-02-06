import Foundation
@testable import KeyPathAppKit
import Testing

/// Tests for MainAppStateController - main app validation coordination
@Suite("Main App State Controller Tests")
@MainActor
struct MainAppStateControllerTests {
    // MARK: - ValidationState Tests

    @Test("ValidationState.isSuccess returns true only for success")
    func validationStateIsSuccess() {
        #expect(MainAppStateController.ValidationState.success.isSuccess == true)
        #expect(MainAppStateController.ValidationState.checking.isSuccess == false)
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 1, totalCount: 1).isSuccess
                == false
        )
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 0, totalCount: 1).isSuccess
                == false
        )
    }

    @Test("ValidationState.hasCriticalIssues detects blocking issues")
    func validationStateHasCriticalIssues() {
        #expect(MainAppStateController.ValidationState.success.hasCriticalIssues == false)
        #expect(MainAppStateController.ValidationState.checking.hasCriticalIssues == false)
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 1, totalCount: 1)
                .hasCriticalIssues == true
        )
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 0, totalCount: 1)
                .hasCriticalIssues == false
        )
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 2, totalCount: 3)
                .hasCriticalIssues == true
        )
    }

    @Test("ValidationState equality works correctly")
    func validationStateEquality() {
        #expect(MainAppStateController.ValidationState.success == .success)
        #expect(MainAppStateController.ValidationState.checking == .checking)
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 1, totalCount: 2)
                == MainAppStateController.ValidationState.failed(blockingCount: 1, totalCount: 2)
        )
        #expect(
            MainAppStateController.ValidationState.failed(blockingCount: 1, totalCount: 2)
                != MainAppStateController.ValidationState.failed(blockingCount: 2, totalCount: 2)
        )
        #expect(MainAppStateController.ValidationState.success != .checking)
    }

    // MARK: - Initialization Tests

    @Test("Controller initializes with nil validation state")
    func initialization() {
        let controller = MainAppStateController()
        #expect(controller.validationState == nil)
        #expect(controller.issues.isEmpty)
        #expect(controller.lastValidationDate == nil)
    }

    @Test("Controller can be configured without crashing")
    func configuration() {
        let controller = MainAppStateController()
        let manager = RuntimeCoordinator()

        // Should not crash
        controller.configure(with: manager)
    }

    @Test("isConfigured is false before configure() and true after")
    func isConfiguredProperty() {
        let controller = MainAppStateController()

        // Before configure: should be false
        #expect(controller.isConfigured == false)

        // Configure
        let manager = RuntimeCoordinator()
        controller.configure(with: manager)

        // After configure: should be true
        #expect(controller.isConfigured == true)
    }

    // MARK: - State Observation Tests

    @Test("ValidationState is observable")
    func stateObservability() {
        let controller = MainAppStateController()

        // Initial state should be nil
        #expect(controller.validationState == nil)

        // Simulate state changes
        controller.validationState = .checking
        #expect(controller.validationState == .checking)

        controller.validationState = .success
        #expect(controller.validationState == .success)

        controller.validationState = .failed(blockingCount: 1, totalCount: 2)
        #expect(controller.validationState?.hasCriticalIssues == true)
    }
}

/// Tests for validation state transitions
@Suite("Validation State Transition Tests")
@MainActor
struct ValidationStateTransitionTests {
    @Test("Typical successful validation flow")
    func successfulValidationFlow() {
        let controller = MainAppStateController()

        // Start: nil (not yet validated)
        #expect(controller.validationState == nil)

        // User opens app → checking
        controller.validationState = .checking
        #expect(controller.validationState == .checking)
        #expect(controller.validationState?.isSuccess == false)

        // Validation completes successfully
        controller.validationState = .success
        #expect(controller.validationState?.isSuccess == true)
        #expect(controller.validationState?.hasCriticalIssues == false)
    }

    @Test("Validation failure flow")
    func failedValidationFlow() {
        let controller = MainAppStateController()

        // Start: nil
        #expect(controller.validationState == nil)

        // User opens app → checking
        controller.validationState = .checking

        // Validation finds issues
        controller.validationState = .failed(blockingCount: 2, totalCount: 5)
        #expect(controller.validationState?.isSuccess == false)
        #expect(controller.validationState?.hasCriticalIssues == true)
    }

    @Test("Non-blocking issues flow")
    func nonBlockingIssuesFlow() {
        let controller = MainAppStateController()

        // Validation finds non-critical issues
        controller.validationState = .failed(blockingCount: 0, totalCount: 3)

        // Has issues but not critical
        #expect(controller.validationState?.isSuccess == false)
        #expect(controller.validationState?.hasCriticalIssues == false)
    }
}

/// Behavioral tests for MainAppStateController async validation flows
@Suite("Main App State Controller Behavior Tests")
@MainActor
struct MainAppStateControllerBehaviorTests {
    @Test("performInitialValidation is a no-op before configure")
    func performInitialValidationWithoutConfiguration() async {
        let controller = MainAppStateController()

        await controller.performInitialValidation()

        #expect(controller.validationState == nil)
        #expect(controller.issues.isEmpty)
        #expect(controller.lastValidationDate == nil)
    }

    @Test("refreshValidation on unconfigured controller surfaces failed state")
    func refreshValidationWithoutConfiguration() async {
        let controller = MainAppStateController()

        await controller.refreshValidation()

        guard case let .failed(blockingCount, totalCount) = controller.validationState else {
            Issue.record("Expected failed validation state")
            return
        }
        #expect(blockingCount == 1)
        #expect(totalCount == 1)
        #expect(controller.issues.count == 1)
    }

    @Test("revalidate on unconfigured controller surfaces failed state")
    func revalidateWithoutConfiguration() async {
        let controller = MainAppStateController()

        await controller.revalidate()

        guard case let .failed(blockingCount, totalCount) = controller.validationState else {
            Issue.record("Expected failed validation state")
            return
        }
        #expect(blockingCount == 1)
        #expect(totalCount == 1)
        #expect(controller.issues.count == 1)
    }

    @Test("performInitialValidation after configure surfaces failure when service is unhealthy")
    func performInitialValidationAfterConfigure() async {
        let controller = MainAppStateController()
        controller.configure(with: RuntimeCoordinator())

        await controller.performInitialValidation()

        guard case let .failed(blockingCount, totalCount) = controller.validationState else {
            Issue.record("Expected failed validation state when test-mode service health is unhealthy")
            return
        }
        #expect(blockingCount == 1)
        #expect(totalCount == 1)
        #expect(controller.issues.count == 1)
    }
}
