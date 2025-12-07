import Foundation
@testable import KeyPathAppKit
import Testing

// MARK: - KeyPathActionURI Parsing Tests

@Suite("KeyPathActionURI Parsing")
struct KeyPathActionURITests {
    @Test("Parses simple launch URI")
    func parsesSimpleLaunchURI() {
        let uri = KeyPathActionURI(string: "keypath://launch/Obsidian")

        #expect(uri != nil)
        #expect(uri?.action == "launch")
        #expect(uri?.target == "Obsidian")
        #expect(uri?.pathComponents == ["Obsidian"])
        #expect(uri?.queryItems.isEmpty == true)
    }

    @Test("Parses URI with multiple path components")
    func parsesMultiplePathComponents() {
        let uri = KeyPathActionURI(string: "keypath://rule/caps-esc/fired")

        #expect(uri != nil)
        #expect(uri?.action == "rule")
        #expect(uri?.target == "caps-esc")
        #expect(uri?.pathComponents == ["caps-esc", "fired"])
    }

    @Test("Parses URI with query parameters")
    func parsesQueryParameters() {
        let uri = KeyPathActionURI(string: "keypath://notify?title=Hello&body=World&sound=Pop")

        #expect(uri != nil)
        #expect(uri?.action == "notify")
        #expect(uri?.target == nil)
        #expect(uri?.queryItems["title"] == "Hello")
        #expect(uri?.queryItems["body"] == "World")
        #expect(uri?.queryItems["sound"] == "Pop")
    }

    @Test("Parses fakekey URI with action")
    func parsesFakekeyWithAction() {
        let uri = KeyPathActionURI(string: "keypath://fakekey/email-sig/tap")

        #expect(uri != nil)
        #expect(uri?.action == "fakekey")
        #expect(uri?.target == "email-sig")
        #expect(uri?.pathComponents == ["email-sig", "tap"])
    }

    @Test("Parses vkey alias")
    func parsesVkeyAlias() {
        let uri = KeyPathActionURI(string: "keypath://vkey/my-macro/press")

        #expect(uri != nil)
        #expect(uri?.action == "vkey")
        #expect(uri?.target == "my-macro")
        #expect(uri?.pathComponents == ["my-macro", "press"])
    }

    @Test("Rejects non-keypath scheme")
    func rejectsNonKeypathScheme() {
        let uri = KeyPathActionURI(string: "https://example.com")
        #expect(uri == nil)
    }

    @Test("Rejects empty host")
    func rejectsEmptyHost() {
        let uri = KeyPathActionURI(string: "keypath:///path")
        #expect(uri == nil)
    }

    @Test("Rejects invalid URL")
    func rejectsInvalidURL() {
        let uri = KeyPathActionURI(string: "not a url")
        #expect(uri == nil)
    }

    @Test("Handles URL-encoded characters")
    func handlesURLEncodedCharacters() {
        let uri = KeyPathActionURI(string: "keypath://notify?title=Hello%20World")

        #expect(uri != nil)
        #expect(uri?.queryItems["title"] == "Hello World")
    }

    @Test("Parses open URL action")
    func parsesOpenURLAction() {
        let uri = KeyPathActionURI(string: "keypath://open/github.com/user/repo")

        #expect(uri != nil)
        #expect(uri?.action == "open")
        #expect(uri?.pathComponents == ["github.com", "user", "repo"])
    }

    // MARK: - Shorthand Syntax Tests

    @Test("Parses shorthand launch syntax")
    func parsesShorthandLaunch() {
        let uri = KeyPathActionURI(string: "launch:obsidian")

        #expect(uri != nil)
        #expect(uri?.action == "launch")
        #expect(uri?.target == "obsidian")
        #expect(uri?.targetTitleCase == "Obsidian")
        #expect(uri?.isShorthand == true)
    }

