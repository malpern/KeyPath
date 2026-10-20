import Foundation
@testable import KeyPathInsights
import XCTest

@MainActor
final class ActivityLoggerDisableTests: XCTestCase {
    func testDisableRejectsNewEventsWhileFinalFlushIsSuspended() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = DisableFlushGate()
        let storage = ActivityLogStorage(
            baseDirectory: directory,
            encrypt: { await gate.encrypt($0) }, decrypt: { $0 }, deleteKey: {}
        )
        let logger = ActivityLogger(storage: storage, automaticallyCaptureEvents: false)
        await logger.enable()
        logger.recordAppSwitch(bundleIdentifier: "test.before", appName: "Before")
        let disable = Task { await logger.disable() }
        await gate.waitUntilBlocked()

        // Model callbacks already queued when observers were removed, plus a
        // direct action dispatch while encryption keeps disable suspended.
        let disabledBeforeFlushCompletes = !logger.isEnabled
        logger.recordAppSwitch(bundleIdentifier: "test.after", appName: "After")
        logger.recordAppLaunch(bundleIdentifier: "test.after", appName: "After")
        logger.recordKeyPathAction(action: "launch", target: "After", uri: "keypath://launch/After")
        let countDuringFlush = logger.eventCount
        await gate.release()
        await disable.value
        // A subsequent flush must not persist any post-disable event left in memory.
        await logger.flush()
        let events = try await storage.readAllEvents()

        XCTAssertTrue(disabledBeforeFlushCompletes, "Disabling must revoke capture before awaiting storage")
        XCTAssertEqual(countDuringFlush, 1)
        XCTAssertEqual(events.count, 1, "Activity recorded after opt-out must never reach storage")
        XCTAssertFalse(logger.isEnabled)
    }
}

private actor DisableFlushGate {
    private var entered = false
    private var first = true
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func encrypt(_ data: Data) async -> Data {
        if first {
            first = false
            entered = true
            blockedWaiters.forEach { $0.resume() }
            blockedWaiters.removeAll()
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return data
    }

    func waitUntilBlocked() async {
        if entered { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
