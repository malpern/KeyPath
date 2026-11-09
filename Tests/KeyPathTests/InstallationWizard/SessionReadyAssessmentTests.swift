@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

final class SessionReadyAssessmentTests: KeyPathTestCase {
    @MainActor
    func testReadySessionProducesHealthyAssessmentWithoutHelperRecipe() {
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

        XCTAssertEqual(decision.assessment, .sessionRuntimeReady)
        XCTAssertTrue(decision.matrixActions.isEmpty)
        XCTAssertTrue(decision.autoFixActions.isEmpty)
    }
}
