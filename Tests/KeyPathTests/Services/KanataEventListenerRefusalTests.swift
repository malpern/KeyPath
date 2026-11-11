import Darwin
@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

/// A refused engine connection must never crash the app. Network can report
/// `.failed` after `.ready` for one connection; resuming the readiness
/// continuation twice traps (seen 2026-11-11 when the engine refused the app).
final class KanataEventListenerRefusalTests: XCTestCase {
    func testResumeOnceResumesOnlyTheFirstTime() async throws {
        var once: ResumeOnce<Int>?
        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let guardian = ResumeOnce(continuation)
            once = guardian
            XCTAssertTrue(guardian.resume(with: .success(7)))
            XCTAssertFalse(guardian.resume(with: .failure(CancellationError())), "a second resume is ignored")
        }
        XCTAssertEqual(value, 7)
        XCTAssertFalse(once?.resume(with: .success(8)) ?? true)
    }

    /// An engine socket that refuses every peer the way the peer check does:
    /// accept, then shut the connection down before sending a byte. The
    /// listener must keep retrying, not crash.
    func testListenerSurvivesAnEngineSocketThatRefusesEveryPeer() async throws {
        let dir = "/tmp/kp-refuse-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/e.sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try RuntimeControl.makeAddress(path)
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(listen(fd, 16), 0)
        let accepted = Counter()
        let refusedThree = expectation(description: "three refused connections")
        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                if accepted.increment() == 3 { refusedThree.fulfill() }
                shutdown(client, SHUT_RDWR)
                close(client)
            }
        }

        let saved = EngineControlEndpoint.socketPath
        EngineControlEndpoint.publish(path)
        defer { EngineControlEndpoint.publish(saved) }
        let listener = KanataEventListener()
        await listener.start(endpoint: .session, onLayerChange: { _ in })
        await fulfillment(of: [refusedThree], timeout: 10)
        await listener.stop()
        close(fd)
        XCTAssertGreaterThanOrEqual(accepted.value, 3, "the listener kept reconnecting after refusals")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.withLock { count }
    }

    /// Returns the new count.
    @discardableResult
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
