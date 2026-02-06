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
    func dispatchesLaunchAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://launch/Calculator"))
        let result = ActionDispatcher.shared.dispatch(uri)

        // Launch returns success optimistically (async launch)
        #expect(result == .success)
    }

    @Test("Dispatch message API parses shorthand and routes")
    @MainActor
    func dispatchMessageParsesShorthand() {
        var receivedLayer: String?
        ActionDispatcher.shared.onLayerAction = { layer in
            receivedLayer = layer
        }
        defer {
            ActionDispatcher.shared.onLayerAction = nil
        }

        let result = ActionDispatcher.shared.dispatch(message: "layer:editing")
        #expect(result == .success)
        #expect(receivedLayer == "editing")
    }

    @Test("Dispatch message API returns unknownAction for invalid URI string")
    @MainActor
    func dispatchMessageInvalidString() {
        var errorMessage: String?
        ActionDispatcher.shared.onError = { message in
            errorMessage = message
        }
        defer {
            ActionDispatcher.shared.onError = nil
        }

        let invalidInput = "not-a-keypath-message"
        let result = ActionDispatcher.shared.dispatch(message: invalidInput)

        if case let .unknownAction(message) = result {
            #expect(message == invalidInput)
            #expect(errorMessage?.contains("Invalid keypath:// URI") == true)
        } else {
            Issue.record("Expected unknownAction for invalid input")
        }
    }

    @Test("Returns unknownAction for invalid action type")
    @MainActor
    func returnsUnknownActionForInvalidType() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://invalid/something"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .unknownAction(action) = result {
            #expect(action == "invalid")
        } else {
            Issue.record("Expected unknownAction result")
        }
    }

    @Test("Returns missingTarget for launch without app")
    @MainActor
    func returnsMissingTargetForLaunchWithoutApp() throws {
        // Create a URI that has launch action but no target
        // This requires constructing a URL with empty path
        let uri = try #require(KeyPathActionURI(string: "keypath://launch"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "launch")
        } else {
            Issue.record("Expected missingTarget result, got \(result)")
        }
    }

    @Test("Dispatches layer action")
    @MainActor
    func dispatchesLayerAction() throws {
        var receivedLayer: String?
        ActionDispatcher.shared.onLayerAction = { layer in
            receivedLayer = layer
        }

        let uri = try #require(KeyPathActionURI(string: "keypath://layer/nav"))
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
        #expect(receivedLayer == "nav")

        // Clean up
        ActionDispatcher.shared.onLayerAction = nil
    }

    @Test("Dispatches rule action with path")
    @MainActor
    func dispatchesRuleActionWithPath() throws {
        var receivedRule: String?
        var receivedPath: [String]?
        ActionDispatcher.shared.onRuleAction = { rule, path in
            receivedRule = rule
            receivedPath = path
        }

        let uri = try #require(KeyPathActionURI(string: "keypath://rule/caps-esc/fired"))
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
        #expect(receivedRule == "caps-esc")
        #expect(receivedPath == ["fired"])

        // Clean up
        ActionDispatcher.shared.onRuleAction = nil
    }

    @Test("Dispatches notify action")
    @MainActor
    func dispatchesNotifyAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://notify?title=Test&body=Message"))
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
    }

    @Test("Dispatches open action")
    @MainActor
    func dispatchesOpenAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://open/example.com"))
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
    }

    @Test("Dispatches fakekey action")
    @MainActor
    func dispatchesFakekeyAction() throws {
        let previous = FeatureFlags.simulatorAndVirtualKeysEnabled
        FeatureFlags.setSimulatorAndVirtualKeysEnabled(true)
        defer { FeatureFlags.setSimulatorAndVirtualKeysEnabled(previous) }

        let uri = try #require(KeyPathActionURI(string: "keypath://fakekey/test-key/tap"))
        let result = ActionDispatcher.shared.dispatch(uri)

        // Returns success optimistically (TCP call is async)
        #expect(result == .success)
    }

    @Test("Returns missingTarget for fakekey without name")
    @MainActor
    func returnsMissingTargetForFakekeyWithoutName() throws {
        let previous = FeatureFlags.simulatorAndVirtualKeysEnabled
        FeatureFlags.setSimulatorAndVirtualKeysEnabled(true)
        defer { FeatureFlags.setSimulatorAndVirtualKeysEnabled(previous) }

        let uri = try #require(KeyPathActionURI(string: "keypath://fakekey"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "fakekey")
        } else {
            Issue.record("Expected missingTarget result")
        }
    }

    @Test("Returns failed for fakekey when feature flag disabled")
    @MainActor
    func returnsFailedForFakekeyWhenFeatureDisabled() throws {
        let previous = FeatureFlags.simulatorAndVirtualKeysEnabled
        FeatureFlags.setSimulatorAndVirtualKeysEnabled(false)
        defer { FeatureFlags.setSimulatorAndVirtualKeysEnabled(previous) }

        let uri = try #require(KeyPathActionURI(string: "keypath://fakekey/test/tap"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .failed(action, _) = result {
            #expect(action == "fakekey")
        } else {
            Issue.record("Expected failed result for feature-disabled fakekey action")
        }
    }

    @Test("Calls onError callback for unknown action")
    @MainActor
    func callsOnErrorForUnknownAction() throws {
        var errorMessage: String?
        ActionDispatcher.shared.onError = { message in
            errorMessage = message
        }

        let uri = try #require(KeyPathActionURI(string: "keypath://unknown/test"))
        _ = ActionDispatcher.shared.dispatch(uri)

        #expect(errorMessage?.contains("Unknown action type") == true)

        // Clean up
        ActionDispatcher.shared.onError = nil
    }
}

