@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

final class InstallerStateMatrixGoldenTests: XCTestCase {
    func testStateMatrixMarkdownRowsMatchClassifierRows() throws {
        let documentedRows = try documentedStateMatrixRows()
        let classifierRows = InstallerStateMatrixRow.allCases.map(\.rawValue)

        XCTAssertEqual(
            documentedRows,
            classifierRows,
            """
            docs/process/installer-repair-state-matrix.md is the source-of-truth \
            state matrix. Keep the markdown table and InstallerStateMatrixRow \
            in the same order so the golden suite pins the documented contract.
            """
        )
    }

    func testEveryDocumentedStateMatrixRowHasAGoldenFixture() {
        XCTAssertEqual(
            Set(goldenCases.map(\.expectedRow)),
            Set(InstallerStateMatrixRow.allCases),
            "Every row in docs/process/installer-repair-state-matrix.md must have one golden fixture"
        )
    }

    func testClassifySnapshotAndPlanMatchStateMatrixGoldenFixtures() {
        for goldenCase in goldenCases {
            let actualRow = InstallerStateMatrixPlanner.classify(goldenCase.snapshot)
            let actualPlan = InstallerStateMatrixPlanner.plan(for: actualRow)

            XCTAssertEqual(actualRow, goldenCase.expectedRow, goldenCase.name)
            XCTAssertEqual(actualPlan, goldenCase.expectedPlan, goldenCase.name)
        }
    }

