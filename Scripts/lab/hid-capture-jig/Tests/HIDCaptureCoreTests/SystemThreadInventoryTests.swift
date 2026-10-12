@testable import HIDCaptureCore
import XCTest

final class SystemThreadInventoryTests: XCTestCase {
    func testCollectionFailureTimeoutAndMalformedOutputRefuse() {
        XCTAssertNil(SystemThreadInventory.readSystemInventory(executable: "/usr/bin/false", arguments: []))
        XCTAssertNil(SystemThreadInventory.readSystemInventory(executable: "/bin/echo", arguments: ["kern.num_taskthreads: 4096"]))
        let start = Date()
        XCTAssertNil(SystemThreadInventory.readSystemInventory(executable: "/bin/sleep", arguments: ["5"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertEqual(SystemThreadInventory.readSystemInventory(executable: "/bin/echo", arguments: ["Processes: 250 total, 1645 threads"]), 1645)
    }

    func testProductionCollectorReadsLiveInventory() {
        let inventory = SystemThreadInventory()
        XCTAssertEqual(inventory.sample(), -1)
        let ready = expectation(description: "system top inventory")
        DispatchQueue.global().async {
            for _ in 0..<300 {
                if inventory.sample() > 0 { ready.fulfill(); return }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        wait(for: [ready], timeout: 4)
    }

    func testParsesMeasuredInventoryNotKernelLimit() {
        XCTAssertEqual(SystemThreadInventory.parse("Processes: 250 total, 2 running, 248 sleeping, 1742 threads \nCPU usage: 10%"), 1742)
        for invalid in ["", "kern.num_taskthreads: 4096", "Processes: 250 total, 0 threads", "Processes: truncated", "Processes: 1 total, -1 threads"] {
            XCTAssertNil(SystemThreadInventory.parse(invalid))
        }
    }

    func testSuccessfulInventoryExpiresWithoutReusingItForever() {
        final class Clock: @unchecked Sendable {
            let lock = NSLock()
            var value: UInt64 = 1
            var reads = 0
            func firstRead() -> Bool { lock.lock(); defer { lock.unlock() }; reads += 1; return reads == 1 }
            func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
            func advance() { lock.lock(); value = 4_000_000_002; lock.unlock() }
        }
        let clock = Clock()
        let blockFurtherReads = DispatchSemaphore(value: 0)
        let inventory = SystemThreadInventory(collect: {
            let first = clock.firstRead()
            if !first { blockFurtherReads.wait() }
            return first ? 1645 : nil
        }, now: { clock.read() })
        defer { blockFurtherReads.signal() }
        XCTAssertEqual(inventory.sample(), -1)
        let ready = expectation(description: "background inventory completes")
        DispatchQueue.global().async {
            for _ in 0..<100 {
                if inventory.sample() == 1645 { ready.fulfill(); return }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        wait(for: [ready], timeout: 2)
        clock.advance()
        XCTAssertEqual(inventory.sample(), -1)
    }

    func testPendingAndFailedInventoryRemainUnavailable() {
        let started = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        let inventory = SystemThreadInventory(collect: {
            started.signal()
            finish.wait()
            return nil
        }, now: { 1 })
        XCTAssertEqual(inventory.sample(), -1)
        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(inventory.sample(), -1)
        XCTAssertEqual(started.wait(timeout: .now() + 0.05), .timedOut)
        finish.signal()
    }
}
