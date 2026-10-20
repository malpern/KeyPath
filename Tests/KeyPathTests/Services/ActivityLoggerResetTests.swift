import Foundation
@testable import KeyPathInsights
import XCTest

@MainActor
final class ActivityLoggerResetTests: XCTestCase {
    func testResetInvalidatesHistoryReadStartedDuringItsFinalFlush() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encryption = ResetPauseGate()
        let decryption = ResetPauseGate()
        let storage = ActivityLogStorage(
            baseDirectory: directory,
            encrypt: { await encryption.pass($0) },
            decrypt: { await decryption.pass($0) }, deleteKey: {}
        )
        let historical = ActivityEvent(type: .appSwitch, payload: .app(AppEventData(
            bundleIdentifier: "test.history", appName: "History", isLaunch: false
        )))
        try await storage.append([historical])
        let logger = ActivityLogger(storage: storage, automaticallyCaptureEvents: false)
        await logger.enable()
        logger.recordAppSwitch(bundleIdentifier: "test.before", appName: "Before")

        await encryption.arm()
        let reset = Task { try await logger.resetData() }
        await encryption.waitUntilBlocked()
        // A later enable is allowed, but its historical snapshot must not undo reset.
        await decryption.arm()
        let enable = Task { await logger.enable() }
        await decryption.waitUntilBlocked()
        await encryption.release()
        try await reset.value
        await decryption.release()
        await enable.value

        XCTAssertTrue(logger.isEnabled, "The newer explicit enable remains authoritative")
        XCTAssertEqual(logger.eventCount, 0, "A pre-reset history snapshot must not resurrect the count")
        let cleared = try await storage.readAllEvents()
        XCTAssertTrue(cleared.isEmpty)
        logger.recordAppLaunch(bundleIdentifier: "test.after", appName: "After")
        XCTAssertEqual(logger.eventCount, 1)
        await logger.disable()
        let final = try await storage.readAllEvents()
        XCTAssertEqual(final.count, 1)
    }
}

private actor ResetPauseGate {
    private var armed = false
    private var entered = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm() {
        armed = true
    }

    func pass(_ data: Data) async -> Data {
        if armed {
            armed = false
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
