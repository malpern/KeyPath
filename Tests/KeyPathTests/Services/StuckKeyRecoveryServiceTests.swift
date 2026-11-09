@testable import KeyPathAppKit
import XCTest

@MainActor
final class StuckKeyRecoveryServiceTests: KeyPathTestCase {
    private var service: StuckKeyRecoveryService!
    private var incidentCallCount = 0
    private var lastIncident: StuckKeyRecoveryService.StuckKeyIncident?
    /// Fulfilled each time the incident callback runs, so positive tests can wait for
    /// the diagnostic snapshot to complete before asserting on the surfaced incident.
    private var incidentExpectation: XCTestExpectation?

    override func setUp() async throws {
        try await super.setUp()
        service = StuckKeyRecoveryService()
        incidentCallCount = 0
        lastIncident = nil
        incidentExpectation = nil
        service.onIncidentDetected = { [weak self] incident in
            self?.incidentCallCount += 1
            self?.lastIncident = incident
            self?.incidentExpectation?.fulfill()
        }
    }

    // MARK: - Detection Threshold

    func testIgnoresNormalAutorepeat() {
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 100
        )

        service.handleAutorepeatMismatch(correlation)

        XCTAssertEqual(incidentCallCount, 0, "Should not surface an incident for normal autorepeat with active kanata")
    }

    func testIgnoresNonAutorepeat() {
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: false,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)

        XCTAssertEqual(incidentCallCount, 0, "Should not surface an incident if not an unmatched autorepeat")
    }

    func testSurfacesIncidentForStuckKey() async {
        let expectation = expectation(description: "incident surfaced for stuck key")
        incidentExpectation = expectation

        let correlation = makeCorrelation(
            key: "t",
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(incidentCallCount, 1)
        XCTAssertEqual(lastIncident?.key, "t")
        XCTAssertEqual(lastIncident?.keyCode, 17)
        XCTAssertEqual(lastIncident?.msSinceAnyKanataEvent, 5000)
    }

    func testIgnoresHeldKeysWhileTheRuntimeIsNotRemapping() {
        service.runtimeIsRemapping = { false }
        let correlation = makeCorrelation(
            key: "delete",
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 1_400_646
        )

        service.handleAutorepeatMismatch(correlation)

        XCTAssertEqual(incidentCallCount, 0, "A held key is ordinary autorepeat when no runtime intercepts keys")
    }

    func testStillSurfacesIncidentWhileTheRuntimeIsRemapping() async {
        let expectation = expectation(description: "incident surfaced while remapping")
        incidentExpectation = expectation
        service.runtimeIsRemapping = { true }

        service.handleAutorepeatMismatch(makeCorrelation(
            key: "t",
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        ))
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(incidentCallCount, 1)
    }

    func testIgnoresNilKanataEventTime() {
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: nil
        )

        service.handleAutorepeatMismatch(correlation)

        XCTAssertEqual(incidentCallCount, 0, "Should not surface an incident if kanata event time is unknown")
    }

    // MARK: - Debouncing

    func testDebouncesPreviousIncidents() async {
        let firstIncident = expectation(description: "first incident")
        incidentExpectation = firstIncident

        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        await fulfillment(of: [firstIncident], timeout: 5.0)
        XCTAssertEqual(incidentCallCount, 1)

        // Give the first capture Task time to settle, then fire a second mismatch. It is
        // suppressed either by the in-flight guard (if the Task tail hasn't run) or by the
        // 30s cooldown (once lastIncidentAt is set) — either way no second incident fires.
        incidentExpectation = nil
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        service.handleAutorepeatMismatch(correlation)
        XCTAssertEqual(incidentCallCount, 1, "Should not surface another incident within cooldown period")
    }

    func testDoesNotDoubleFireImmediateDuplicateIncident() async {
        let firstIncident = expectation(description: "first incident")
        incidentExpectation = firstIncident

        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        // Immediate duplicate mismatches should not fan out into multiple user-facing
        // incidents while the first diagnostic capture is in flight.
        service.handleAutorepeatMismatch(correlation)
        service.handleAutorepeatMismatch(correlation)
        await fulfillment(of: [firstIncident], timeout: 5.0)

        XCTAssertEqual(incidentCallCount, 1, "Should not surface duplicate incidents while capture is in progress")
    }

    // MARK: - Diagnostic Snapshot Isolation

    func testDiagnosticSnapshotsRedirectToTempDirectoryDuringTests() {
        let dir = StuckKeyRecoveryService.diagnosticsDirectory
        let realDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KeyPath/stuck-key-incidents")

        XCTAssertNotEqual(
            dir.standardizedFileURL.path, realDir.standardizedFileURL.path,
            "Test runs must not write into the real incident directory — the prune-to-20 pass would delete genuine stuck-key evidence"
        )
        XCTAssertTrue(
            dir.standardizedFileURL.path.hasPrefix(
                FileManager.default.temporaryDirectory.standardizedFileURL.path
            ),
            "Test snapshots should land in the temp directory, got \(dir.standardizedFileURL.path)"
        )
    }

    // MARK: - Capture Helpers

    func testSystemLoadLinesSkipProcessListingInTests() async {
        let lines = await StuckKeyRecoveryService.systemLoadLines()

        XCTAssertTrue(
            lines.first?.hasPrefix("loadavg_1m_5m_15m: ") == true,
            "Load average should always be captured (libc call, safe in tests)"
        )
        XCTAssertTrue(lines.contains("top_cpu_processes:"))
        XCTAssertTrue(
            lines.contains("  (skipped in tests)"),
            "Process listing must not shell out under tests"
        )
    }

    // MARK: - Helpers

    private func makeCorrelation(
        key: String = "t",
        suggestsUnmatchedAutorepeat: Bool,
        msSinceAnyKanataEvent: Int?
    ) -> InvestigationSystemEventCorrelation {
        InvestigationSystemEventCorrelation(
            key: key,
            keyCode: 17,
            eventType: "keyDown",
            isAutorepeat: suggestsUnmatchedAutorepeat,
            flagsRawValue: 0,
            sourcePID: nil,
            observedAt: Date(),
            previousKanataAction: .press,
            previousKanataSessionID: 1,
            sameKeyGapMs: 33,
            msSinceAnyKanataEvent: msSinceAnyKanataEvent,
            suggestsUnmatchedAutorepeat: suggestsUnmatchedAutorepeat
        )
    }
}
