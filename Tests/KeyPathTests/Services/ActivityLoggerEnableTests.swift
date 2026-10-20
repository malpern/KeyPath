import Foundation
@testable import KeyPathInsights
import XCTest

@MainActor
final class ActivityLoggerEnableTests: XCTestCase {
    func testEnableCountsEventsAcceptedDuringHistoryRead() async throws {
        try await checkHistoryReadOverlap(flushDuringRead: false)
    }

    func testEnableCountsEventsFlushedDuringHistoryReadExactlyOnce() async throws {
        try await checkHistoryReadOverlap(flushDuringRead: true)
    }

    private func checkHistoryReadOverlap(flushDuringRead: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = HistoryReadGate()
        let storage = ActivityLogStorage(
            baseDirectory: directory, encrypt: { $0 },
            decrypt: { await gate.decrypt($0) }, deleteKey: {}
        )
        try await storage.append([historicalEvent()])
        let logger = ActivityLogger(storage: storage, automaticallyCaptureEvents: false)
        let enable = Task { await logger.enable() }
        await gate.waitUntilBlocked()
        logger.recordAppSwitch(bundleIdentifier: "test.during", appName: "During")
        if flushDuringRead { await logger.flush() }
        await gate.release()
        await enable.value
        let countAfterEnable = logger.eventCount
        await logger.disable()
        let events = try await storage.readAllEvents()

        XCTAssertEqual(countAfterEnable, 2, "History completion must preserve events accepted while it was suspended")
        XCTAssertEqual(events.count, 2)
    }

    func testSupersededEnableCannotOverwriteNewerEnableState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = HistoryReadGate()
        let storage = ActivityLogStorage(
            baseDirectory: directory, encrypt: { $0 },
            decrypt: { await gate.decrypt($0) }, deleteKey: {}
        )
        try await storage.append([historicalEvent()])
        let logger = ActivityLogger(storage: storage, automaticallyCaptureEvents: false)
        let originalEnable = Task { await logger.enable() }
        await gate.waitUntilBlocked()
        logger.recordAppSwitch(bundleIdentifier: "test.first", appName: "First")
        await logger.disable()
        await logger.enable()
        logger.recordAppLaunch(bundleIdentifier: "test.newer", appName: "Newer")
        await gate.release()
        await originalEnable.value
        let countAfterStaleCompletion = logger.eventCount
        let latestEnablePreserved = logger.isEnabled
        await logger.disable()
        let events = try await storage.readAllEvents()

        XCTAssertTrue(latestEnablePreserved)
        XCTAssertEqual(countAfterStaleCompletion, 3, "A stale history read must not overwrite a newer enable")
        XCTAssertEqual(events.count, 3)
    }

    private func historicalEvent() -> ActivityEvent {
        ActivityEvent(type: .appSwitch, payload: .app(AppEventData(
            bundleIdentifier: "test.history", appName: "History", isLaunch: false
        )))
    }
}

private actor HistoryReadGate {
    private var entered = false
    private var first = true
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func decrypt(_ data: Data) async -> Data {
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
