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
        let testMapping = KeyMapping(input: "caps", output: "escape")
        manager.keyMappings.append(testMapping)

        XCTAssertEqual(manager.keyMappings.count, 1, "Should have one mapping")
        XCTAssertEqual(manager.keyMappings.first?.input, "caps")
        XCTAssertEqual(manager.keyMappings.first?.output, "escape")
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
}