@Suite("ActionDispatcher System And Window Actions")
struct ActionDispatcherSystemWindowTests {
    @Test("Returns missingTarget for system without action")
    @MainActor
    func returnsMissingTargetForSystemWithoutAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://system"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "system")
        } else {
            Issue.record("Expected missingTarget for system without action")
        }
    }

    @Test("Returns unknownAction for unknown system action")
    @MainActor
    func returnsUnknownForUnknownSystemAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://system/not-a-real-action"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .unknownAction(action) = result {
            #expect(action == "not-a-real-action")
        } else {
            Issue.record("Expected unknownAction for unknown system action")
        }
    }

    @Test("Returns missingTarget for window without action")
    @MainActor
    func returnsMissingTargetForWindowWithoutAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://window"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "window")
        } else {
            Issue.record("Expected missingTarget for window without action")
        }
    }

    @Test("Returns unknownAction for unknown window action")
    @MainActor
    func returnsUnknownForUnknownWindowAction() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://window/not-a-real-window-action"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .unknownAction(action) = result {
            #expect(action == "not-a-real-window-action")
        } else {
            Issue.record("Expected unknownAction for unknown window action")
        }
    }
}

// MARK: - Folder and Script Action Tests

@Suite("ActionDispatcher Folder Actions")
struct ActionDispatcherFolderTests {
    @Test("Parses folder URI")
    func parsesFolderURI() {
        let uri = KeyPathActionURI(string: "keypath://folder/Users/test/Downloads")

        #expect(uri != nil)
        #expect(uri?.action == "folder")
        #expect(uri?.pathComponents == ["Users", "test", "Downloads"])
    }

    @Test("Parses shorthand folder syntax")
    func parsesShorthandFolder() {
        let uri = KeyPathActionURI(string: "folder:~/Downloads")

        #expect(uri != nil)
        #expect(uri?.action == "folder")
        #expect(uri?.target == "~/Downloads")
    }

    @Test("Returns missingTarget for folder without path")
    @MainActor
    func returnsMissingTargetForFolderWithoutPath() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://folder"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "folder")
        } else {
            Issue.record("Expected missingTarget result")
        }
    }

    @Test("Returns failed for nonexistent folder")
    @MainActor
    func returnsFailedForNonexistentFolder() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://folder/nonexistent/path/12345"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .failed(action, _) = result {
            #expect(action == "folder")
        } else {
            Issue.record("Expected failed result for nonexistent folder")
        }
    }

    @Test("Successfully opens existing folder with absolute path")
    @MainActor
    func opensExistingFolder() throws {
        // Use the home directory which should always exist
        // The path is joined from components, so we need the full path
        let homePath = NSHomeDirectory()
        let uri = try #require(KeyPathActionURI(string: "folder:\(homePath)"))
        let result = ActionDispatcher.shared.dispatch(uri)

        #expect(result == .success)
    }

    @Test("Returns failed when folder target is a file")
    @MainActor
    func returnsFailedWhenFolderTargetIsFile() throws {
        let uri = try #require(KeyPathActionURI(string: "folder:/bin/bash"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .failed(action, _) = result {
            #expect(action == "folder")
        } else {
            Issue.record("Expected failed result when folder target is a file")
        }
    }
}

@Suite("ActionDispatcher Script Actions")
struct ActionDispatcherScriptTests {
    @Test("Parses script URI")
    func parsesScriptURI() {
        let uri = KeyPathActionURI(string: "keypath://script/Users/test/Scripts/backup.sh")

        #expect(uri != nil)
        #expect(uri?.action == "script")
        #expect(uri?.pathComponents == ["Users", "test", "Scripts", "backup.sh"])
    }

