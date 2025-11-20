import Foundation
import Testing

@testable import KeyPathAppKit
import KeyPathCore

/// Tests for the consolidated KeyPathError type
///
/// Verifies:
/// - Error type hierarchy and categorization
/// - LocalizedError conformance (descriptions, suggestions)
/// - Equatable conformance for testing
/// - Sendable conformance for Swift 6 concurrency
/// - Error classification (recoverable, user-facing)
/// - Convenience constructors
@Suite("KeyPathError Tests")
struct KeyPathErrorTests {
    // MARK: - Configuration Errors

    @Test("Configuration error descriptions")
    func configurationErrorDescriptions() {
        let fileNotFound = KeyPathError.configuration(.fileNotFound(path: "/test/path"))
        #expect(fileNotFound.errorDescription?.contains("/test/path") == true)
        #expect(fileNotFound.failureReason == "Configuration operation failed")

        let validationFailed = KeyPathError.configuration(
            .validationFailed(errors: ["error1", "error2"])
        )
        #expect(validationFailed.errorDescription?.contains("error1") == true)
        #expect(validationFailed.errorDescription?.contains("error2") == true)

        let parseError = KeyPathError.configuration(.parseError(line: 42, message: "invalid syntax"))
        #expect(parseError.errorDescription?.contains("line 42") == true)
        #expect(parseError.errorDescription?.contains("invalid syntax") == true)
    }

    @Test("Configuration error recovery suggestions")
    func configurationErrorRecoverySuggestions() {
        let fileNotFound = KeyPathError.configuration(.fileNotFound(path: "/test/path"))
        #expect(fileNotFound.recoverySuggestion?.contains("path") == true)

        let validationFailed = KeyPathError.configuration(
            .validationFailed(errors: ["error1"])
        )
        #expect(validationFailed.recoverySuggestion?.contains("syntax") == true)
    }

    @Test("Configuration errors are not recoverable by default")
    func configurationErrorRecoverability() {
        let fileNotFound = KeyPathError.configuration(.fileNotFound(path: "/test/path"))
        #expect(fileNotFound.isRecoverable == true)

        let loadFailed = KeyPathError.configuration(.loadFailed(reason: "test"))
        #expect(loadFailed.isRecoverable == true)

        let saveFailed = KeyPathError.configuration(.saveFailed(reason: "test"))
        #expect(saveFailed.isRecoverable == false)
    }

    // MARK: - Process Errors

    @Test("Process error descriptions")
    func processErrorDescriptions() {
        let startFailed = KeyPathError.process(.startFailed(reason: "permission denied"))
        #expect(startFailed.errorDescription?.contains("permission denied") == true)
        #expect(startFailed.failureReason == "Process lifecycle operation failed")

        let notRunning = KeyPathError.process(.notRunning)
        #expect(notRunning.errorDescription == "Process is not running")

        let stateTransition = KeyPathError.process(
            .stateTransitionFailed(from: "stopped", to: "running")
        )
        #expect(stateTransition.errorDescription?.contains("stopped") == true)
        #expect(stateTransition.errorDescription?.contains("running") == true)
    }

    @Test("Process error recovery suggestions")
    func processErrorRecoverySuggestions() {
        let notRunning = KeyPathError.process(.notRunning)
        #expect(notRunning.recoverySuggestion?.contains("Start") == true)

        let launchAgentNotFound = KeyPathError.process(.launchAgentNotFound)
        #expect(launchAgentNotFound.recoverySuggestion?.contains("wizard") == true)
    }

    @Test("Process errors recoverability")
    func processErrorRecoverability() {
        let notRunning = KeyPathError.process(.notRunning)
        #expect(notRunning.isRecoverable == true)

        let stopFailed = KeyPathError.process(.stopFailed(underlyingError: "test"))
        #expect(stopFailed.isRecoverable == true)

        let startFailed = KeyPathError.process(.startFailed(reason: "test"))
        #expect(startFailed.isRecoverable == false)
    }

    // MARK: - Permission Errors

    @Test("Permission error descriptions")
    func permissionErrorDescriptions() {
        let accessibility = KeyPathError.permission(.accessibilityNotGranted)
        #expect(accessibility.errorDescription == "Accessibility permission not granted")
        #expect(accessibility.failureReason == "Permission or security check failed")

        let inputMonitoring = KeyPathError.permission(.inputMonitoringNotGranted)
        #expect(inputMonitoring.errorDescription == "Input Monitoring permission not granted")

        let keychainSave = KeyPathError.permission(.keychainSaveFailed(status: -25300))
        #expect(keychainSave.errorDescription?.contains("-25300") == true)
    }

