@testable import KeyPathAppKit
import KeyPathCore
import KeyPathDaemonLifecycle
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
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: StubSystemValidator(context: finalContext)
        )
    }

    func testStartActionRunsSessionStartRecipe() async {
        let runtime = SessionStartStub(startSucceeds: true)
        WizardDependencies.runtimeCoordinator = runtime
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()

        let report = await engine(finalContext: ready).runSingleAction(.restartCommServer)

        XCTAssertTrue(report.success, report.failureReason ?? "")
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), [InstallerRecipeID.startSessionRuntime])
        XCTAssertEqual(runtime.starts, 1)
    }

    func testStartActionFailsWhenSessionRuntimeDoesNotStart() async {
        let runtime = SessionStartStub(startSucceeds: false)
        WizardDependencies.runtimeCoordinator = runtime
        let stopped = SystemContextBuilder.cleanInstall()

        let report = await engine(finalContext: stopped).runSingleAction(.restartCommServer)

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), [InstallerRecipeID.startSessionRuntime])
        XCTAssertEqual(report.executedRecipes.first?.success, false)
        XCTAssertEqual(runtime.starts, 1)
    }

    func testSynchronizeConfigPathsRunsConfigCheckRecipe() async throws {
        let runtime = SessionStartStub(startSucceeds: true)
        WizardDependencies.runtimeCoordinator = runtime
        let restore = try ensureUserConfig(present: true)
        defer { restore() }
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()

        let report = await engine(finalContext: ready).runSingleAction(.synchronizeConfigPaths)

        XCTAssertTrue(report.success, report.failureReason ?? "")
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), [InstallerRecipeID.synchronizeConfigPaths])
        XCTAssertEqual(runtime.starts, 0, "The config check must not start the runtime")
    }

    func testSynchronizeConfigPathsFailsWithoutUserConfig() async throws {
        WizardDependencies.runtimeCoordinator = SessionStartStub(startSucceeds: true)
        let restore = try ensureUserConfig(present: false)
        defer { restore() }
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()

        let report = await engine(finalContext: ready).runSingleAction(.synchronizeConfigPaths)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("User configuration is missing") ?? false)
    }

    /// Puts the sandboxed user config into the requested state and returns a restore closure.
    private func ensureUserConfig(present: Bool) throws -> () -> Void {
        let fm = FileManager.default
        let path = KeyPathConstants.Config.mainConfigPath
        let backup = path + ".single-action-test-backup"
        let existed = fm.fileExists(atPath: path)
        if existed { try? fm.removeItem(atPath: backup); try fm.copyItem(atPath: path, toPath: backup) }
        if present {
            try fm.createDirectory(atPath: KeyPathConstants.Config.directory, withIntermediateDirectories: true)
            if !existed { try "(defsrc)\n(deflayer base)\n".write(toFile: path, atomically: true, encoding: .utf8) }
        } else if existed {
            try fm.removeItem(atPath: path)
        }
        return {
            try? fm.removeItem(atPath: path)
            if existed { try? fm.moveItem(atPath: backup, toPath: path) }
        }
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
    func currentRuntimeStatus() async -> WizardRuntimeStatus {
        .stopped
    }

    func isInTransientRuntimeStartupWindow() async -> Bool {
        false
    }

    func openAccessibilitySettings() {}
}