    func testVirtualHIDApprovalPendingOutranksRetryableLiveInputCaptureRepair() {
        let snapshot = matrixSnapshot(
            currentInputCaptureIssue: true,
            virtualHIDApprovalPending: true
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .virtualHIDApprovalPending)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.surfaceVirtualHIDApproval])
    }

    func testHelperInstalledButUnresponsiveDoesNotFallThroughHealthy() {
        let snapshot = matrixSnapshot(
            helperInstalled: true,
            helperResponding: false,
            helperFresh: true
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .helperMissing)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.installHelper])
    }

    func testReadyRuntimeOutranksGenericManualApprovalRequired() {
        let snapshot = matrixSnapshot(manualApprovalRequired: true)

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .runningAndTCPResponding)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [])
    }

    func testStoppedRuntimeWithManualApprovalRemainsTerminalManualAction() {
        let snapshot = matrixSnapshot(
            kanataProcessRunning: false,
            kanataTCPResponding: false,
            manualApprovalRequired: true
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .manualApprovalRequired)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.surfaceManualApproval])
    }

    func testUnknownRegistrationEvidenceDoesNotDefaultHealthy() {
        let snapshot = matrixSnapshot(smAppServiceRegistered: .unknown)

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .kanataNotRegistered)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.installOrRegisterRuntimeServices])
    }

    func testUnknownRuntimeProcessEvidenceDoesNotDefaultHealthy() {
        let snapshot = matrixSnapshot(kanataProcessRunning: .unknown)

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .loadedButNotRunning)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.installRequiredRuntimeServices])
    }

    func testUnknownVirtualHIDPayloadEvidenceDoesNotDefaultHealthy() {
        let snapshot = matrixSnapshot(virtualHIDPayloadPresent: .unknown)

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .virtualHIDDriverPayloadMissing)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.installVirtualHIDPayload])
    }

    private struct GoldenCase {
        let name: String
        let snapshot: InstallerStateMatrixSnapshot
        let expectedRow: InstallerStateMatrixRow
        let expectedPlan: [InstallerStateMatrixAction]
    }

    private func matrixSnapshot(
        kanataBinaryPresent: Evidence<Bool> = .present,
        requiredRuntimePayloadPresent: Evidence<Bool> = .present,
        smAppServiceRegistered: Evidence<Bool> = .present,
        launchdJobLoaded: Evidence<Bool> = .present,
        kanataProcessRunning: Evidence<Bool> = .present,
        kanataTCPResponding: Evidence<Bool> = .present,
        currentInputCaptureIssue: Evidence<Bool> = .absent,
        staleInputCaptureIssue: Evidence<Bool> = .absent,
        driverKitApprovalPending: Evidence<Bool> = .absent,
        virtualHIDDriverPresent: Evidence<Bool> = .present,
        virtualHIDPayloadPresent: Evidence<Bool> = .present,
        virtualHIDServicesHealthy: Evidence<Bool> = .present,
        virtualHIDApprovalPending: Evidence<Bool> = .absent,
        helperInstalled: Evidence<Bool> = .present,
        helperResponding: Evidence<Bool> = .present,
        helperFresh: Evidence<Bool> = .present,
        helperPathReportedSuccess: Evidence<Bool> = .absent,
        sudoFallbackReportedSuccess: Evidence<Bool> = .absent,
        manualApprovalRequired: Evidence<Bool> = .absent,
        definitiveUnhealthyState: Evidence<Bool> = .absent
    ) -> InstallerStateMatrixSnapshot {
        InstallerStateMatrixSnapshot(
            kanataBinaryPresent: kanataBinaryPresent,
            requiredRuntimePayloadPresent: requiredRuntimePayloadPresent,
            smAppServiceRegistered: smAppServiceRegistered,
            launchdJobLoaded: launchdJobLoaded,
            kanataProcessRunning: kanataProcessRunning,
            kanataTCPResponding: kanataTCPResponding,
            currentInputCaptureIssue: currentInputCaptureIssue,
            staleInputCaptureIssue: staleInputCaptureIssue,
            driverKitApprovalPending: driverKitApprovalPending,
            virtualHIDDriverPresent: virtualHIDDriverPresent,
            virtualHIDPayloadPresent: virtualHIDPayloadPresent,
            virtualHIDServicesHealthy: virtualHIDServicesHealthy,
            virtualHIDApprovalPending: virtualHIDApprovalPending,
            helperInstalled: helperInstalled,
            helperResponding: helperResponding,
            helperFresh: helperFresh,
            helperPathReportedSuccess: helperPathReportedSuccess,
            sudoFallbackReportedSuccess: sudoFallbackReportedSuccess,
            manualApprovalRequired: manualApprovalRequired,
            definitiveUnhealthyState: definitiveUnhealthyState
        )
    }

    private func documentedStateMatrixRows() throws -> [String] {
        let docURL = repositoryRoot()
            .appendingPathComponent("docs/process/installer-repair-state-matrix.md")
        let contents = try String(contentsOf: docURL, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)

        guard let headerIndex = lines.firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespaces) == "| State | Typical Evidence | Planner Should | Success Postcondition | Test Requirement |"
        }) else {
            XCTFail("Could not find state-matrix table header in \(docURL.path)")
            return []
        }

        return lines.dropFirst(headerIndex + 2).prefix { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
        }.compactMap { line in
            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 2, !columns[1].isEmpty else { return nil }
            return columns[1]
        }
    }

    private func repositoryRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // InstallationEngine
            .deletingLastPathComponent() // KeyPathTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    private var goldenCases: [GoldenCase] {
        [
            GoldenCase(
                name: "Fresh install, missing components",
                snapshot: matrixSnapshot(kanataBinaryPresent: false),
                expectedRow: .freshInstallMissingComponents,
                expectedPlan: [.installMissingComponents]
            ),
            GoldenCase(
                name: "Kanata not registered",
                snapshot: matrixSnapshot(smAppServiceRegistered: false),
                expectedRow: .kanataNotRegistered,
                expectedPlan: [.installOrRegisterRuntimeServices]
            ),
            GoldenCase(
                name: "Registered but not loaded",
                snapshot: matrixSnapshot(launchdJobLoaded: false),
                expectedRow: .registeredButNotLoaded,
                expectedPlan: [.recoverRuntimeRegistrationBypassingThrottle]
            ),
            GoldenCase(
                name: "Loaded but not running",
                snapshot: matrixSnapshot(kanataProcessRunning: false, kanataTCPResponding: false),
                expectedRow: .loadedButNotRunning,
                expectedPlan: [.installRequiredRuntimeServices]
            ),
            GoldenCase(
                name: "Running but TCP not responding",
                snapshot: matrixSnapshot(kanataTCPResponding: false),
                expectedRow: .runningButTCPNotResponding,
                expectedPlan: [.restartOrRecoverKanataRuntime]
            ),
            GoldenCase(
                name: "Running and TCP responding",
                snapshot: matrixSnapshot(),
                expectedRow: .runningAndTCPResponding,
                expectedPlan: []
            ),
            GoldenCase(
                name: "Running but input capture failing",
                snapshot: matrixSnapshot(currentInputCaptureIssue: true),
                expectedRow: .runningButInputCaptureFailing,
                expectedPlan: [.repairVHIDActivationServices]
            ),
            GoldenCase(
                name: "Stale/non-approval input-capture issue with Kanata stopped",
                snapshot: matrixSnapshot(
                    kanataProcessRunning: false,
                    kanataTCPResponding: false,
                    staleInputCaptureIssue: true
                ),
                expectedRow: .staleInputCaptureIssueWithKanataStopped,
                expectedPlan: [.installRequiredRuntimeServices]
            ),
            GoldenCase(
                name: "DriverKit approval pending with Kanata stopped",
                snapshot: matrixSnapshot(
                    kanataProcessRunning: false,
                    kanataTCPResponding: false,
                    driverKitApprovalPending: true
                ),
                expectedRow: .driverKitApprovalPendingWithKanataStopped,
                expectedPlan: [.surfaceDriverKitApproval]
            ),
            GoldenCase(
                name: "VirtualHID driver payload missing",
                snapshot: matrixSnapshot(virtualHIDPayloadPresent: false),
                expectedRow: .virtualHIDDriverPayloadMissing,
                expectedPlan: [.installVirtualHIDPayload]
            ),
            GoldenCase(
                name: "VHID services missing/unhealthy",
                snapshot: matrixSnapshot(virtualHIDServicesHealthy: false),
                expectedRow: .vhidServicesMissingUnhealthy,
                expectedPlan: [.repairVHIDServices]
            ),
            GoldenCase(
                name: "VirtualHID approval pending",
                snapshot: matrixSnapshot(virtualHIDApprovalPending: true),
                expectedRow: .virtualHIDApprovalPending,
                expectedPlan: [.surfaceVirtualHIDApproval]
            ),
            GoldenCase(
                name: "Helper missing",
                snapshot: matrixSnapshot(helperInstalled: false, helperResponding: false, helperFresh: false),
                expectedRow: .helperMissing,
                expectedPlan: [.installHelper]
            ),
            GoldenCase(
                name: "Helper responds but may be stale",
                snapshot: matrixSnapshot(helperFresh: false),
                expectedRow: .helperRespondsButMayBeStale,
                expectedPlan: [.verifyOrRefreshHelper]
            ),
            GoldenCase(
                name: "Helper path succeeds",
                snapshot: matrixSnapshot(helperPathReportedSuccess: true),
                expectedRow: .helperPathSucceeds,
                expectedPlan: [.verifyPostconditions]
            ),
            GoldenCase(
                name: "Sudo fallback succeeds",
                snapshot: matrixSnapshot(sudoFallbackReportedSuccess: true),
                expectedRow: .sudoFallbackSucceeds,
                expectedPlan: [.verifyPostconditions]
            ),
            GoldenCase(
                name: "Manual approval is required",
                snapshot: matrixSnapshot(
                    kanataProcessRunning: false,
                    kanataTCPResponding: false,
                    manualApprovalRequired: true
                ),
                expectedRow: .manualApprovalRequired,
                expectedPlan: [.surfaceManualApproval]
            ),
            GoldenCase(
                name: "Definitive unhealthy state",
                snapshot: matrixSnapshot(definitiveUnhealthyState: true),
                expectedRow: .definitiveUnhealthyState,
                expectedPlan: [.failWithDiagnostics]
            )
        ]
    }
}