    @Test("Permission error recovery suggestions")
    func permissionErrorRecoverySuggestions() {
        let accessibility = KeyPathError.permission(.accessibilityNotGranted)
        #expect(accessibility.recoverySuggestion?.contains("System Settings") == true)
        #expect(accessibility.recoverySuggestion?.contains("Privacy & Security") == true)

        let inputMonitoring = KeyPathError.permission(.inputMonitoringNotGranted)
        #expect(inputMonitoring.recoverySuggestion?.contains("System Settings") == true)
    }

    @Test("Permission errors are not recoverable")
    func permissionErrorRecoverability() {
        let accessibility = KeyPathError.permission(.accessibilityNotGranted)
        #expect(accessibility.isRecoverable == false)

        let inputMonitoring = KeyPathError.permission(.inputMonitoringNotGranted)
        #expect(inputMonitoring.isRecoverable == false)
    }

    // MARK: - System Errors

    @Test("System error descriptions")
    func systemErrorDescriptions() {
        let eventTapFailed = KeyPathError.system(.eventTapCreationFailed)
        #expect(eventTapFailed.errorDescription == "Failed to create event tap")

        let invalidKeyCode = KeyPathError.system(.invalidKeyCode(999))
        #expect(invalidKeyCode.errorDescription?.contains("999") == true)

        let driverNotLoaded = KeyPathError.system(.driverNotLoaded(driver: "VirtualHID"))
        #expect(driverNotLoaded.errorDescription?.contains("VirtualHID") == true)
    }

    @Test("System error recovery suggestions")
    func systemErrorRecoverySuggestions() {
        let driverNotLoaded = KeyPathError.system(.driverNotLoaded(driver: "VirtualHID"))
        #expect(driverNotLoaded.recoverySuggestion?.contains("wizard") == true)
    }

    @Test("System errors are not recoverable")
    func systemErrorRecoverability() {
        let eventTapFailed = KeyPathError.system(.eventTapCreationFailed)
        #expect(eventTapFailed.isRecoverable == false)

        let driverNotLoaded = KeyPathError.system(.driverNotLoaded(driver: "test"))
        #expect(driverNotLoaded.isRecoverable == false)
    }

    // MARK: - Communication Errors

    @Test("Communication error descriptions")
    func communicationErrorDescriptions() {
        let timeout = KeyPathError.communication(.timeout)
        #expect(timeout.errorDescription == "Communication timeout")

        let payloadTooLarge = KeyPathError.communication(.payloadTooLarge(size: 2000))
        #expect(payloadTooLarge.errorDescription?.contains("2000") == true)

        let notAuthenticated = KeyPathError.communication(.notAuthenticated)
        #expect(notAuthenticated.errorDescription == "Not authenticated")
    }

    @Test("Communication error recovery suggestions")
    func communicationErrorRecoverySuggestions() {
        let timeout = KeyPathError.communication(.timeout)
        #expect(timeout.recoverySuggestion?.contains("restart") == true)

        let notAuthenticated = KeyPathError.communication(.notAuthenticated)
        #expect(notAuthenticated.recoverySuggestion?.contains("Restart") == true)
    }

    @Test("Communication errors are recoverable")
    func communicationErrorRecoverability() {
        let timeout = KeyPathError.communication(.timeout)
        #expect(timeout.isRecoverable == true)

        let noResponse = KeyPathError.communication(.noResponse)
        #expect(noResponse.isRecoverable == true)
    }

    // MARK: - Coordination Errors

    @Test("Coordination error descriptions")
    func coordinationErrorDescriptions() {
        let invalidState = KeyPathError.coordination(
            .invalidState(expected: "running", actual: "stopped")
        )
        #expect(invalidState.errorDescription?.contains("running") == true)
        #expect(invalidState.errorDescription?.contains("stopped") == true)

        let conflictDetected = KeyPathError.coordination(.conflictDetected(service: "Karabiner"))
        #expect(conflictDetected.errorDescription?.contains("Karabiner") == true)

        let systemDetection = KeyPathError.coordination(
            .systemDetectionFailed(component: "driver", reason: "not found")
        )
        #expect(systemDetection.errorDescription?.contains("driver") == true)
        #expect(systemDetection.errorDescription?.contains("not found") == true)
    }

    @Test("Coordination error display preferences")
    func coordinationErrorDisplayPreferences() {
        let operationCancelled = KeyPathError.coordination(.operationCancelled)
        #expect(operationCancelled.shouldDisplayToUser == false)

        let invalidState = KeyPathError.coordination(
            .invalidState(expected: "running", actual: "stopped")
        )
        #expect(invalidState.shouldDisplayToUser == true)
    }

    // MARK: - Logging Errors

