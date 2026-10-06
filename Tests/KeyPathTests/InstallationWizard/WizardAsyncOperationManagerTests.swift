@testable import KeyPathInstallationWizard
import XCTest

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
}
