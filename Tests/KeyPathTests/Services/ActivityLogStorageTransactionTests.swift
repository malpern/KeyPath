import Foundation
@testable import KeyPathInsights
import XCTest

final class ActivityLogStorageTransactionTests: XCTestCase, @unchecked Sendable {
    private func event() -> ActivityEvent {
        ActivityEvent(type: .appSwitch, payload: .app(AppEventData(
            bundleIdentifier: "test.app", appName: "Test", isLaunch: false
        )))
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testAppendPreservesUnreadableHistoryAndThrows() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ActivityLogStorage(
            baseDirectory: directory, encrypt: { $0 },
            decrypt: { _ in throw TestFailure.unreadable }, deleteKey: {}
        )
        try await storage.append([event()])
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: file)
        do {
            try await storage.append([event()])
            XCTFail("An unreadable existing log must not be replaced")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testAppendPreservesInvalidUTF8History() async throws {
        try await assertMalformedHistoryPreserved(Data([0xFF, 0xFE]))
    }

    func testAppendPreservesHistoryContainingInvalidJSONLine() async throws {
        try await assertMalformedHistoryPreserved(Data("{not JSON}\n".utf8))
    }

    private func assertMalformedHistoryPreserved(_ corruption: Data) async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ActivityLogStorage(
            baseDirectory: directory, encrypt: { $0 }, decrypt: { $0 }, deleteKey: {}
        )
        try await storage.append([event()])
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        // Retain a valid event alongside the bad line, proving partial decoding
        // cannot authorize rewriting only the surviving subset of history.
        var original = try Data(contentsOf: file)
        original.append(Data("\n".utf8))
        original.append(corruption)
        try original.write(to: file)
        do {
            try await storage.append([event()])
            XCTFail("Malformed history must be preserved for recovery")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testConcurrentAppendsPreserveBothBatches() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = EncryptionGate()
        let requested = expectation(description: "Both mutations entered storage")
        requested.expectedFulfillmentCount = 2
        let storage = ActivityLogStorage(
            baseDirectory: directory, encrypt: { await gate.encrypt($0) },
            decrypt: { $0 }, deleteKey: {}, mutationRequested: { requested.fulfill() }
        )
        let first = event(), second = event()
        let firstTask = Task { try await storage.append([first]) }
        await gate.waitUntilBlocked()
        let secondTask = Task { try await storage.append([second]) }
        await fulfillment(of: [requested], timeout: 2)
        await gate.release()
        try await firstTask.value
        try await secondTask.value
        let events = try await storage.readAllEvents()
        XCTAssertEqual(Set(events.map(\.id)), Set([first.id, second.id]))
    }

    func testResetWaitsForPendingAppendAndLeavesNoHistory() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = EncryptionGate()
        let requested = expectation(description: "Append and reset entered storage")
        requested.expectedFulfillmentCount = 2
        let storage = ActivityLogStorage(
            baseDirectory: directory, encrypt: { await gate.encrypt($0) },
            decrypt: { $0 }, deleteKey: {}, mutationRequested: { requested.fulfill() }
        )
        let value = event()
        let append = Task { try await storage.append([value]) }
        await gate.waitUntilBlocked()
        let reset = Task { try await storage.clearAll() }
        await fulfillment(of: [requested], timeout: 2)
        await gate.release()
        try await append.value
        try await reset.value
        let hasLogs = await storage.hasLogs()
        XCTAssertFalse(hasLogs, "An append already in flight must not resurrect reset data")
    }
}

private enum TestFailure: Error { case unreadable }

private actor EncryptionGate {
    private var blocked = false
    private var didBlock = false
    private var first = true
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func encrypt(_ data: Data) async -> Data {
        if first {
            first = false
            blocked = true
            didBlock = true
            for waiter in blockedWaiters {
                waiter.resume()
            }
            blockedWaiters.removeAll()
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return data
    }

    func waitUntilBlocked() async {
        if didBlock { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release() {
        guard blocked else { return }
        blocked = false
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
