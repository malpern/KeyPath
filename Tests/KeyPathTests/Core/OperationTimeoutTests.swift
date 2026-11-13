import KeyPathCore
import os.lock
@preconcurrency import XCTest

@MainActor
final class OperationTimeoutTests: XCTestCase {
    func testReturnsValueAndPropagatesOperationError() async throws {
        enum ProbeError: Error { case failed }

        let result = try await withTimeout(.seconds(5), cancellation: .returnImmediately) { 42 }
        XCTAssertEqual(result, 42)

        do {
            _ = try await withTimeout(.seconds(5), cancellation: .returnImmediately) {
                throw ProbeError.failed
            }
            XCTFail("Expected the operation's error")
        } catch ProbeError.failed {}
    }

    func testMutationRetainsOwnershipUntilCancelledWorkFinishes() async {
        let cancelled = expectation(description: "Deadline cancelled the mutation")
        let completedEarly = expectation(description: "Timeout returned before cleanup")
        completedEarly.isInverted = true
        let cleanup = AsyncStream<Void>.makeStream()
        let cleanedUp = OSAllocatedUnfairLock(initialState: false)

        let call = Task {
            do {
                try await withTimeout(.milliseconds(50), cancellation: .waitForOperation) {
                    // A separate task simulates cleanup that must finish even after cancellation.
                    let finishCleanup = Task {
                        for await _ in cleanup.stream {}
                    }
                    await withTaskCancellationHandler {
                        await finishCleanup.value
                    } onCancel: {
                        cancelled.fulfill()
                    }
                }
                XCTFail("Expected a timeout")
            } catch is OperationTimeoutError {
                if !cleanedUp.withLock({ $0 }) { completedEarly.fulfill() }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        await fulfillment(of: [cancelled], timeout: 2)
        await fulfillment(of: [completedEarly], timeout: 0.1)
        cleanedUp.withLock { $0 = true }
        cleanup.continuation.finish()
        await call.value
    }

    func testAlreadyCancelledCallDoesNotStartOperation() async {
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await withTimeout(.seconds(5), cancellation: .returnImmediately) {
                    XCTFail("Cancelled call started its operation")
                }
                XCTFail("Expected cancellation")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        await task.value
    }
}
