import Foundation
@testable import KeyPathAppKit
import KeyPathWizardCore
import Testing

/// Tests for UserNotificationService - notification management and deduplication
@Suite("User Notification Service Tests")
@MainActor
struct UserNotificationServiceTests {
    // MARK: - Category Tests

    @Test("Category raw values are correctly formatted")
    func categoryRawValues() {
        #expect(UserNotificationService.Category.serviceFailure.rawValue == "KP_SERVICE_FAILURE")
        #expect(UserNotificationService.Category.recovery.rawValue == "KP_RECOVERY")
        #expect(UserNotificationService.Category.permission.rawValue == "KP_PERMISSION")
        #expect(UserNotificationService.Category.info.rawValue == "KP_INFO")
    }

    // MARK: - Action Tests

    @Test("Action identifiers are correctly formatted")
    func actionIdentifiers() {
        #expect(UserNotificationService.Action.openWizard.rawValue == "KP_ACTION_OPEN_WIZARD")
        #expect(UserNotificationService.Action.retryStart.rawValue == "KP_ACTION_RETRY_START")
        #expect(UserNotificationService.Action.openInputMonitoring.rawValue == "KP_ACTION_OPEN_INPUT_MONITORING")
        #expect(UserNotificationService.Action.openAccessibility.rawValue == "KP_ACTION_OPEN_ACCESSIBILITY")
        #expect(UserNotificationService.Action.openApp.rawValue == "KP_ACTION_OPEN_APP")
    }

    // MARK: - LaunchFailureStatus Tests

    @Test("Launch failure status messages are user-friendly")
    func launchFailureStatusMessages() {
        let permissionDenied = LaunchFailureStatus.permissionDenied("Accessibility required")
        #expect(permissionDenied.shortMessage.contains("permissions") || permissionDenied.shortMessage.contains("Accessibility"))

        let serviceFailure = LaunchFailureStatus.serviceFailure("test error")
        #expect(serviceFailure.shortMessage == "test error" || serviceFailure.shortMessage.contains("test error"))

        let configError = LaunchFailureStatus.configError("invalid config")
        #expect(configError.shortMessage == "invalid config" || configError.shortMessage.contains("invalid config"))

        let missingDep = LaunchFailureStatus.missingDependency("required binary")
        #expect(missingDep.shortMessage == "required binary" || missingDep.shortMessage.contains("required binary"))
    }

    // MARK: - Integration Tests

    @Test("Service initializes without crashing")
    func serviceInitialization() {
        let service = UserNotificationService.shared
        // shared is a singleton, not optional - verify it exists by calling a method
        service.requestAuthorizationIfNeeded()
        // If we get here without crashing, the service initialized successfully
    }

    @Test("Request authorization is idempotent")
    func authorizationRequest() {
        let service = UserNotificationService.shared
        // Should not crash when called multiple times
        service.requestAuthorizationIfNeeded()
        service.requestAuthorizationIfNeeded()
    }
}

/// Tests for deduplication key generation
@Suite("Notification Deduplication Tests")
struct NotificationDeduplicationTests {
    @Test("Different failure messages generate different keys")
    func differentKeysForDifferentMessages() {
        let status1 = LaunchFailureStatus.permissionDenied("Accessibility required")
        let status2 = LaunchFailureStatus.permissionDenied("Input Monitoring required")

        #expect(status1.shortMessage != status2.shortMessage)
    }

    @Test("Same failure type with same message generates consistent results")
    func consistentMessages() {
        let status1 = LaunchFailureStatus.serviceFailure("Connection failed")
        let status2 = LaunchFailureStatus.serviceFailure("Connection failed")

        #expect(status1.shortMessage == status2.shortMessage)
        #expect(status1 == status2)
    }
}
