import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// The 2026-11-03 regression: a cancelled wait skipped the signal, so the
/// probe outlived the app. Every abandoned wait must signal the probe.
@MainActor
final class SessionCapabilityProbeWaitTests: XCTestCase {
    private struct Cancelled: Error {}

    private func report() -> SessionRuntimeReport {
        SessionRuntimeReport(nonce: "probe", pid: 123, uid: 502, state: .capabilities,
                             accessibility: true, effectiveInputAccess: true, tapActive: false,
                             tcpPort: 0, inputCount: 0, outputCount: 0)
    }

    func testCancelledWaitSignalsTheProbe() async {
        var abandoned = 0
        do {
            _ = try await ServiceLifecycleCoordinator.awaitCapabilityReport(
                read: { nil }, sleep: { throw Cancelled() }, abandon: { abandoned += 1 }
            )
            XCTFail("The cancellation must propagate")
        } catch {}
        XCTAssertEqual(abandoned, 1)
    }

    func testTimeoutSignalsTheProbeOnce() async throws {
        var abandoned = 0
        var reads = 0
        let result = try await ServiceLifecycleCoordinator.awaitCapabilityReport(
            attempts: 3, read: { reads += 1; return nil }, sleep: {}, abandon: { abandoned += 1 }
        )
        XCTAssertNil(result)
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(abandoned, 1)
    }

    /// A probe that reported exits on its own and is not signalled.
    func testReportedProbeIsNotSignalled() async throws {
        var reads = 0
        let result = try await ServiceLifecycleCoordinator.awaitCapabilityReport(
            read: { reads += 1; return reads == 2 ? self.report() : nil }, sleep: {},
            abandon: { XCTFail("A reported probe must not be signalled") }
        )
        XCTAssertEqual(result?.nonce, "probe")
    }
}
