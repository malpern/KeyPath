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
            restartKarabinerDaemon: { true },
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

// MARK: - VirtualHID Validation

@Suite("RecoveryCoordinator — VirtualHID Validation")
@MainActor
struct RecoveryCoordinatorVirtualHIDValidationTests {
    @Test("startKanataWithValidation calls onError when daemon not running")
    func callsOnErrorWhenDaemonNotRunning() async {
        let coordinator = RecoveryCoordinator()
        var errorMessage: String?

        await coordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { false },
            startKanata: { true },
            onError: { errorMessage = $0 }
        )

        #expect(errorMessage != nil, "onError should have been called")
        #expect(errorMessage?.contains("Recovery failed") == true)
    }

    @Test("startKanataWithValidation starts kanata when daemon running")
    func startsKanataWhenDaemonRunning() async {
        let coordinator = RecoveryCoordinator()
        var startKanataCalled = false

        await coordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { true },
            startKanata: {
                startKanataCalled = true
                return true
            },
            onError: { _ in }
        )

        #expect(startKanataCalled, "startKanata should have been called")
    }

    @Test("startKanataWithValidation does not start when daemon not running")
    func doesNotStartWhenDaemonNotRunning() async {
        let coordinator = RecoveryCoordinator()
        var startKanataCalled = false

        await coordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { false },
            startKanata: {
                startKanataCalled = true
                return true
            },
            onError: { _ in }
        )

        #expect(!startKanataCalled, "startKanata should NOT have been called")
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
            restartKarabinerDaemon: { true },
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
            restartKarabinerDaemon: { true },
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
            restartKarabinerDaemon: { true },
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
            restartKarabinerDaemon: { true },
            restartService: { _ in false }
        )

        let result = await coordinator.resumeMappings()
        #expect(result == false)
    }
}

// MARK: - Failure Diagnosis

@Suite("RecoveryCoordinator — Failure Diagnosis")
@MainActor
struct RecoveryCoordinatorFailureDiagnosisTests {
    @Test("diagnoseKanataFailure triggers recovery on exit code 6 with VirtualHID error")
    func triggersRecoveryOnExitCode6() async {
        let coordinator = RecoveryCoordinator()

        await confirmation("recovery triggered", expectedCount: 1) { confirm in
            coordinator.diagnoseKanataFailure(
                exitCode: 6,
                output: "error: connect_failed asio.system:61",
                diagnostics: [],
                addDiagnostic: { _ in },
                attemptRecovery: {
                    confirm()
                }
            )

            // The recovery runs in a detached Task inside diagnoseKanataFailure,
            // so yield briefly to let it execute.
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("diagnoseKanataFailure adds all diagnostics")
    func addsAllDiagnostics() {
        let coordinator = RecoveryCoordinator()

        let diagnostics = [
            makeDiagnostic(title: "Diag 1"),
            makeDiagnostic(title: "Diag 2"),
            makeDiagnostic(title: "Diag 3"),
        ]

        var addedTitles: [String] = []
        coordinator.diagnoseKanataFailure(
            exitCode: 0,
            output: "",
            diagnostics: diagnostics,
            addDiagnostic: { addedTitles.append($0.title) },
            attemptRecovery: {}
        )

        #expect(addedTitles.count == 3)
        #expect(addedTitles == ["Diag 1", "Diag 2", "Diag 3"])
    }

    @Test("diagnoseKanataFailure does not trigger recovery for normal exit")
    func doesNotTriggerRecoveryForNormalExit() async {
        let coordinator = RecoveryCoordinator()
        var recoveryCalled = false

        coordinator.diagnoseKanataFailure(
            exitCode: 0,
            output: "",
            diagnostics: [],
            addDiagnostic: { _ in },
            attemptRecovery: { recoveryCalled = true }
        )

        // Give any potential Task a chance to run (it shouldn't)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!recoveryCalled, "attemptRecovery should NOT be called for exit code 0")
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