    @Test("Logging error descriptions")
    func loggingErrorDescriptions() {
        let fileCreationFailed = KeyPathError.logging(
            .fileCreationFailed(path: "/var/log/test.log")
        )
        #expect(fileCreationFailed.errorDescription?.contains("/var/log/test.log") == true)

        let writeFailed = KeyPathError.logging(.writeFailed(reason: "disk full"))
        #expect(writeFailed.errorDescription?.contains("disk full") == true)
    }

    @Test("Logging errors should not display to user")
    func loggingErrorDisplayPreferences() {
        let fileCreationFailed = KeyPathError.logging(
            .fileCreationFailed(path: "/var/log/test.log")
        )
        #expect(fileCreationFailed.shouldDisplayToUser == false)
    }

    // MARK: - Convenience Constructors

    @Test("Convenience constructors work correctly")
    func convenienceConstructors() {
        let configNotFound = KeyPathError.configFileNotFound("/test/path")
        #expect(configNotFound.errorDescription?.contains("/test/path") == true)

        let processStartFailed = KeyPathError.processStartFailed("permission denied")
        #expect(processStartFailed.errorDescription?.contains("permission denied") == true)

        let accessibilityError = KeyPathError.accessibilityNotGranted
        #expect(accessibilityError.errorDescription?.contains("Accessibility") == true)

        let inputMonitoringError = KeyPathError.inputMonitoringNotGranted
        #expect(inputMonitoringError.errorDescription?.contains("Input Monitoring") == true)

        let udpTimeoutError = KeyPathError.udpTimeout
        #expect(udpTimeoutError.errorDescription?.contains("timeout") == true)

        let driverError = KeyPathError.driverNotLoaded("VirtualHID")
        #expect(driverError.errorDescription?.contains("VirtualHID") == true)
    }

    // MARK: - Equatable Conformance

    @Test("Equatable conformance works correctly")
    func equatableConformance() {
        // Same errors should be equal
        let error1 = KeyPathError.configuration(.fileNotFound(path: "/test"))
        let error2 = KeyPathError.configuration(.fileNotFound(path: "/test"))
        #expect(error1 == error2)

        // Different paths should not be equal
        let error3 = KeyPathError.configuration(.fileNotFound(path: "/other"))
        #expect(error1 != error3)

        // Different error types should not be equal
        let error4 = KeyPathError.process(.notRunning)
        #expect(error1 != error4)

        // Same category but different cases should not be equal
        let error5 = KeyPathError.configuration(.loadFailed(reason: "test"))
        #expect(error1 != error5)
    }

    // MARK: - Error Classification

    @Test("Error display filtering works correctly")
    func errorDisplayFiltering() {
        // Errors that should display to user
        let permissionError = KeyPathError.permission(.accessibilityNotGranted)
        #expect(permissionError.shouldDisplayToUser == true)

        let validationError = KeyPathError.configuration(
            .validationFailed(errors: ["test"])
        )
        #expect(validationError.shouldDisplayToUser == true)

        let startFailedError = KeyPathError.process(.startFailed(reason: "test"))
        #expect(startFailedError.shouldDisplayToUser == true)

        // Errors that should not display to user
        let loggingError = KeyPathError.logging(.writeFailed(reason: "test"))
        #expect(loggingError.shouldDisplayToUser == false)

        let cancelledError = KeyPathError.coordination(.operationCancelled)
        #expect(cancelledError.shouldDisplayToUser == false)
    }

    @Test("Error recoverability classification")
    func errorRecoverabilityClassification() {
        // Recoverable errors
        let configNotFound = KeyPathError.configuration(.fileNotFound(path: "/test"))
        #expect(configNotFound.isRecoverable == true)

        let processNotRunning = KeyPathError.process(.notRunning)
        #expect(processNotRunning.isRecoverable == true)

        let commTimeout = KeyPathError.communication(.timeout)
        #expect(commTimeout.isRecoverable == true)

        // Non-recoverable errors
        let permissionError = KeyPathError.permission(.accessibilityNotGranted)
        #expect(permissionError.isRecoverable == false)

        let eventTapError = KeyPathError.system(.eventTapCreationFailed)
        #expect(eventTapError.isRecoverable == false)
    }

    // MARK: - Sendable Conformance (Compile-Time Test)

    @Test("KeyPathError is Sendable")
    func sendableConformance() async {
        // This test verifies that KeyPathError can be passed between actors
        // If it compiles, Sendable conformance is working
        let error = KeyPathError.configuration(.fileNotFound(path: "/test"))

        // Send error to a detached task
        await Task.detached {
            _ = error.errorDescription
        }.value

        // If this compiles, Sendable conformance is working correctly
        #expect(true)
    }
}
