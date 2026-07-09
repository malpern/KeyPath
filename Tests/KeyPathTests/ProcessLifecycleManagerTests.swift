@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathDaemonLifecycle
@preconcurrency import XCTest

@MainActor
final class ProcessLifecycleManagerTests: XCTestCase {
    func testIntentSetting() {
        let manager = ProcessLifecycleManager()

        // Test setting intent to running
        manager.setIntent(.shouldBeRunning(source: "test"))

        // Test setting intent to stopped
        manager.setIntent(.shouldBeStopped)

        // No crashes or issues setting intents
        XCTAssertTrue(true, "Intent setting should work without issues")
    }

    func testReconcileWithIntent() async {
        let manager = ProcessLifecycleManager()

        // Test reconcile with running intent
        manager.setIntent(.shouldBeRunning(source: "test"))

        do {
            try await manager.reconcileWithIntent()
            XCTAssertTrue(true, "Reconcile with running intent should not throw")
        } catch {
            XCTFail("Reconcile should not throw: \(error)")
        }

        // Test reconcile with stopped intent
        manager.setIntent(.shouldBeStopped)

        do {
            try await manager.reconcileWithIntent()
            XCTAssertTrue(true, "Reconcile with stopped intent should not throw")
        } catch {
            XCTFail("Reconcile should not throw: \(error)")
        }
    }

    func testProcessIntentEnumValues() {
        // Test that ProcessIntent enum works correctly
        let runningIntent = ProcessLifecycleManager.ProcessIntent.shouldBeRunning(source: "test")
        let stoppedIntent = ProcessLifecycleManager.ProcessIntent.shouldBeStopped

        // Basic validation that enum cases can be created
        switch runningIntent {
        case let .shouldBeRunning(source):
            XCTAssertEqual(source, "test", "Source should match")
        case .shouldBeStopped:
            XCTFail("Should be running intent")
        }

        switch stoppedIntent {
        case .shouldBeRunning:
            XCTFail("Should be stopped intent")
        case .shouldBeStopped:
            XCTAssertTrue(true, "Correct stopped intent")
        }
    }

    func testDetectKanataProcessesUsesInjectedSystemStateProvider() async throws {
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configureRunResult { executable, args in
            if executable == "/usr/bin/pgrep", args == ["-fl", "kanata"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: """
                    123 kanata --cfg /Users/example/.config/keypath/keypath.kbd
                    456 pgrep -fl kanata
                    789 /Applications/Visual Studio Code.app/Contents/MacOS/Electron kanata extension

                    """,
                    stderr: "",
                    duration: 0.01
                )
            }
            return ProcessResult(exitCode: 1, stdout: "", stderr: "", duration: 0.01)
        }

        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let manager = ProcessLifecycleManager(systemStateProvider: provider)

        let processes = try await manager.detectKanataProcesses()
        let commands = await runner.executedCommands

        XCTAssertEqual(processes.map(\.pid), [123])
        XCTAssertEqual(processes.first?.command, "kanata --cfg /Users/example/.config/keypath/keypath.kbd")
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-fl", "kanata"] },
            "ProcessLifecycleManager should use the injected provider for kanata process discovery"
        )
    }

    func testProcessLifecycleErrors() {
        // Test that error enum cases can be created (migrated to KeyPathError)
        let noManagerError = KeyPathError.process(.noManager)
        let startFailedError = KeyPathError.process(.startFailed(reason: "test"))
        let stopFailedError = KeyPathError.process(.stopFailed(underlyingError: "test error 1"))
        let terminateFailedError = KeyPathError.process(
            .terminateFailed(underlyingError: "test error 2")
        )

        XCTAssertNotNil(noManagerError)
        XCTAssertNotNil(startFailedError)
        XCTAssertNotNil(stopFailedError)
        XCTAssertNotNil(terminateFailedError)
    }
}
