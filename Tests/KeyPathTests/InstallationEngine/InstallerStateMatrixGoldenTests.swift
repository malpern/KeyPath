@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

final class InstallerStateMatrixGoldenTests: XCTestCase {
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

    private struct GoldenCase {
        let name: String
        let snapshot: InstallerStateMatrixSnapshot
        let expectedRow: InstallerStateMatrixRow
        let expectedPlan: [InstallerStateMatrixAction]
    }

    private var goldenCases: [GoldenCase] {
        [
            GoldenCase(
                name: "Fresh install, missing components",
                snapshot: InstallerStateMatrixSnapshot(kanataBinaryPresent: false),
                expectedRow: .freshInstallMissingComponents,
                expectedPlan: [.installMissingComponents]
            ),
            GoldenCase(
                name: "Kanata not registered",
                snapshot: InstallerStateMatrixSnapshot(smAppServiceRegistered: false),
                expectedRow: .kanataNotRegistered,
                expectedPlan: [.installOrRegisterRuntimeServices]
            ),
            GoldenCase(
                name: "Registered but not loaded",
                snapshot: InstallerStateMatrixSnapshot(launchdJobLoaded: false),
                expectedRow: .registeredButNotLoaded,
                expectedPlan: [.recoverRuntimeRegistrationBypassingThrottle]
            ),
            GoldenCase(
                name: "Loaded but not running",
                snapshot: InstallerStateMatrixSnapshot(kanataProcessRunning: false, kanataTCPResponding: false),
                expectedRow: .loadedButNotRunning,
                expectedPlan: [.installRequiredRuntimeServices]
            ),
            GoldenCase(
                name: "Running but TCP not responding",
                snapshot: InstallerStateMatrixSnapshot(kanataTCPResponding: false),
                expectedRow: .runningButTCPNotResponding,
                expectedPlan: [.restartOrRecoverKanataRuntime]
            ),
            GoldenCase(
                name: "Running and TCP responding",
                snapshot: InstallerStateMatrixSnapshot(),
                expectedRow: .runningAndTCPResponding,
                expectedPlan: []
            ),
            GoldenCase(
                name: "Running but input capture failing",
                snapshot: InstallerStateMatrixSnapshot(currentInputCaptureIssue: true),
                expectedRow: .runningButInputCaptureFailing,
                expectedPlan: [.repairVHIDActivationServices]
            ),
            GoldenCase(
                name: "Stale/non-approval input-capture issue with Kanata stopped",
                snapshot: InstallerStateMatrixSnapshot(
                    kanataProcessRunning: false,
                    kanataTCPResponding: false,
                    staleInputCaptureIssue: true
                ),
                expectedRow: .staleInputCaptureIssueWithKanataStopped,
                expectedPlan: [.installRequiredRuntimeServices]
            ),
            GoldenCase(
                name: "DriverKit approval pending with Kanata stopped",
                snapshot: InstallerStateMatrixSnapshot(
                    kanataProcessRunning: false,
                    kanataTCPResponding: false,
                    driverKitApprovalPending: true
                ),
                expectedRow: .driverKitApprovalPendingWithKanataStopped,
                expectedPlan: [.surfaceDriverKitApproval]
            ),
            GoldenCase(
                name: "VirtualHID driver payload missing",
                snapshot: InstallerStateMatrixSnapshot(virtualHIDPayloadPresent: false),
                expectedRow: .virtualHIDDriverPayloadMissing,
                expectedPlan: [.installVirtualHIDPayload]
            ),
            GoldenCase(
                name: "VHID services missing/unhealthy",
                snapshot: InstallerStateMatrixSnapshot(virtualHIDServicesHealthy: false),
                expectedRow: .vhidServicesMissingUnhealthy,
                expectedPlan: [.repairVHIDServices]
            ),
            GoldenCase(
                name: "VirtualHID approval pending",
                snapshot: InstallerStateMatrixSnapshot(virtualHIDApprovalPending: true),
                expectedRow: .virtualHIDApprovalPending,
                expectedPlan: [.surfaceVirtualHIDApproval]
            ),
            GoldenCase(
                name: "Helper missing",
                snapshot: InstallerStateMatrixSnapshot(helperInstalled: false, helperResponding: false, helperFresh: false),
                expectedRow: .helperMissing,
                expectedPlan: [.installHelper]
            ),
            GoldenCase(
                name: "Helper responds but may be stale",
                snapshot: InstallerStateMatrixSnapshot(helperFresh: false),
                expectedRow: .helperRespondsButMayBeStale,
                expectedPlan: [.verifyOrRefreshHelper]
            ),
            GoldenCase(
                name: "Helper path succeeds",
                snapshot: InstallerStateMatrixSnapshot(helperPathReportedSuccess: true),
                expectedRow: .helperPathSucceeds,
                expectedPlan: [.verifyPostconditions]
            ),
            GoldenCase(
                name: "Sudo fallback succeeds",
                snapshot: InstallerStateMatrixSnapshot(sudoFallbackReportedSuccess: true),
                expectedRow: .sudoFallbackSucceeds,
                expectedPlan: [.verifyPostconditions]
            ),
            GoldenCase(
                name: "Manual approval is required",
                snapshot: InstallerStateMatrixSnapshot(manualApprovalRequired: true),
                expectedRow: .manualApprovalRequired,
                expectedPlan: [.surfaceManualApproval]
            ),
            GoldenCase(
                name: "Definitive unhealthy state",
                snapshot: InstallerStateMatrixSnapshot(definitiveUnhealthyState: true),
                expectedRow: .definitiveUnhealthyState,
                expectedPlan: [.failWithDiagnostics]
            )
        ]
    }
}