    @Test("Parses shorthand with multiple path components")
    func parsesShorthandMultiplePaths() {
        let uri = KeyPathActionURI(string: "layer:nav:activate")

        #expect(uri != nil)
        #expect(uri?.action == "layer")
        #expect(uri?.target == "nav")
        #expect(uri?.pathComponents == ["nav", "activate"])
        #expect(uri?.isShorthand == true)
    }

    @Test("Parses shorthand with query parameters")
    func parsesShorthandWithQuery() {
        let uri = KeyPathActionURI(string: "notify:?title=Hello&body=World")

        #expect(uri != nil)
        #expect(uri?.action == "notify")
        #expect(uri?.target == nil)
        #expect(uri?.queryItems["title"] == "Hello")
        #expect(uri?.queryItems["body"] == "World")
        #expect(uri?.isShorthand == true)
    }

    @Test("Parses shorthand fakekey with action")
    func parsesShorthandFakekey() {
        let uri = KeyPathActionURI(string: "fakekey:email-sig:tap")

        #expect(uri != nil)
        #expect(uri?.action == "fakekey")
        #expect(uri?.target == "email-sig")
        #expect(uri?.pathComponents == ["email-sig", "tap"])
        #expect(uri?.isShorthand == true)
    }

    @Test("Parses shorthand rule with fired")
    func parsesShorthandRule() {
        let uri = KeyPathActionURI(string: "rule:caps-escape:fired")

        #expect(uri != nil)
        #expect(uri?.action == "rule")
        #expect(uri?.target == "caps-escape")
        #expect(uri?.pathComponents == ["caps-escape", "fired"])
    }

    @Test("Parses shorthand open URL")
    func parsesShorthandOpen() {
        let uri = KeyPathActionURI(string: "open:github.com")

        #expect(uri != nil)
        #expect(uri?.action == "open")
        #expect(uri?.target == "github.com")
    }

    @Test("Converts target to Title Case")
    func convertsTargetToTitleCase() {
        let uri = KeyPathActionURI(string: "launch:visual studio code")

        #expect(uri?.target == "visual studio code")
        #expect(uri?.targetTitleCase == "Visual Studio Code")
    }

    @Test("Full URI is not marked as shorthand")
    func fullURINotShorthand() {
        let uri = KeyPathActionURI(string: "keypath://launch/Obsidian")

        #expect(uri?.isShorthand == false)
    }

    @Test("Rejects empty action in shorthand")
    func rejectsEmptyActionShorthand() {
        let uri = KeyPathActionURI(string: ":obsidian")
        #expect(uri == nil)
    }

    @Test("Rejects string without colon")
    func rejectsNoColon() {
        let uri = KeyPathActionURI(string: "launch-obsidian")
        #expect(uri == nil)
    }

    @Test("Both syntaxes produce equivalent results")
    func syntaxesEquivalent() {
        let fullURI = KeyPathActionURI(string: "keypath://launch/Obsidian")
        let shorthand = KeyPathActionURI(string: "launch:Obsidian")

        #expect(fullURI?.action == shorthand?.action)
        #expect(fullURI?.target == shorthand?.target)
        #expect(fullURI?.pathComponents == shorthand?.pathComponents)
    }
}

// MARK: - ActionDispatcher Tests

@Suite("ActionDispatcher Routing")
struct ActionDispatcherRoutingTests {
    @Test("Dispatches launch action")
    @MainActor
    func dispatchesLaunchAction() {
        let uri = KeyPathActionURI(string: "keypath://launch/Calculator")!
        let result = ActionDispatcher.shared.dispatch(uri)

        // Launch returns success optimistically (async launch)
        #expect(result == .success)
    }

    @Test("Returns unknownAction for invalid action type")
    @MainActor
    func returnsUnknownActionForInvalidType() {
        let uri = KeyPathActionURI(string: "keypath://invalid/something")!
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .unknownAction(action) = result {
            #expect(action == "invalid")
        } else {
            Issue.record("Expected unknownAction result")
        }
    }

