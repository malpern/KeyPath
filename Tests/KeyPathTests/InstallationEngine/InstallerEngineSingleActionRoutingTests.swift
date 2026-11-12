@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import XCTest

/// The wizard "Start"/"Fix" buttons, Settings "Fix it", the CLI and RuntimeControl
/// all reach the session runtime through these two single actions.
@MainActor
final class InstallerEngineSingleActionRoutingTests: KeyPathAsyncTestCase {
    private var previousRuntime: (any RuntimeCoordinating)?

    override func setUp() async throws {
        try await super.setUp()
        previousRuntime = WizardDependencies.runtimeCoordinator
    }

    override func tearDown() async throws {
        WizardDependencies.runtimeCoordinator = previousRuntime
        try await super.tearDown()
    }

    private func engine(finalContext: SystemContext) -> InstallerEngine {
        InstallerEngine(
            systemValidator: StubSystemValidator(context: finalContext)
        )
    }

    func testStartActionRunsSessionStartRecipe() async {
        let runtime = SessionStartStub(startSucceeds: true)
        WizardDependencies.runtimeCoordinator = runtime
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()

        let report = await engine(finalContext: ready).runSingleAction(.startSessionRuntime)

        XCTAssertTrue(report.success, report.failureReason ?? "")
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), [InstallerRecipeID.startSessionRuntime])
        XCTAssertEqual(runtime.starts, 1)
    }

    func testStartActionFailsWhenSessionRuntimeDoesNotStart() async {
        let runtime = SessionStartStub(startSucceeds: false)
        WizardDependencies.runtimeCoordinator = runtime
        let stopped = SystemContextBuilder.cleanInstall()

        let report = await engine(finalContext: stopped).runSingleAction(.startSessionRuntime)

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), [InstallerRecipeID.startSessionRuntime])
        XCTAssertEqual(report.executedRecipes.first?.success, false)
        XCTAssertEqual(runtime.starts, 1)
    }
}

@MainActor
private final class SessionStartStub: RuntimeCoordinating {
    let startSucceeds: Bool
    var starts = 0
    var lastError: String?

    init(startSucceeds: Bool) {
        self.startSucceeds = startSucceeds
    }

    func startKanata(reason _: String) async -> Bool {
        starts += 1
        return startSucceeds
    }

    func stopKanata(reason _: String) async -> Bool {
        true
    }

    func restartKanata(reason _: String) async -> Bool {
        true
    }

    func updateStatus() async {}
    func currentRuntimeStatus() async -> RuntimeStatus {
        .stopped
    }

    func isInTransientRuntimeStartupWindow() async -> Bool {
        false
    }

    func openAccessibilitySettings() {}
}
