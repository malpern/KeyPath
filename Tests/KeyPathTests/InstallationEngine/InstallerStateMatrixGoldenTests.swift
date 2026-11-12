import KeyPathCore
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

    func testUnknownRuntimeEvidenceDoesNotDefaultHealthy() {
        XCTAssertEqual(
            InstallerStateMatrixPlanner.classify(matrixSnapshot(kanataProcessRunning: .unknown)),
            .sessionRuntimeStopped
        )
        XCTAssertEqual(
            InstallerStateMatrixPlanner.classify(matrixSnapshot(kanataTCPResponding: .unknown)),
            .sessionRuntimeStopped
        )
        XCTAssertEqual(
            InstallerStateMatrixPlanner.classify(matrixSnapshot(kanataBinaryPresent: .unknown)),
            .sessionRuntimeStopped
        )
        XCTAssertEqual(
            InstallerStateMatrixPlanner.classify(matrixSnapshot(captureComplete: false)),
            .sessionRuntimeStopped,
            "An incomplete capture is never a ready runtime"
        )
    }

    func testSessionTCPWithoutVerifiedCaptureOrPayloadIsNotReady() {
        XCTAssertEqual(InstallerStateMatrixPlanner.classify(matrixSnapshot(
            sessionInputCaptureReady: .unknown
        )), .sessionRuntimeStopped)
        XCTAssertEqual(InstallerStateMatrixPlanner.classify(matrixSnapshot(
            requiredRuntimePayloadPresent: false
        )), .sessionRuntimeStopped)
    }

    private struct GoldenCase {
        let name: String
        let snapshot: InstallerStateMatrixSnapshot
        let expectedRow: InstallerStateMatrixRow
        let expectedPlan: [InstallerStateMatrixAction]
    }

    private func matrixSnapshot(
        captureComplete: Evidence<Bool> = .present,
        sessionInputCaptureReady: Evidence<Bool> = .present,
        kanataBinaryPresent: Evidence<Bool> = .present,
        requiredRuntimePayloadPresent: Evidence<Bool> = .present,
        kanataProcessRunning: Evidence<Bool> = .present,
        kanataTCPResponding: Evidence<Bool> = .present
    ) -> InstallerStateMatrixSnapshot {
        InstallerStateMatrixSnapshot(
            captureComplete: captureComplete,
            sessionInputCaptureReady: sessionInputCaptureReady,
            kanataBinaryPresent: kanataBinaryPresent,
            requiredRuntimePayloadPresent: requiredRuntimePayloadPresent,
            kanataProcessRunning: kanataProcessRunning,
            kanataTCPResponding: kanataTCPResponding
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
                name: "Session runtime stopped or not ready",
                snapshot: matrixSnapshot(kanataProcessRunning: false, kanataTCPResponding: false),
                expectedRow: .sessionRuntimeStopped,
                expectedPlan: [.restartOrRecoverKanataRuntime]
            ),
            GoldenCase(
                name: "Session tap active and engine responding",
                snapshot: matrixSnapshot(),
                expectedRow: .sessionRuntimeReady,
                expectedPlan: []
            ),
        ]
    }
}