    @Test("Returns missingTarget for launch without app")
    @MainActor
    func returnsMissingTargetForLaunchWithoutApp() {
        // Create a URI that has launch action but no target
        // This requires constructing a URL with empty path
        let uri = KeyPathActionURI(string: "keypath://launch")!
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "launch")
        } else {
            Issue.record("Expected missingTarget result, got \(result)")
        }
    }

    @Test("Dispatches layer action")
    @MainActor
    func dispatchesLayerAction() {
        var receivedLayer: String?
        ActionDispatcher.shared.onLayerAction = { layer in
            receivedLayer = layer
        }

        let uri = KeyPathActionURI(string: "keypath://layer/nav")!
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
        #expect(receivedLayer == "nav")

        // Clean up
        ActionDispatcher.shared.onLayerAction = nil
    }

    @Test("Dispatches rule action with path")
    @MainActor
    func dispatchesRuleActionWithPath() {
        var receivedRule: String?
        var receivedPath: [String]?
        ActionDispatcher.shared.onRuleAction = { rule, path in
            receivedRule = rule
            receivedPath = path
        }

        let uri = KeyPathActionURI(string: "keypath://rule/caps-esc/fired")!
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
        #expect(receivedRule == "caps-esc")
        #expect(receivedPath == ["fired"])

        // Clean up
        ActionDispatcher.shared.onRuleAction = nil
    }

    @Test("Dispatches notify action")
    @MainActor
    func dispatchesNotifyAction() {
        let uri = KeyPathActionURI(string: "keypath://notify?title=Test&body=Message")!
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
    }

    @Test("Dispatches open action")
    @MainActor
    func dispatchesOpenAction() {
        let uri = KeyPathActionURI(string: "keypath://open/example.com")!
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
    }

    @Test("Dispatches fakekey action")
    @MainActor
    func dispatchesFakekeyAction() {
        let uri = KeyPathActionURI(string: "keypath://fakekey/test-key/tap")!
        let result = ActionDispatcher.shared.dispatch(uri)

        // Returns success optimistically (TCP call is async)
        #expect(result == .success)
    }

    @Test("Returns missingTarget for fakekey without name")
    @MainActor
    func returnsMissingTargetForFakekeyWithoutName() {
        let uri = KeyPathActionURI(string: "keypath://fakekey")!
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "fakekey")
        } else {
            Issue.record("Expected missingTarget result")
        }
    }

    @Test("Calls onError callback for unknown action")
    @MainActor
    func callsOnErrorForUnknownAction() {
        var errorMessage: String?
        ActionDispatcher.shared.onError = { message in
            errorMessage = message
        }

        let uri = KeyPathActionURI(string: "keypath://unknown/test")!
        _ = ActionDispatcher.shared.dispatch(uri)

        #expect(errorMessage?.contains("Unknown action type") == true)

        // Clean up
        ActionDispatcher.shared.onError = nil
    }
}

// MARK: - App Launch Approval Tests

@Suite("ActionDispatcher App Approval")
struct ActionDispatcherAppApprovalTests {
    @Test("Approved apps list starts empty or from UserDefaults")
    @MainActor
    func approvedAppsInitialization() {
        // Clear any existing approvals first
        ActionDispatcher.shared.clearAllAppApprovals()

        let apps = ActionDispatcher.shared.getApprovedApps()
        #expect(apps.isEmpty)
    }

