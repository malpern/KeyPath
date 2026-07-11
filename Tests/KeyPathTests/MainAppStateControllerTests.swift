import Foundation
@testable import KeyPathAppKit
@testable import KeyPathDaemonLifecycle
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
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
        controller.configure(
            serviceLifecycle: manager.serviceLifecycleCoordinator,
            onSystemHealthy: {}
        )
    }

    @Test("isConfigured is false before setValidator() and true after")
    func isConfiguredProperty() {
        let controller = MainAppStateController()

        // Before setValidator: should be false
        #expect(controller.isConfigured == false)

        // Configure with lifecycle coordinator
        let manager = RuntimeCoordinator()
        controller.configure(
            serviceLifecycle: manager.serviceLifecycleCoordinator,
            onSystemHealthy: {}
        )

        // Still false without validator
        #expect(controller.isConfigured == false)

        // Inject validator
        controller.setValidator(SystemValidator(processLifecycleManager: ProcessLifecycleManager()))

        // Now should be true
        #expect(controller.isConfigured == true)
    }

    @Test("issues array can be populated and cleared")
    func issuesArrayPopulateAndClear() {
        let controller = MainAppStateController()
        #expect(controller.issues.isEmpty)

        // Populate with non-empty array
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .warning,
                category: .daemon,
                title: "Test issue",
                description: "A test issue",
                autoFixAction: nil,
                userAction: nil
            ),
        ]
        #expect(controller.issues.count == 1)

        // Clear and verify empty
        controller.issues = []
        #expect(controller.issues.isEmpty)
    }

    @Test("Menu bar health falls back to validation before matrix classification")
    func menuBarHealthFallsBackBeforeMatrixClassification() {
        let controller = MainAppStateController()

        controller.validationState = .success
        controller.issues = []
        #expect(controller.menuBarSystemHealthy == true)

        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .error,
                category: .daemon,
                title: "Runtime stopped",
                description: "Kanata is not running",
                autoFixAction: nil,
                userAction: nil
            ),
        ]
        #expect(controller.menuBarSystemHealthy == false)
    }

    @Test("Menu bar health prefers shared state matrix row when available")
    func menuBarHealthPrefersStateMatrixRow() {
        let controller = MainAppStateController()

        controller.validationState = .success
        controller.issues = []
        controller.lastInstallerStateMatrixRow = .runningButTCPNotResponding
        controller.lastInstallerStateMatrixPlan = [.restartOrRecoverKanataRuntime]
        #expect(controller.menuBarSystemHealthy == false)

        controller.validationState = .failed(blockingCount: 1, totalCount: 1)
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .error,
                category: .daemon,
                title: "Stale issue",
                description: "Legacy validation state is stale",
                autoFixAction: nil,
                userAction: nil
            ),
        ]
        controller.lastInstallerStateMatrixRow = .runningAndTCPResponding
        controller.lastInstallerStateMatrixPlan = []
        #expect(controller.menuBarSystemHealthy == true)
    }

    @Test("lastValidationDate is settable")
    func lastValidationDateSettable() {
        let controller = MainAppStateController()
        #expect(controller.lastValidationDate == nil)

        let now = Date()
        controller.lastValidationDate = now
        #expect(controller.lastValidationDate != nil)
        #expect(controller.lastValidationDate == now)
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

    @Test("Re-validation after success transitions through checking")
    func revalidationAfterSuccessTransitionsThroughChecking() {
        let controller = MainAppStateController()

        // First validation succeeds
        controller.validationState = .success
        #expect(controller.validationState?.isSuccess == true)

        // Re-validation starts: back to checking
        controller.validationState = .checking
        #expect(controller.validationState == .checking)
        #expect(controller.validationState?.isSuccess == false)

        // Re-validation completes: success again
        controller.validationState = .success
        #expect(controller.validationState?.isSuccess == true)
    }

    @Test("Failed state with zero total count")
    func failedStateWithZeroTotalCount() {
        let state = MainAppStateController.ValidationState.failed(
            blockingCount: 0, totalCount: 0
        )
        #expect(state.isSuccess == false)
        #expect(state.hasCriticalIssues == false)
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

    @Test("refreshValidation on unconfigured controller surfaces checking state")
    func refreshValidationWithoutConfiguration() async {
        let controller = MainAppStateController()

        await controller.refreshValidation()

        #expect(controller.validationState == .checking)
        #expect(controller.issues.isEmpty)
    }

    @Test("revalidate on unconfigured controller surfaces checking state")
    func revalidateWithoutConfiguration() async {
        let controller = MainAppStateController()

        await controller.revalidate()

        #expect(controller.validationState == .checking)
        #expect(controller.issues.isEmpty)
    }

    @Test("performInitialValidation after configure produces a non-nil validation state")
    func performInitialValidationAfterConfigure() async {
        let controller = MainAppStateController()
        let manager = RuntimeCoordinator()
        controller.configure(
            serviceLifecycle: manager.serviceLifecycleCoordinator,
            onSystemHealthy: {}
        )

        await controller.performInitialValidation()

        // After configure + validation, state should never remain nil
        #expect(controller.validationState != nil)
        #expect(controller.lastValidationDate != nil)

        // If failed, blocking count should be consistent
        if case let .failed(blockingCount, _) = controller.validationState {
            #expect(blockingCount >= 1)
        }
    }

    @Test("startup gate requires TCP responsiveness before reporting ready")
    func startupGateRequiresTCPResponsivenessBeforeReady() async {
        let controller = MainAppStateController()
        #if DEBUG
            var probeCount = 0
            var observedNonRespondingProbe = false
            controller.configureStartupGateTestingState(
                healthOverride: {
                    probeCount += 1
                    let isResponding = probeCount >= 2
                    if !isResponding {
                        observedNonRespondingProbe = true
                    }
                    return KanataHealthSnapshot(
                        isRunning: true,
                        isResponding: isResponding
                    )
                },
                transientWindowOverride: { false },
                timingOverride: (
                    definitiveGrace: 1.0,
                    transientGrace: 1.05,
                    checkInterval: 0.01
                )
            )
            defer { controller.resetStartupGateTestingState() }
        #endif

        let ready = await controller.evaluateKanataStartupGateForTesting()
        #expect(ready == true)
        #if DEBUG
            #expect(observedNonRespondingProbe == true)
            #expect(probeCount >= 2)
        #endif
    }

    @Test("startup gate does not report ready on persistent no-runtime evidence")
    func startupGateDoesNotReportReadyForPersistentNoRuntime() async {
        let controller = MainAppStateController()
        #if DEBUG
            controller.configureStartupGateTestingState(
                healthOverride: {
                    KanataHealthSnapshot(isRunning: false, isResponding: false)
                },
                transientWindowOverride: { false },
                timingOverride: (
                    definitiveGrace: 0.05,
                    transientGrace: 0.08,
                    checkInterval: 0.01
                )
            )
            defer { controller.resetStartupGateTestingState() }
        #endif

        let ready = await controller.evaluateKanataStartupGateForTesting()
        #expect(ready == false)
    }

    @Test("startup gate does not turn transient non-ready state into ready")
    func startupGateDoesNotPromoteTransientNonReadyState() async {
        let controller = MainAppStateController()
        #if DEBUG
            controller.configureStartupGateTestingState(
                healthOverride: {
                    KanataHealthSnapshot(isRunning: false, isResponding: false)
                },
                transientWindowOverride: { true },
                timingOverride: (
                    definitiveGrace: 0.05,
                    transientGrace: 0.08,
                    checkInterval: 0.01
                )
            )
            defer { controller.resetStartupGateTestingState() }
        #endif

        let ready = await controller.evaluateKanataStartupGateForTesting()
        #expect(ready == false)
    }

    @Test("performInitialValidation after configure sets lastValidationDate")
    func performInitialValidationSetsLastValidationDate() async {
        let controller = MainAppStateController()
        let manager = RuntimeCoordinator()
        controller.configure(
            serviceLifecycle: manager.serviceLifecycleCoordinator,
            onSystemHealthy: {}
        )

        #expect(controller.lastValidationDate == nil)
        await controller.performInitialValidation()
        #expect(controller.lastValidationDate != nil)
    }

    @Test("multiple rapid revalidate calls don't corrupt state")
    func multipleRapidRevalidateCallsDontCorruptState() async {
        let controller = MainAppStateController()

        // Call revalidate 3 times rapidly (unconfigured controller)
        await controller.revalidate()
        await controller.revalidate()
        await controller.revalidate()

        // Final state should be consistent: checking (unconfigured path)
        // and issues array should be valid (empty, not corrupted)
        #expect(controller.validationState != nil)
        #expect(controller.validationState == .checking)
        #expect(controller.issues.isEmpty)
    }

    @Test("Unknown TCP configuration remains inconclusive")
    func unknownTCPConfigurationRemainsInconclusive() async {
        let context = SystemContextBuilder(
            servicesHealthy: true,
            kanataTCPConfigured: nil,
            componentsInstalled: true
        ).build()
        let controller = configuredController(validator: StubSystemValidator(context: context))

        await controller.refreshValidation()

        #expect(controller.lastTCPConfigured == nil)
        #expect(controller.validationState == .checking)
    }

    @Test("A later complete capture resolves unknown TCP configuration")
    func laterCaptureResolvesUnknownTCPConfiguration() async {
        let unknown = SystemContextBuilder(
            servicesHealthy: true,
            kanataTCPConfigured: nil,
            componentsInstalled: true
        ).build()
        let healthy = SystemContextBuilder(
            servicesHealthy: true,
            kanataTCPConfigured: true,
            componentsInstalled: true
        ).build()
        let validator = SequenceSystemValidator(contexts: [unknown, healthy])
        let controller = configuredController(validator: validator)

        await controller.refreshValidation()
        #expect(controller.validationState == .checking)

        await controller.revalidate()
        #expect(controller.lastTCPConfigured == true)
        #expect(controller.validationState == .success)
        #expect(validator.checkCount == 2)
    }

    @Test("Explicit missing TCP configuration remains a failure")
    func explicitMissingTCPConfigurationRemainsFailure() async {
        let context = SystemContextBuilder(
            servicesHealthy: true,
            kanataTCPConfigured: false,
            componentsInstalled: true
        ).build()
        let controller = configuredController(validator: StubSystemValidator(context: context))

        await controller.refreshValidation()

        #expect(controller.lastTCPConfigured == false)
        #expect(controller.validationState?.hasCriticalIssues == true)
    }

    @Test("Concurrent refreshes publish one validation result")
    func concurrentRefreshesPublishOneValidationResult() async {
        let context = SystemContextBuilder(
            servicesHealthy: true,
            kanataTCPConfigured: true,
            componentsInstalled: true
        ).build()
        let validator = GatedCountingValidator(context: context)
        let controller = configuredController(validator: validator)

        async let first: Void = controller.refreshValidation()
        await Task.yield()
        async let second: Void = controller.refreshValidation()
        await Task.yield()
        validator.open()
        _ = await (first, second)

        #expect(validator.checkCount == 1)
        #expect(controller.validationState == .success)
    }

    @Test("startup gate with immediately-healthy service reports ready")
    func startupGateWithImmediatelyHealthyServiceReportsReady() async {
        let controller = MainAppStateController()
        #if DEBUG
            controller.configureStartupGateTestingState(
                healthOverride: {
                    KanataHealthSnapshot(isRunning: true, isResponding: true)
                },
                transientWindowOverride: { false },
                timingOverride: (
                    definitiveGrace: 1.0,
                    transientGrace: 1.05,
                    checkInterval: 0.01
                )
            )
            defer { controller.resetStartupGateTestingState() }
        #endif

        let ready = await controller.evaluateKanataStartupGateForTesting()
        #expect(ready == true)
    }

    private func configuredController(validator: any WizardSystemValidating) -> MainAppStateController {
        let controller = MainAppStateController()
        controller.setValidator(validator)
        #if DEBUG
            controller.configureStartupGateTestingState(
                healthOverride: {
                    KanataHealthSnapshot(isRunning: true, isResponding: true)
                },
                transientWindowOverride: { false }
            )
        #endif
        return controller
    }
}

@MainActor
private final class GatedCountingValidator: WizardSystemValidating {
    private let snapshot: SystemSnapshot
    private var isOpen = false
    private(set) var checkCount = 0

    init(context: SystemContext) {
        snapshot = SystemSnapshot(
            id: context.snapshotID,
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            helper: context.helper,
            compatibility: SystemCompatibilityStatus(
                macOSVersion: context.system.macOSVersion,
                driverCompatible: context.system.driverCompatible
            ),
            timestamp: context.timestamp,
            captureStatus: context.captureStatus
        )
    }

    func checkSystem() async -> SystemSnapshot {
        checkCount += 1
        while !isOpen, !Task.isCancelled {
            await Task.yield()
        }
        return snapshot
    }

    func open() {
        isOpen = true
    }
}

@MainActor
private final class SequenceSystemValidator: WizardSystemValidating {
    private var snapshots: [SystemSnapshot]
    private(set) var checkCount = 0

    init(contexts: [SystemContext]) {
        snapshots = contexts.map { context in
            SystemSnapshot(
                id: context.snapshotID,
                permissions: context.permissions,
                components: context.components,
                conflicts: context.conflicts,
                health: context.services,
                helper: context.helper,
                compatibility: SystemCompatibilityStatus(
                    macOSVersion: context.system.macOSVersion,
                    driverCompatible: context.system.driverCompatible
                ),
                timestamp: context.timestamp,
                captureStatus: context.captureStatus
            )
        }
    }

    func checkSystem() async -> SystemSnapshot {
        checkCount += 1
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }
        return snapshots[0]
    }
}
