import XCTest
@testable import KeyPathAppKit
import KeyPathWizardCore
import KeyPathCore

@MainActor
final class WizardAutoFixerFacadeTests: XCTestCase {
    func testPerformAutoFixDelegatesToInstallerEngine() async {
        let mockEngine = MockInstallerEngine()
        let fixer = WizardAutoFixer(
            kanataManager: RuntimeCoordinator(),
            installerEngine: mockEngine
        )

        let success = await fixer.performAutoFix(.installBundledKanata)

        XCTAssertTrue(success)
        XCTAssertEqual(mockEngine.actions, [.installBundledKanata])
    }
}

// MARK: - Test Doubles

@MainActor
private final class MockInstallerEngine: WizardInstallerEngineProtocol {
    private(set) var actions: [AutoFixAction] = []

    func runSingleAction(_ action: AutoFixAction, using _: PrivilegeBroker) async -> InstallerReport {
        actions.append(action)
        return InstallerReport(success: true, failureReason: nil, executedRecipes: [], logs: [])
    }
}