    @Test("Parses shorthand script syntax")
    func parsesShorthandScript() {
        let uri = KeyPathActionURI(string: "script:~/Scripts/backup.sh")

        #expect(uri != nil)
        #expect(uri?.action == "script")
        #expect(uri?.target == "~/Scripts/backup.sh")
    }

    @Test("Returns missingTarget for script without path")
    @MainActor
    func returnsMissingTargetForScriptWithoutPath() throws {
        let uri = try #require(KeyPathActionURI(string: "keypath://script"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .missingTarget(action) = result {
            #expect(action == "script")
        } else {
            Issue.record("Expected missingTarget result")
        }
    }

    @Test("Returns failed when script execution disabled")
    @MainActor
    func returnsFailedWhenDisabled() throws {
        // Ensure script execution is disabled
        ScriptSecurityService.shared.isScriptExecutionEnabled = false

        let uri = try #require(KeyPathActionURI(string: "keypath://script/some/script.sh"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .failed(action, _) = result {
            #expect(action == "script")
        } else {
            Issue.record("Expected failed result when scripts disabled")
        }
    }

    @Test("Returns failed for nonexistent script")
    @MainActor
    func returnsFailedForNonexistentScript() throws {
        // Enable script execution
        ScriptSecurityService.shared.isScriptExecutionEnabled = true
        ScriptSecurityService.shared.bypassFirstRunDialog = true
        defer {
            ScriptSecurityService.shared.isScriptExecutionEnabled = false
            ScriptSecurityService.shared.bypassFirstRunDialog = false
        }

        let uri = try #require(KeyPathActionURI(string: "keypath://script/nonexistent/path/script.sh"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .failed(action, _) = result {
            #expect(action == "script")
        } else {
            Issue.record("Expected failed result for nonexistent script")
        }
    }

    @Test("Calls confirmation callback when needed")
    @MainActor
    func callsConfirmationCallback() throws {
        // Enable script execution but require confirmation
        ScriptSecurityService.shared.isScriptExecutionEnabled = true
        ScriptSecurityService.shared.bypassFirstRunDialog = false
        defer {
            ScriptSecurityService.shared.isScriptExecutionEnabled = false
            ActionDispatcher.shared.onScriptConfirmationNeeded = nil
        }

        var confirmationRequested = false
        var requestedPath: String?

        ActionDispatcher.shared.onScriptConfirmationNeeded = { path, _, _ in
            confirmationRequested = true
            requestedPath = path
        }

        // Use /bin/bash which is always an executable that exists
        let uri = try #require(KeyPathActionURI(string: "script:/bin/bash"))
        _ = ActionDispatcher.shared.dispatch(uri)

        #expect(confirmationRequested == true)
        #expect(requestedPath == "/bin/bash")
    }

    @Test("Calls disabled callback when scripts disabled")
    @MainActor
    func callsDisabledCallback() throws {
        ScriptSecurityService.shared.isScriptExecutionEnabled = false
        defer {
            ActionDispatcher.shared.onScriptExecutionDisabled = nil
        }

        var disabledCallbackCalled = false

        ActionDispatcher.shared.onScriptExecutionDisabled = { _ in
            disabledCallbackCalled = true
        }

        let uri = try #require(KeyPathActionURI(string: "keypath://script/some/script.sh"))
        _ = ActionDispatcher.shared.dispatch(uri)

        #expect(disabledCallbackCalled == true)
    }

    @Test("Returns failed when file exists but is not executable script type")
    @MainActor
    func returnsFailedForNotExecutableScriptType() throws {
        ScriptSecurityService.shared.isScriptExecutionEnabled = true
        ScriptSecurityService.shared.bypassFirstRunDialog = true
        defer {
            ScriptSecurityService.shared.isScriptExecutionEnabled = false
            ScriptSecurityService.shared.bypassFirstRunDialog = false
        }

        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-dispatcher-not-executable-\(UUID().uuidString).txt").path
        FileManager.default.createFile(atPath: tempPath, contents: Data("plain text".utf8))
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        let uri = try #require(KeyPathActionURI(string: "script:\(tempPath)"))
        let result = ActionDispatcher.shared.dispatch(uri)

        if case let .failed(action, _) = result {
            #expect(action == "script")
        } else {
            Issue.record("Expected failed result for non-executable non-script file")
        }
    }
}

// MARK: - ActionDispatchResult Equality

extension ActionDispatchResult: Equatable {
    public static func == (lhs: ActionDispatchResult, rhs: ActionDispatchResult) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success):
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
