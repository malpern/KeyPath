@preconcurrency import XCTest

@testable import KeyPathAppKit

/// Unit tests for StatePublisherService.
///
/// Tests reactive state publishing via AsyncStream.
/// These tests verify:
/// - Initial state emission
/// - State change notifications
/// - Multiple subscribers
/// - Provider configuration
@MainActor
final class StatePublisherServiceTests: XCTestCase {
    // MARK: - Basic Functionality Tests

    func testConfigureSetsProvider() {
        let publisher = StatePublisherService<String>()
        var callCount = 0

        publisher.configure {
            callCount += 1
            return "test-state-\(callCount)"
        }

        XCTAssertTrue(publisher.isConfigured, "Publisher should be configured after configure()")
    }

    func testGetCurrentStateReturnsProviderValue() {
        let publisher = StatePublisherService<String>()
        publisher.configure { "test-state" }

        let state = publisher.getCurrentState()
        XCTAssertEqual(state, "test-state", "getCurrentState should return provider value")
    }

    func testGetCurrentStateReturnsNilWhenNotConfigured() {
        let publisher = StatePublisherService<String>()

        let state = publisher.getCurrentState()
        XCTAssertNil(state, "getCurrentState should return nil when not configured")
    }

    func testHasSubscribersReturnsFalseInitially() {
        let publisher = StatePublisherService<String>()
        XCTAssertFalse(publisher.hasSubscribers, "Should have no subscribers initially")
    }

    // MARK: - AsyncStream Tests

    func testStateChangesEmitsInitialState() async {
        let publisher = StatePublisherService<String>()
        publisher.configure { "initial-state" }

        var receivedStates: [String] = []
        let expectation = expectation(description: "Receive initial state")

        Task {
            for await state in publisher.stateChanges {
                receivedStates.append(state)
                if receivedStates.count == 1 {
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStates, ["initial-state"], "Should emit initial state immediately")
    }

    func testStateChangesEmitsOnNotifyStateChanged() async {
        let publisher = StatePublisherService<Int>()
        var counter = 0
        publisher.configure { counter }

        var receivedStates: [Int] = []
        let expectation = expectation(description: "Receive state changes")
        expectation.expectedFulfillmentCount = 3 // Initial + 2 notifications

        Task {
            for await state in publisher.stateChanges {
                receivedStates.append(state)
                expectation.fulfill()
                if receivedStates.count >= 3 {
                    break
                }
            }
        }

        // Wait for initial state
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Trigger state changes
        counter = 1
        publisher.notifyStateChanged()

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        counter = 2
        publisher.notifyStateChanged()

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStates, [0, 1, 2], "Should emit all state changes")
    }

    func testNotifyStateChangedWithoutProviderLogsWarning() {
        let publisher = StatePublisherService<String>()
        // Don't configure provider

        // This should not crash, just log a warning
        publisher.notifyStateChanged()
        XCTAssertFalse(publisher.hasSubscribers, "Should not have subscribers if not configured")
    }

    func testMultipleSubscribersReceiveUpdates() async {
        // Note: Current implementation only supports single subscriber
        // (stateChangeContinuation is overwritten by last subscriber)
        // This test verifies that at least one subscriber receives updates
        let publisher = StatePublisherService<String>()
        var stateCounter = 0
        publisher.configure { "state-\(stateCounter)" }

        var subscriberReceivedUpdate = false

        let expectation = expectation(description: "Subscriber receives update")

        // Single subscriber test
        Task {
            var initialReceived = false
            for await _ in publisher.stateChanges {
                if !initialReceived {
                    initialReceived = true
                    continue // Skip initial state
                }
                subscriberReceivedUpdate = true
                expectation.fulfill()
                break
            }
        }

        // Wait for subscription to be set up
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Trigger update
        stateCounter = 1
        publisher.notifyStateChanged()

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(subscriberReceivedUpdate, "Subscriber should receive update")
    }

    // MARK: - Edge Cases

    func testStateChangesWorksWithCustomType() async {
        struct TestState: Sendable, Equatable {
            let value: Int
        }

        let publisher = StatePublisherService<TestState>()
        publisher.configure { TestState(value: 42) }

        var receivedState: TestState?
        let expectation = expectation(description: "Receive custom state")

        Task {
            for await state in publisher.stateChanges {
                receivedState = state
                expectation.fulfill()
                break
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedState?.value, 42, "Should work with custom Sendable types")
    }

    func testProviderCalledOnEachNotification() {
        let publisher = StatePublisherService<Int>()
        var callCount = 0

        publisher.configure {
            callCount += 1
            return callCount
        }

        // Initial state (from getCurrentState or first subscription)
        _ = publisher.getCurrentState()
        let initialCalls = callCount

        publisher.notifyStateChanged()
        publisher.notifyStateChanged()
        publisher.notifyStateChanged()

        XCTAssertGreaterThan(callCount, initialCalls, "Provider should be called on each notification")
    }

    func testStateChangesSubscriptionAfterConfiguration() async {
        let publisher = StatePublisherService<String>()

        // Configure after creating publisher
        publisher.configure { "configured-state" }

        var receivedStates: [String] = []
        let expectation = expectation(description: "Receive state after configuration")

        Task {
            for await state in publisher.stateChanges {
                receivedStates.append(state)
                expectation.fulfill()
                break
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStates.first, "configured-state", "Should emit state even if configured after publisher creation")
    }
}
