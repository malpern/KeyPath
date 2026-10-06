@testable import KeyPathInstallationWizard
import XCTest
import KeyPathWizardCore

@MainActor
final class WizardAsyncOperationManagerTests: XCTestCase {
    func testCompletedCheckIsRetiredBeforeSuspendingSuccessCallback() async {
        let manager = WizardAsyncOperationManager()
        let entered = expectation(description: "Follow-up callback entered")
        let finished = expectation(description: "Follow-up callback finished")
        let gate = AsyncStream<Void>.makeStream()
        manager.execute(operation: AsyncOperation(id: "state_detection", name: "Check") { _ in true }) { _ in
            entered.fulfill()
            for await _ in gate.stream { break }
            finished.fulfill()
        }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertFalse(manager.hasRunningOperations)
        XCTAssertFalse(manager.isRunning("state_detection"))
        gate.continuation.finish()
        await fulfillment(of: [finished], timeout: 2)
    }

    func testOldCompletionCannotRetireReplacementWithSameID() async {
        let manager = WizardAsyncOperationManager()
        let replacementStarted = expectation(description: "Replacement started")
        let oldCallbackFinished = expectation(description: "Old callback finished")
        let replacementFinished = expectation(description: "Replacement finished")
        let gate = AsyncStream<Void>.makeStream()
        manager.execute(operation: AsyncOperation(id: "state_detection", name: "First") { _ in true }) { _ in
            manager.execute(operation: AsyncOperation(id: "state_detection", name: "Replacement") { _ in
                replacementStarted.fulfill()
                for await _ in gate.stream { break }
                return true
            }) { _ in replacementFinished.fulfill() }
            oldCallbackFinished.fulfill()
        }
        await fulfillment(of: [replacementStarted, oldCallbackFinished], timeout: 2)
        XCTAssertTrue(manager.isRunning("state_detection"))
        gate.continuation.finish()
        await fulfillment(of: [replacementFinished], timeout: 2)
        XCTAssertFalse(manager.hasRunningOperations)
    }
    func testDeadlineRetiresCheckBeforeNonCooperativeWorkReturns() async {
        let manager = WizardAsyncOperationManager()
        let started = expectation(description: "Started")
        let timedOut = expectation(description: "Deadline delivered")
        let returned = expectation(description: "Late work returned")
        var release: CheckedContinuation<Bool, Never>?
        manager.execute(operation: AsyncOperation(id: "check", name: "Check") { _ in
            let value = await withCheckedContinuation { release = $0; started.fulfill() }
            returned.fulfill()
            return value
        }, timeout: 0.05) { _ in
            XCTFail("Timed-out work must not succeed later")
        } onFailure: { _ in timedOut.fulfill() }
        await fulfillment(of: [started, timedOut], timeout: 2)
        XCTAssertFalse(manager.hasRunningOperations)
        XCTAssertNotNil(manager.lastError)
        release?.resume(returning: true)
        await fulfillment(of: [returned], timeout: 2)
    }

    func testCancelledCheckDoesNotDeliverLateCompletion() async {
        let manager = WizardAsyncOperationManager()
        let started = expectation(description: "Started")
        let returned = expectation(description: "Returned")
        var release: CheckedContinuation<Bool, Never>?
        manager.execute(operation: AsyncOperation(id: "check", name: "Check") { _ in
            let value = await withCheckedContinuation { release = $0; started.fulfill() }
            returned.fulfill()
            return value
        }) { _ in XCTFail("Cancelled success") } onFailure: { _ in XCTFail("Cancelled failure") }
        await fulfillment(of: [started], timeout: 2)
        manager.cancelAllOperations()
        XCTAssertFalse(manager.hasRunningOperations)
        release?.resume(returning: true)
        await fulfillment(of: [returned], timeout: 2)
    }

    func testSupersededDetectionCannotOverwriteNewSnapshot() async {
        let machine = WizardStateMachine()
        let manager = WizardAsyncOperationManager()
        let started = expectation(description: "Old inspection started")
        let applied = expectation(description: "New inspection applied")
        let returned = expectation(description: "Old inspection returned")
        var release: CheckedContinuation<SystemStateResult, Never>?
        machine.stateDetector = {
            let result = await withCheckedContinuation { release = $0; started.fulfill() }
            returned.fulfill()
            return result
        }
        manager.execute(operation: WizardOperations.stateDetection(stateMachine: machine)) { result in
            XCTFail("Superseded callback")
            machine.updateWizardState(from: result)
        }
        await fulfillment(of: [started], timeout: 2)
        machine.stateDetector = { SystemStateResult(state: .active, issues: [], autoFixActions: [], detectionTimestamp: Date()) }
        manager.execute(operation: WizardOperations.stateDetection(stateMachine: machine)) { result in
            machine.updateWizardState(from: result)
            applied.fulfill()
        }
        await fulfillment(of: [applied], timeout: 2)
        release?.resume(returning: SystemStateResult(state: .serviceNotRunning, issues: [], autoFixActions: [], detectionTimestamp: Date()))
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(machine.wizardState, .active)
        XCTAssertEqual(machine.stateVersion, 1)
    }

    func testFailureIsDeliveredAfterBusyStateClears() async {
        enum TestError: Error { case failed }
        let manager = WizardAsyncOperationManager()
        let failed = expectation(description: "Failure handled")
        manager.execute(operation: AsyncOperation<Bool>(id: "check", name: "Check") { _ in
            throw TestError.failed
        }) { _ in XCTFail("Unexpected success") } onFailure: { _ in
            XCTAssertFalse(manager.hasRunningOperations)
            XCTAssertNotNil(manager.lastError)
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 2)
    }

    func testDelayedRetryCannotStartAfterANewerRefreshRequest() {
        let view = InstallationWizardView()
        let oldRequest = UUID()
        view.stateMachine.inspectionRequestID = UUID()
        view.performStateDetection(previousPage: .communication, attempt: 1,
                                   showSpinner: true, requestID: oldRequest)
        XCTAssertFalse(view.asyncOperationManager.hasRunningOperations)
        XCTAssertEqual(view.stateMachine.stateVersion, 0)
    }

}
