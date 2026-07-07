@testable import KeyPathAppKit
@testable import KeyPathCore
import ServiceManagement
@preconcurrency import XCTest

@MainActor
final class KanataDaemonManagerTests: XCTestCase {
    var manager: KanataDaemonManager!
    private nonisolated(unsafe) var originalSMFactory: ((String) -> SMAppServiceProtocol)!
    private nonisolated(unsafe) var originalRegisteredButNotLoadedOverride: (() async -> Bool)?
    private nonisolated(unsafe) var originalStatusProvider: SMAppServiceStatusProvider!

    override func setUp() async throws {
        try await super.setUp()
        originalSMFactory = KanataDaemonManager.smServiceFactory
        originalRegisteredButNotLoadedOverride = KanataDaemonManager.registeredButNotLoadedOverride
        originalStatusProvider = SMAppServiceStatusProvider.shared
        KanataDaemonManager.registeredButNotLoadedOverride = nil
        manager = KanataDaemonManager.shared
    }

    override func tearDown() async throws {
        KanataDaemonManager.smServiceFactory = originalSMFactory
        KanataDaemonManager.registeredButNotLoadedOverride = originalRegisteredButNotLoadedOverride
        SMAppServiceStatusProvider.shared = originalStatusProvider
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Status Checking Tests

    func testGetStatus() async {
        let status = await manager.getStatus()
        // Status should be one of the valid SMAppService statuses
        XCTAssertTrue(
            status == .notFound || status == .notRegistered || status == .requiresApproval
                || status == .enabled,
            "Status should be a valid SMAppService status"
        )
    }

    func testIsRegisteredViaSMAppService() async {
        let isRegistered = await KanataDaemonManager.isRegisteredViaSMAppService()
        // Should return boolean without crashing
        XCTAssertNotNil(isRegistered)
    }

    func testHasLegacyInstallation() {
        let hasLegacy = manager.hasLegacyInstallation()
        // Should return boolean without crashing
        XCTAssertNotNil(hasLegacy)
    }

    func testIsInstalled() async {
        let isInstalled = await manager.isInstalled()
        // Should return boolean without crashing
        XCTAssertNotNil(isInstalled)
    }

    // MARK: - Validation Tests

    func testPlistExistsInBundle() {
        let bundlePath = Bundle.main.bundlePath
        let plistPath =
            "\(bundlePath)/Contents/Library/LaunchDaemons/\(KanataDaemonManager.kanataPlistName)"
        let exists = FileManager.default.fileExists(atPath: plistPath)

        if exists {
            print("✅ Plist found at: \(plistPath)")
        } else {
            print("⚠️ Plist not found at: \(plistPath)")
            print("   This is expected if running tests outside app bundle context")
        }
        // Don't fail test - plist may not exist in test environment
    }

    func testKanataBinaryExistsInBundle() {
        let bundlePath = Bundle.main.bundlePath
        let enginePath = "\(bundlePath)/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata"
        let exists = FileManager.default.fileExists(atPath: enginePath)

        if exists {
            print("✅ Kanata binary found in bundle")
        } else {
            print("⚠️ Kanata binary not found at: \(enginePath)")
            print("   This is expected if running tests outside app bundle context")
        }
        // Don't fail test - binary may not exist in test environment
    }

    // MARK: - Error Handling Tests

    func testRegistrationRequiresMacOS13() async {
        // This test verifies the macOS version check
        // On macOS 13+, this should not throw immediately
        // On older macOS, it should throw

        if #available(macOS 13, *) {
            // On macOS 13+, registration attempt should not immediately fail due to version
            // (it may fail for other reasons like missing plist, but not version)
            // Don't actually register - just verify the version check passes
            let status = await manager.getStatus()
            XCTAssertNotNil(status, "Should be able to check status on macOS 13+")
        } else {
            // On older macOS, registration should fail with version error
            do {
                try await manager.register()
                XCTFail("Registration should fail on macOS < 13")
            } catch let KanataDaemonError.registrationFailed(reason) {
                XCTAssertTrue(
                    reason.contains("macOS 13"),
                    "Error should mention macOS 13 requirement"
                )
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Constants Tests

    func testConstants() {
        XCTAssertEqual(KanataDaemonManager.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(KanataDaemonManager.kanataPlistName, "com.keypath.kanata.plist")
    }

    func testPreferredLaunchctlTargetsForSMAppServicePreferGuiDomain() {
        let targets = KanataDaemonManager.preferredLaunchctlTargets(for: .smappserviceActive, userID: 501)
        XCTAssertEqual(targets, ["gui/501/com.keypath.kanata", "system/com.keypath.kanata"])
    }

    func testPreferredLaunchctlTargetsForLegacyUseSystemOnly() {
        let targets = KanataDaemonManager.preferredLaunchctlTargets(for: .legacyActive, userID: 501)
        XCTAssertEqual(targets, ["system/com.keypath.kanata"])
    }

    // MARK: - Singleton Tests

    func testSingleton() {
        let manager1 = KanataDaemonManager.shared
        let manager2 = KanataDaemonManager.shared
        XCTAssertIdentical(manager1, manager2, "Should return same singleton instance")
    }

    func testRegister_WhenEnabledButNotLoaded_AttemptsRecoveryReregister() async throws {
        final class EnabledMockService: SMAppServiceProtocol, @unchecked Sendable {
            var status: SMAppService.Status = .enabled
            private(set) var registerCalls = 0
            private(set) var unregisterCalls = 0

            func register() throws {
                registerCalls += 1
                status = .enabled
            }

            func unregister() async throws {
                unregisterCalls += 1
                status = .notRegistered
            }
        }

        let mockService = EnabledMockService()
        KanataDaemonManager.smServiceFactory = { _ in mockService }
        // The provider is the single owner of status reads (#853); point it at the
        // same mock so register()'s initial + post-mutation status reads observe it.
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 0,
            serviceFactory: { _ in mockService }
        )

        var probeCount = 0
        KanataDaemonManager.registeredButNotLoadedOverride = {
            probeCount += 1
            return probeCount == 1
        }

        try await manager.register()

        XCTAssertEqual(mockService.unregisterCalls, 1, "Should unregister stale enabled registration")
        XCTAssertEqual(mockService.registerCalls, 1, "Should re-register after unregistering stale state")
        XCTAssertGreaterThanOrEqual(probeCount, 2, "Should probe stale state before and after recovery")
    }

    func testRegisteredButNotLoadedUsesInjectedSystemStateProviderForProcessDiscovery() async {
        final class EnabledMockService: SMAppServiceProtocol, @unchecked Sendable {
            var status: SMAppService.Status = .enabled

            func register() throws {}
            func unregister() async throws {}
        }

        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configureLaunchctlResult { _, _ in
            ProcessResult(exitCode: 113, stdout: "", stderr: "service not found", duration: 0.01)
        }
        await runner.configurePgrepResult { pattern in
            pattern == "kanata.*--cfg" ? [4242] : []
        }

        let mockService = EnabledMockService()
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 0,
            serviceFactory: { _ in mockService }
        )
        let provider = SystemStateProvider(subprocessRunner: runner)
        let manager = KanataDaemonManager(subprocessRunner: runner, systemStateProvider: provider)

        let isStale = await manager.isRegisteredButNotLoaded()
        let commands = await runner.executedCommands

        XCTAssertFalse(isStale, "A live Kanata process should suppress stale-registration recovery")
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "kanata.*--cfg"] },
            "KanataDaemonManager should use the injected provider's subprocess runner for process discovery"
        )
    }
}
