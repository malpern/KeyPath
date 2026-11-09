@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class AppSessionProbeTests: XCTestCase {
    private func response(
        state: RuntimeControl.State, ready: Bool, issues: [RuntimeControl.Issue] = []
    ) -> RuntimeControl.Response {
        var response = RuntimeControl.Response(
            ok: true, operation: .doctor, state: state, workerPID: state == .running ? 42 : nil,
            failure: nil, lastError: nil, layer: nil, appPID: 1, appVersion: "test"
        )
        response.ready = ready
        response.issues = issues
        return response
    }

    private func issue(_ category: String) -> RuntimeControl.Issue {
        .init(title: "t", category: category, fix: "f", needsUser: false, settingsURL: nil)
    }

    func testNoAnswerReadsAsNotRunning() {
        XCTAssertEqual(AppSessionProbe.evidence(from: nil), .none)
    }

    func testRunningAndReadyHasKeyAccess() {
        let evidence = AppSessionProbe.evidence(from: response(state: .running, ready: true))
        XCTAssertEqual(evidence, .init(runtimeRunning: true, runtimeKeyAccess: true))
    }

    /// A conflict makes the app not ready, but the runtime is still running.
    func testRunningButNotReadyForAnotherReasonStaysRunning() {
        let evidence = AppSessionProbe.evidence(from: response(state: .running, ready: false, issues: [issue("conflict")]))
        XCTAssertEqual(evidence, .init(runtimeRunning: true, runtimeKeyAccess: true))
    }

    func testPermissionProblemLeavesKeyAccessUnverified() {
        let evidence = AppSessionProbe.evidence(from: response(state: .running, ready: false, issues: [issue("permissions")]))
        XCTAssertEqual(evidence, .init(runtimeRunning: true, runtimeKeyAccess: false))
    }

    func testStoppedRuntimeIsNotRunning() {
        XCTAssertEqual(AppSessionProbe.evidence(from: response(state: .stopped, ready: false)), .none)
        XCTAssertEqual(AppSessionProbe.evidence(from: response(state: .starting, ready: false)), .none)
    }

    func testProbeNeverAsksALiveAppUnderTests() {
        XCTAssertEqual(AppSessionProbe.current(), .none)
    }
}
