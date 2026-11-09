import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
import Testing

// MARK: - Initialization & Configuration

@Suite("RecoveryCoordinator — Initialization & Configuration")
@MainActor
struct RecoveryCoordinatorInitTests {
    @Test("unconfigured coordinator has no-op handlers")
    func unconfiguredCoordinatorHasNoOpHandlers() async {
        let coordinator = RecoveryCoordinator()

        // The default killAllKanataProcesses throws, so pauseMappings returns false
        let result = await coordinator.pauseMappings()
        #expect(result == false)
    }

    @Test("configure replaces handlers")
    func configureReplacesHandlers() async {
        let coordinator = RecoveryCoordinator()

        var killCalled = false
        var restartServiceCalled = false

        coordinator.configure(
            killAllKanataProcesses: { killCalled = true },
            restartService: { _ in
                restartServiceCalled = true
                return true
            }
        )

        // pauseMappings calls killAllKanataProcesses
        let pauseResult = await coordinator.pauseMappings()
        #expect(killCalled, "killAllKanataProcesses should have been called")
        #expect(pauseResult == true)

        // resumeMappings calls restartService
        let resumeResult = await coordinator.resumeMappings()
        #expect(restartServiceCalled, "restartService should have been called")
        #expect(resumeResult == true)
    }
}

// MARK: - Auto-Fix Logic

@Suite("RecoveryCoordinator — Auto-Fix Logic")
@MainActor
struct RecoveryCoordinatorAutoFixTests {
    @Test("canAutoFix returns diagnostic.canAutoFix")
    func canAutoFixReturnsDiagnosticValue() {
        let coordinator = RecoveryCoordinator()

        let fixable = makeDiagnostic(canAutoFix: true)
        #expect(coordinator.canAutoFix(fixable) == true)

        let notFixable = makeDiagnostic(canAutoFix: false)
        #expect(coordinator.canAutoFix(notFixable) == false)
    }

    @Test("autoFixActionType returns resetConfig for configuration category")
    func autoFixReturnsResetConfigForConfiguration() {
        let coordinator = RecoveryCoordinator()
        let diagnostic = makeDiagnostic(category: .configuration, canAutoFix: true)

        let actionType = coordinator.autoFixActionType(diagnostic)
        #expect(actionType == .resetConfig)
    }

    @Test("autoFixActionType returns restartService for process terminated")
    func autoFixReturnsRestartServiceForProcessTerminated() {
        let coordinator = RecoveryCoordinator()
        let diagnostic = makeDiagnostic(
            category: .process,
            title: "Process Terminated",
            canAutoFix: true
        )

        let actionType = coordinator.autoFixActionType(diagnostic)
        #expect(actionType == .restartService)
    }

    @Test("autoFixActionType returns nil when canAutoFix is false")
    func autoFixReturnsNilWhenNotFixable() {
        let coordinator = RecoveryCoordinator()
        let diagnostic = makeDiagnostic(category: .configuration, canAutoFix: false)

        let actionType = coordinator.autoFixActionType(diagnostic)
        #expect(actionType == nil)
    }

    @Test("autoFixActionType returns nil for unrecognized categories")
    func autoFixReturnsNilForUnrecognizedCategories() {
        let coordinator = RecoveryCoordinator()
        let diagnostic = makeDiagnostic(category: .conflict, canAutoFix: true)

        let actionType = coordinator.autoFixActionType(diagnostic)
        #expect(actionType == nil)
    }
}

// MARK: - Pause/Resume

@Suite("RecoveryCoordinator — Pause/Resume")
@MainActor
struct RecoveryCoordinatorPauseResumeTests {
    @Test("pauseMappings succeeds when kill succeeds")
    func pauseSucceedsWhenKillSucceeds() async {
        let coordinator = RecoveryCoordinator()
        coordinator.configure(
            killAllKanataProcesses: { /* success — no throw */ },
            restartService: { _ in true }
        )

        let result = await coordinator.pauseMappings()
        #expect(result == true)
    }

    @Test("pauseMappings fails when kill throws")
    func pauseFailsWhenKillThrows() async {
        let coordinator = RecoveryCoordinator()
        coordinator.configure(
            killAllKanataProcesses: { throw TestError.intentional },
            restartService: { _ in true }
        )

        let result = await coordinator.pauseMappings()
        #expect(result == false)
    }

    @Test("resumeMappings succeeds when restart succeeds")
    func resumeSucceedsWhenRestartSucceeds() async {
        let coordinator = RecoveryCoordinator()
        coordinator.configure(
            killAllKanataProcesses: {},
            restartService: { _ in true }
        )

        let result = await coordinator.resumeMappings()
        #expect(result == true)
    }

    @Test("resumeMappings fails when restart fails")
    func resumeFailsWhenRestartFails() async {
        let coordinator = RecoveryCoordinator()
        coordinator.configure(
            killAllKanataProcesses: {},
            restartService: { _ in false }
        )

        let result = await coordinator.resumeMappings()
        #expect(result == false)
    }
}

// MARK: - Test Helpers

private enum TestError: Error {
    case intentional
}

private func makeDiagnostic(
    severity: DiagnosticSeverity = .error,
    category: DiagnosticCategory = .process,
    title: String = "Test Diagnostic",
    canAutoFix: Bool = false
) -> KanataDiagnostic {
    KanataDiagnostic(
        timestamp: Date(),
        severity: severity,
        category: category,
        title: title,
        description: "Test description",
        technicalDetails: "Test details",
        suggestedAction: "Test action",
        canAutoFix: canAutoFix
    )
}
