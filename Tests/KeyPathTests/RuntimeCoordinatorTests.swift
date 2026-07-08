@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class RuntimeCoordinatorTests: KeyPathTestCase {
    lazy var manager: RuntimeCoordinator = .init()

    override func setUp() {
        super.setUp()
        KarabinerConflictService.testDaemonRunning = nil
    }

    override func tearDown() {
        KarabinerConflictService.testDaemonRunning = nil
        super.tearDown()
    }

    func testInitialState() {
        if let error = manager.lastError {
            XCTAssertTrue(
                error.lowercased().contains("install"),
                "Unexpected initial error: \(error)"
            )
        }
        XCTAssertTrue(manager.keyMappings.isEmpty, "Should have no initial mappings")
        XCTAssertTrue(manager.diagnostics.isEmpty, "Should have no initial diagnostics")
        XCTAssertNil(manager.lastProcessExitCode, "Should have no initial exit code")
    }

    func testDiagnosticManagement() {
        let diagnostic = KanataDiagnostic(
            timestamp: Date(),
            severity: .error,
            category: .configuration,
            title: "Test Error",
            description: "Test description",
            technicalDetails: "Test details",
            suggestedAction: "Test action",
            canAutoFix: false
        )

        manager.addDiagnostic(diagnostic)
        XCTAssertEqual(manager.diagnostics.count, 1, "Should have one diagnostic")
        XCTAssertEqual(manager.diagnostics.first?.title, "Test Error")

        manager.clearDiagnostics()
        XCTAssertTrue(manager.diagnostics.isEmpty, "Should have no diagnostics after clear")
    }

    func testConfigValidation() async {
        let validation = await manager.validateConfigFile()
        XCTAssertNotNil(validation.isValid)
        XCTAssertNotNil(validation.errors)
    }

    func testKeyMappingStorage() {
        let testMapping = KeyMapping(input: "caps", action: .keystroke(key: "escape"))
        manager.keyMappings.append(testMapping)

        XCTAssertEqual(manager.keyMappings.count, 1, "Should have one mapping")
        XCTAssertEqual(manager.keyMappings.first?.input, "caps")
        XCTAssertEqual(manager.keyMappings.first?.action, .keystroke(key: "escape"))
    }

    func testConfigPathProperty() {
        let configPath = manager.configPath
        XCTAssertFalse(configPath.isEmpty, "Config path should not be empty")
        XCTAssertTrue(configPath.contains("keypath.kbd"), "Config path should contain keypath.kbd")
    }

    func testInstallationStatus() {
        let isInstalled = manager.isCompletelyInstalled()
        XCTAssertNotNil(isInstalled)
    }

    func testPerformanceConfigValidation() async {
        let startTime = Date()
        _ = await manager.validateConfigFile()
        let duration = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 10.0, "Config validation should complete within 10 seconds")
    }

    // MARK: - Grab recovery (#625)

    /// An authoritative grab success must not clear an unrelated error — only a
    /// grab-recovery give-up message it set itself. (active=true takes the pure
    /// .recordSuccess path, which performs no service side effects.)
    func testGrabSuccessDoesNotClearUnrelatedError() async {
        manager.lastError = "Some unrelated install error"
        await manager.handleGrabStatusChanged(active: true, reason: nil)
        XCTAssertEqual(
            manager.lastError, "Some unrelated install error",
            "Grab success should leave an unrelated error untouched"
        )
    }

    func testGrabFailureSurfacesErrorWithoutRecoveryDelay() async {
        let started = Date()

        await manager.handleGrabStatusChanged(active: false, reason: "test grab failure")

        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            1.0,
            "Grab failure handling should surface state instead of running the old multi-second recovery sequence"
        )
        XCTAssertEqual(
            manager.lastError,
            "Keyboard remapping is not active: kanata could not capture the keyboard. Try quitting other keyboard tools, then restart KeyPath."
        )
    }
}
