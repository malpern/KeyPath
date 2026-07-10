import KeyPathCore
@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

final class HelperVersionContractTests: KeyPathTestCase {
    func testAllHelperVersionConsumersUseSharedContract() throws {
        XCTAssertEqual(HelperManager.expectedHelperVersion, KeyPathHelperContract.version)
        XCTAssertEqual(WizardHelperConstants.expectedHelperVersion, KeyPathHelperContract.version)

        let infoURL = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathHelper/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, KeyPathHelperContract.version)

        let contractConsumers = [
            "Sources/KeyPathHelper/HelperService.swift",
            "Sources/KeyPathHelper/main.swift",
            "Sources/KeyPathAppKit/Core/HelperManager.swift",
            "Sources/KeyPathWizardCore/WizardHelperManaging.swift",
            "Sources/KeyPathInstallationWizard/UI/Pages/WizardHelperPage.swift",
        ]
        for relativePath in contractConsumers {
            let source = try String(
                contentsOf: repositoryRoot().appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertTrue(
                source.contains("KeyPathHelperContract.version"),
                "\(relativePath) must use the shared helper version contract"
            )
        }
    }

    @MainActor
    func testHealthyHelperVersionProducesHealthyAssessmentAndEmptyPlan() {
        let context = SystemContextBuilder(
            servicesHealthy: true,
            kanataLaunchdLoaded: true,
            kanataProcessRunning: true,
            kanataTCPResponding: true,
            kanataSMAppServiceRegistered: true,
            loginItemsApprovalRequired: false,
            componentsInstalled: true
        ).build()
        let decision = InstallerDecisionPipeline.decide(for: .repair, context: context)

        XCTAssertEqual(decision.assessment, .runningAndTCPResponding)
        XCTAssertTrue(decision.matrixActions.isEmpty)
        XCTAssertTrue(decision.autoFixActions.isEmpty)
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
