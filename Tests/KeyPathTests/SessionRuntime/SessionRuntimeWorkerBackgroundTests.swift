import Foundation
@testable import KeyPathAppKit
import XCTest

@MainActor
final class SessionRuntimeWorkerBackgroundTests: XCTestCase {
    private enum Failure: Error, Equatable { case expected }

    func testHIDWorkRunsOffMainThreadAndReturnsItsResult() throws {
        XCTAssertTrue(Thread.isMainThread)
        let result = try SessionRuntimeWorker.performHIDWork {
            (Thread.isMainThread, 42)
        }
        XCTAssertFalse(result.0)
        XCTAssertEqual(result.1, 42)
    }

    func testHIDWorkPropagatesFailureAfterJoining() {
        XCTAssertThrowsError(try SessionRuntimeWorker.performHIDWork { () -> Int in
            throw Failure.expected
        }) {
            XCTAssertEqual($0 as? Failure, .expected)
        }
    }

    func testBackgroundRunLoopCannotDeliverQueuedMainShutdown() throws {
        let shutdown = Flag()
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            shutdown.mark()
        }
        defer {
            // Drain our callback after the join, so it cannot outlive this test.
            CFRunLoopRunInMode(.defaultMode, 0, false)
        }
        let deliveredDuringWork = try SessionRuntimeWorker.performHIDWork {
            // Model a child join that services the calling thread's run loop.
            // With global.sync this can service the main shutdown callback.
            CFRunLoopRunInMode(.defaultMode, 0, false)
            return shutdown.value
        }
        XCTAssertFalse(deliveredDuringWork)
        XCTAssertFalse(shutdown.value, "The caller's join must not service its main run loop")
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var marked = false

        var value: Bool {
            lock.lock()
            defer { lock.unlock() }
            return marked
        }

        func mark() {
            lock.lock()
            defer { lock.unlock() }
            marked = true
        }
    }
}