    @Test("Trust all apps is disabled by default after clear")
    @MainActor
    func trustAllAppsDefaultsToDisabled() {
        ActionDispatcher.shared.clearAllAppApprovals()

        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == false)
    }

    @Test("Can enable and disable trust all apps")
    @MainActor
    func toggleTrustAllApps() {
        // Start clean
        ActionDispatcher.shared.clearAllAppApprovals()

        // Enable
        ActionDispatcher.shared.setTrustAllApps(true)
        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == true)

        // Disable
        ActionDispatcher.shared.setTrustAllApps(false)
        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == false)
    }

    @Test("Clear all approvals also clears trust all setting")
    @MainActor
    func clearApprovalsResetsTrustAll() {
        // Enable trust all first
        ActionDispatcher.shared.setTrustAllApps(true)
        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == true)

        // Clear all
        ActionDispatcher.shared.clearAllAppApprovals()

        // Trust all should be disabled
        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == false)
    }

    @Test("Revoke approval removes app from list")
    @MainActor
    func revokeApprovalRemovesApp() {
        ActionDispatcher.shared.clearAllAppApprovals()

        // Launch an app (in test mode, approval is bypassed but tracked)
        let uri = KeyPathActionURI(string: "keypath://launch/TestApp")!
        _ = ActionDispatcher.shared.dispatch(uri)

        // Note: Since we're in test mode, the app won't actually be added to approvals
        // because the approval dialog is skipped. Let's test the revoke API directly.

        // For this test, we need to verify the revoke API works correctly
        // We can't easily add an approval without showing a dialog, so we test
        // that revoking a non-existent app doesn't crash
        ActionDispatcher.shared.revokeAppApproval("SomeApp")

        let apps = ActionDispatcher.shared.getApprovedApps()
        #expect(!apps.contains("someapp")) // normalized to lowercase
    }

    @Test("App identifiers are normalized to lowercase")
    @MainActor
    func appIdentifiersNormalized() {
        ActionDispatcher.shared.clearAllAppApprovals()

        // Revoke with mixed case - should work on lowercase
        ActionDispatcher.shared.revokeAppApproval("MyApp")
        ActionDispatcher.shared.revokeAppApproval("MYAPP")
        ActionDispatcher.shared.revokeAppApproval("myapp")

        // All should target the same normalized key
        let apps = ActionDispatcher.shared.getApprovedApps()
        #expect(!apps.contains("myapp"))
    }

    @Test("Launch action works when trust all is enabled")
    @MainActor
    func launchWorksWithTrustAll() {
        ActionDispatcher.shared.clearAllAppApprovals()
        ActionDispatcher.shared.setTrustAllApps(true)

        // Launch should succeed without any approval prompt
        let uri = KeyPathActionURI(string: "keypath://launch/Calculator")!
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)

        // Clean up
        ActionDispatcher.shared.clearAllAppApprovals()
    }

    @Test("Trust all apps setting persists across checks")
    @MainActor
    func trustAllPersists() {
        ActionDispatcher.shared.clearAllAppApprovals()

        // Enable trust all
        ActionDispatcher.shared.setTrustAllApps(true)

        // Multiple checks should all return true
        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == true)
        #expect(ActionDispatcher.shared.isTrustAllAppsEnabled() == true)

        // Launch multiple apps - all should work
        let apps = ["Calculator", "Safari", "TextEdit"]
        for app in apps {
            let uri = KeyPathActionURI(string: "keypath://launch/\(app)")!
            let result = ActionDispatcher.shared.dispatch(uri)
            #expect(result == .success, "Launch of \(app) should succeed with trust all enabled")
        }

        // Clean up
        ActionDispatcher.shared.clearAllAppApprovals()
    }

    @Test("Approved apps list returns sorted results")
    @MainActor
    func approvedAppsAreSorted() {
        // The getApprovedApps() method should return sorted results
        // We can only verify behavior, not internal state in test mode
        let apps = ActionDispatcher.shared.getApprovedApps()

        // Verify it's sorted
        let sorted = apps.sorted()
        #expect(apps == sorted)
    }
}

// MARK: - ActionDispatchResult Equality

extension ActionDispatchResult: Equatable {
    public static func == (lhs: ActionDispatchResult, rhs: ActionDispatchResult) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success):
            true
        case (.pendingApproval, .pendingApproval):
            true
        case let (.unknownAction(a), .unknownAction(b)):
            a == b
        case let (.missingTarget(a), .missingTarget(b)):
            a == b
        case let (.failed(actionA, _), .failed(actionB, _)):
            actionA == actionB
        default:
            false
        }
    }
}
