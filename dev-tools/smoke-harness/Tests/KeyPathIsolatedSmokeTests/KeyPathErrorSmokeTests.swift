import KeyPathCore
import Testing

@Suite("KeyPathError Isolated Smoke Tests")
struct KeyPathErrorSmokeTests {
    @Test("Configuration errors expose stable user-facing text")
    func configurationErrorText() {
        let fileNotFound = KeyPathError.configuration(.fileNotFound(path: "/test/path"))
        #expect(fileNotFound.errorDescription?.contains("/test/path") == true)
        #expect(fileNotFound.failureReason == "Configuration operation failed")
        #expect(fileNotFound.isRecoverable == true)

        let parseError = KeyPathError.configuration(.parseError(line: 42, message: "invalid syntax"))
        #expect(parseError.errorDescription?.contains("line 42") == true)
        #expect(parseError.errorDescription?.contains("invalid syntax") == true)
    }

    @Test("Permission errors stay user-facing and non-recoverable")
    func permissionErrorClassification() {
        let accessibility = KeyPathError.permission(.accessibilityNotGranted)
        #expect(accessibility.errorDescription == "Accessibility permission not granted")
        #expect(accessibility.recoverySuggestion?.contains("System Settings") == true)
        #expect(accessibility.shouldDisplayToUser == true)
        #expect(accessibility.isRecoverable == false)
    }

    @Test("Communication errors remain recoverable")
    func communicationErrorClassification() {
        let timeout = KeyPathError.communication(.timeout)
        #expect(timeout.errorDescription == "Communication timeout")
        #expect(timeout.recoverySuggestion?.contains("restart") == true)
        #expect(timeout.isRecoverable == true)
    }

    @Test("Equatable conformance works across common branches")
    func equatableConformance() {
        let left = KeyPathError.configuration(.fileNotFound(path: "/test"))
        let right = KeyPathError.configuration(.fileNotFound(path: "/test"))
        let other = KeyPathError.process(.notRunning)

        #expect(left == right)
        #expect(left != other)
    }
}
