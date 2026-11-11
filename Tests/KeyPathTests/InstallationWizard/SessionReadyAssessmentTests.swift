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
            kanataProcessRunning: true,
            kanataTCPResponding: true,
            componentsInstalled: true
        ).build()
        XCTAssertEqual(context.installerStateMatrixRow, .sessionRuntimeReady)
        XCTAssertTrue(context.installerStateMatrixPlan.isEmpty)
        XCTAssertTrue(InstallerEngine.actions(for: .repair, context: context).isEmpty)
    }
}
