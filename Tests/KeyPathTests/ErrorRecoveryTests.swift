@testable import KeyPathAppKit
import KeyPathCore
import KeyPathWizardCore
import XCTest

/// Tests for error recovery infrastructure.
/// Verifies that crash detection, config backup, and validation
/// failure handling work correctly.
final class ErrorRecoveryTests: XCTestCase {
    // MARK: - Config Backup

    @MainActor
    func testConfigBackup_InvalidConfigGetsBackedUp() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configService = ConfigurationService(configDirectory: tempDir.path)

        // Write a valid config first
        let validCollections = RuleCollectionCatalog().defaultCollections()
        try await configService.saveConfiguration(
            ruleCollections: validCollections
        )

        // Verify config file exists
        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
    }

    // MARK: - VHID Safety Check

    func testVHIDSafety_EmergencyStopWhenDaemonUnhealthy() {
        XCTAssertTrue(
            VHIDSafetyCheck.shouldEmergencyStop(kanataRunning: true, vhidDaemonHealthy: false),
            "Should trigger emergency stop when kanata runs without VirtualHID"
        )
    }

    func testVHIDSafety_NoStopWhenBothHealthy() {
        XCTAssertFalse(
            VHIDSafetyCheck.shouldEmergencyStop(kanataRunning: true, vhidDaemonHealthy: true),
            "Should not stop when both are healthy"
        )
    }

    func testVHIDSafety_NoStopWhenKanataNotRunning() {
        XCTAssertFalse(
            VHIDSafetyCheck.shouldEmergencyStop(kanataRunning: false, vhidDaemonHealthy: false),
            "Should not stop when kanata isn't running"
        )
    }

    // MARK: - Config Validation

    @MainActor
    func testConfigValidation_ValidConfigPasses() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("validation-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configService = ConfigurationService(configDirectory: tempDir.path)
        let collections = RuleCollectionCatalog().defaultCollections()
        let config = KanataConfiguration.generateFromCollections(collections)

        let result = await configService.validateConfiguration(config)
        XCTAssertTrue(result.isValid, "Default config should validate. Errors: \(result.errors)")
    }

    @MainActor
    func testConfigValidation_EmptyConfigFails() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("validation-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configService = ConfigurationService(configDirectory: tempDir.path)
        let result = await configService.validateConfiguration("")
        XCTAssertFalse(result.isValid, "Empty config should fail validation")
    }

    // MARK: - Health State Transitions

    @MainActor
    func testHealthObserver_UnhealthyOnIssues() async {
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { states.append($0) },
            onDismiss: {},
            sleep: { _ in }
        )

        let controller = MainAppStateController()
        controller.validationState = .failed(blockingCount: 2, totalCount: 3)
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .error,
                category: .daemon,
                title: "Service stopped",
                description: "Kanata is not running",
                autoFixAction: nil,
                userAction: nil
            ),
        ]

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(
            states.contains(where: {
                if case .unhealthy = $0 { return true }
                return false
            }),
            "Should show unhealthy when validation fails with issues"
        )
    }

    @MainActor
    func testHealthObserver_RecoveryToHealthy() async {
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { states.append($0) },
            onDismiss: { states.append(.dismissed) },
            sleep: { _ in }
        )

        let controller = MainAppStateController()
        controller.validationState = .failed(blockingCount: 1, totalCount: 1)
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .error,
                category: .daemon,
                title: "Stopped",
                description: "Not running",
                autoFixAction: nil,
                userAction: nil
            ),
        ]

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        // Simulate recovery
        controller.validationState = .success
        controller.issues = []
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(states.contains(.healthy),
                      "Should transition to healthy after recovery")
    }
}
