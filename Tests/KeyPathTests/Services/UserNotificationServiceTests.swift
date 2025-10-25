import Testing
import Foundation
@testable import KeyPath

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
        // shortMessage returns fixed user-friendly strings, not the associated values
        let permissionDenied = LaunchFailureStatus.permissionDenied("Accessibility required")
        #expect(permissionDenied.shortMessage == "Kanata needs permissions")

        let serviceFailure = LaunchFailureStatus.serviceFailure("test error")
        #expect(serviceFailure.shortMessage == "Kanata service failed")

        let configError = LaunchFailureStatus.configError("invalid config")
        #expect(configError.shortMessage == "Configuration error")

        let missingDep = LaunchFailureStatus.missingDependency("required binary")
        #expect(missingDep.shortMessage == "Kanata not installed")
    }

    // MARK: - Integration Tests
    //
    // NOTE: These tests require macOS app bundle context for UNUserNotificationCenter
    // and will be skipped in Swift Package Manager test context.

    @Test("Service initializes without crashing",
          .enabled(if: Bundle.main.bundleIdentifier != nil))
    func serviceInitialization() {
        // Just accessing .shared should not crash
        _ = UserNotificationService.shared
    }

    @Test("Request authorization is idempotent",
          .enabled(if: Bundle.main.bundleIdentifier != nil))
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

    @Test("Different failure types generate different messages")
    func differentKeysForDifferentTypes() {
        let permissionDenied = LaunchFailureStatus.permissionDenied("Accessibility required")
        let configError = LaunchFailureStatus.configError("Bad syntax")

        // Different failure types should have different short messages
        #expect(permissionDenied.shortMessage != configError.shortMessage)
    }

    @Test("Same failure type with same message generates consistent results")
    func consistentMessages() {
        let status1 = LaunchFailureStatus.serviceFailure("Connection failed")
        let status2 = LaunchFailureStatus.serviceFailure("Connection failed")

        #expect(status1.shortMessage == status2.shortMessage)
        #expect(status1 == status2)
    }
}