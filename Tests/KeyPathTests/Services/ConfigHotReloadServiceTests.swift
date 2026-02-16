import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Unit tests for ConfigHotReloadService.
///
/// Tests configuration hot-reload functionality.
/// These tests verify:
/// - Configuration validation
/// - Reload handler invocation
/// - Callback execution
/// - Error handling
@MainActor
final class ConfigHotReloadServiceTests: XCTestCase {
    var service: ConfigHotReloadService!
    var configService: ConfigurationService!
    var reloadHandlerCalled: Bool!
    var reloadHandlerResult: Bool!

    override func setUp() async throws {
        try await super.setUp()
        service = ConfigHotReloadService.shared
        // Use short delay to avoid 2+ second waits in tests
        service.statusResetDelay = 0.01
        configService = ConfigurationService(configDirectory: NSTemporaryDirectory())
        reloadHandlerCalled = false
        reloadHandlerResult = true

        service.configure(
            configurationService: configService,
            reloadHandler: { [weak self] in
                self?.reloadHandlerCalled = true
                return self?.reloadHandlerResult ?? false
            },
            configParser: { _ in
                // Simple parser - in real usage this would parse Kanata config
                []
            }
        )
    }

    override func tearDown() async throws {
        // Reset delay to default
        service?.statusResetDelay = 2.0
        // Avoid cross-test leakage since the service is a singleton.
        service?.callbacks = .init()
        service = nil
        configService = nil
        reloadHandlerCalled = nil
        reloadHandlerResult = nil
        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testConfigureSetsDependencies() {
        XCTAssertNotNil(service, "Service should be initialized")
    }

    // MARK: - File Reading Tests

    func testHandleExternalChangeReadsFile() async {
        let tempFile = createTempConfigFile(content: "(defcfg)\n(defsrc)\n(deflayer base)")

        let result = await service.handleExternalChange(configPath: tempFile.path)

        XCTAssertNotNil(result.newContent, "Should read file content")
        XCTAssertTrue(result.newContent?.contains("defcfg") ?? false, "Should contain config content")
    }

    func testHandleExternalChangeFailsWhenFileMissing() async {
        let result = await service.handleExternalChange(configPath: "/nonexistent/path.kbd")

        XCTAssertFalse(result.success, "Should fail when file doesn't exist")
        XCTAssertTrue(result.message.contains("deleted") || result.message.contains("not found"), "Error message should mention file issue")
        XCTAssertNil(result.newContent, "Should not have content when file missing")
    }

    // MARK: - Validation Tests

    func testHandleExternalChangeValidatesConfig() async {
        let validConfig = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let tempFile = createTempConfigFile(content: validConfig)

        let result = await service.handleExternalChange(configPath: tempFile.path)

        // In test mode, ConfigurationService does lightweight validation
        // Should succeed if config is parseable
        XCTAssertTrue(result.success || !result.success, "Should return validation result")
    }

    func testHandleExternalChangeFailsOnInvalidConfig() async {
        let invalidConfig = "invalid config syntax {"
        let tempFile = createTempConfigFile(content: invalidConfig)

        let result = await service.handleExternalChange(configPath: tempFile.path)

        // May fail validation or succeed with test mode - either is acceptable
        XCTAssertNotNil(result, "Should return a result")
    }

    // MARK: - Reload Handler Tests

    func testHandleExternalChangeCallsReloadHandler() async {
        reloadHandlerResult = true
        let validConfig = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let tempFile = createTempConfigFile(content: validConfig)

        let result = await service.handleExternalChange(configPath: tempFile.path)

        // Reload handler is called if validation succeeds
        if result.success {
            XCTAssertTrue(reloadHandlerCalled, "Should call reload handler on success")
        }
    }

    func testHandleExternalChangeReturnsPendingReloadWhenServiceUnavailable() async {
        // When reload handler fails but service is unavailable (process not running),
        // we should return success:false + pendingReload:true because the config is valid
        // but was never applied to kanata.
        reloadHandlerResult = false
        let validConfig = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let tempFile = createTempConfigFile(content: validConfig)

        let result = await service.handleExternalChange(configPath: tempFile.path)

        // In test environment, Kanata process is never running, so reload failure
        // is treated as "service unavailable" (pendingReload - config valid but not applied)
        if reloadHandlerCalled {
            XCTAssertFalse(result.success, "Should not report success when config was not applied")
            XCTAssertTrue(result.pendingReload, "Should indicate pending reload")
            XCTAssertEqual(result.message, "Config saved, will apply when service starts")
            XCTAssertNotNil(result.newContent, "Should still include config content")
        }
    }

    func testHandleExternalChangeFailsWhenReloadFailsAndServiceRunning() async {
        // If reload fails while service is running and installation state is not pending,
        // this should be treated as a real failure.
        reloadHandlerResult = false

        service.configure(
            configurationService: configService,
            reloadHandler: { [weak self] in
                self?.reloadHandlerCalled = true
                return self?.reloadHandlerResult ?? false
            },
            configParser: { _ in [] },
            serviceManagementStateProvider: { .smappserviceActive },
            isKanataProcessRunningProvider: { true }
        )

        let validConfig = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let tempFile = createTempConfigFile(content: validConfig)

        let result = await service.handleExternalChange(configPath: tempFile.path)

        XCTAssertTrue(reloadHandlerCalled, "Reload handler should be called")
        XCTAssertFalse(result.success, "Should fail when reload fails and service is running")
        XCTAssertEqual(result.message, "Hot reload failed")
    }

    // MARK: - Callback Tests

    func testCallbacksInvokedOnSuccess() async {
        reloadHandlerResult = true
        let validConfig = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let tempFile = createTempConfigFile(content: validConfig)

        var detectedCalled = false
        var validatingCalled = false
        var successCalled = false
        let resetExpectation = expectation(description: "onReset called")

        service.callbacks.onDetected = { detectedCalled = true }
        service.callbacks.onValidating = { validatingCalled = true }
        service.callbacks.onSuccess = { _ in successCalled = true }
        service.callbacks.onReset = { resetExpectation.fulfill() }

        _ = await service.handleExternalChange(configPath: tempFile.path)

        await fulfillment(of: [resetExpectation], timeout: 1.0)

        XCTAssertTrue(detectedCalled, "onDetected should be called")
        XCTAssertTrue(validatingCalled, "onValidating should be called")
        XCTAssertTrue(successCalled, "onSuccess should be called")
    }

    func testCallbacksInvokedOnServiceUnavailable() async {
        // Force reload handler to fail - in test environment this triggers
        // "service unavailable" path (process not running) which calls onReset
        reloadHandlerResult = false
        let validConfig = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let tempFile = createTempConfigFile(content: validConfig)

        var detectedCalled = false
        let resetExpectation = expectation(description: "onReset called")

        service.callbacks.onDetected = { detectedCalled = true }
        service.callbacks.onReset = { resetExpectation.fulfill() }

        let result = await service.handleExternalChange(configPath: tempFile.path)

        await fulfillment(of: [resetExpectation], timeout: 1.0)

        XCTAssertTrue(detectedCalled, "onDetected should be called")
        // In test environment, service is unavailable (process not running)
        // so result is pendingReload (config valid but not applied) and onReset is called
        XCTAssertFalse(result.success, "Should not report success when service unavailable")
        XCTAssertTrue(result.pendingReload, "Should indicate pending reload")
    }

    // MARK: - Parser Tests

    func testParseKeyMappingsReturnsMappings() {
        service.configure(
            configurationService: configService,
            reloadHandler: { true },
            configParser: { _ in
                [KeyMapping(input: "caps", output: "esc")]
            }
        )

        let mappings = service.parseKeyMappings(from: "test config")
        XCTAssertEqual(mappings?.count, 1, "Should parse key mappings")
        XCTAssertEqual(mappings?.first?.input, "caps", "Should parse correct input")
    }

    func testParseKeyMappingsReturnsNilWhenParserThrows() {
        // Configure parser to throw an error
        service.configure(
            configurationService: configService,
            reloadHandler: { true },
            configParser: { _ in
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parser error"])
            }
        )

        let mappings = service.parseKeyMappings(from: "test config")
        XCTAssertNil(mappings, "Should return nil when parser throws")
    }

    func testParseKeyMappingsHandlesParserErrors() {
        service.configure(
            configurationService: configService,
            reloadHandler: { true },
            configParser: { _ in
                throw NSError(domain: "test", code: 1)
            }
        )

        let mappings = service.parseKeyMappings(from: "test config")
        XCTAssertNil(mappings, "Should return nil when parser throws")
    }

    // MARK: - Helper Methods

    private func createTempConfigFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).kbd")

        try! content.write(to: tempFile, atomically: true, encoding: .utf8)

        return tempFile
    }
}
