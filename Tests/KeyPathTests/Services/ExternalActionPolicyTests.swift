import Foundation
@testable import KeyPathAppKit
import XCTest

/// Links opened by other apps (web pages, documents, Raycast) are limited:
/// no scripts, web pages only for `open`, and virtual keys ask first.
@MainActor
final class ExternalActionPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ExternalActionPolicyTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func decision(_ string: String) throws -> ExternalActionPolicy.Decision {
        try ExternalActionPolicy.decision(for: XCTUnwrap(KeyPathActionURI(string: string)), defaults: defaults)
    }

    func testScriptsNeverRunFromLinks() throws {
        guard case .refuse = try decision("keypath://script/~/scripts/hello.sh") else {
            return XCTFail("A link must not start a script")
        }
    }

    func testOpenAllowsOnlyWebPages() throws {
        XCTAssertEqual(try decision("keypath://open/https://example.com"), .allow)
        XCTAssertEqual(try decision("keypath://open/example.com"), .allow)
        guard case .refuse = try decision("keypath://open/file:%2F%2F%2Fetc%2Fhosts") else {
            return XCTFail("file:// must be refused")
        }
        guard case .refuse = try decision("keypath://open/x-apple.systempreferences:%2F%2Fx") else {
            return XCTFail("Other app schemes must be refused")
        }
    }

    func testVirtualKeysAskUntilAlwaysAllowed() throws {
        guard case let .confirm(summary, key) = try decision("keypath://fakekey/nav-mode/tap") else {
            return XCTFail("Expected a prompt")
        }
        XCTAssertTrue(summary.contains("nav-mode"))
        defaults.set(true, forKey: key)
        XCTAssertEqual(try decision("keypath://fakekey/nav-mode/tap"), .allow)
    }

    func testEverydayActionsStayAvailable() throws {
        for uri in ["keypath://launch/Safari", "keypath://window/left", "keypath://layer/nav",
                    "keypath://settings/rules", "keypath://overlay/toggle", "keypath://notify?title=Hi"]
        {
            XCTAssertEqual(try decision(uri), .allow, uri)
        }
    }

    func testAppNamesCannotBePaths() {
        XCTAssertTrue(ExternalActionPolicy.isPlainAppName("Visual Studio Code"))
        XCTAssertTrue(ExternalActionPolicy.isPlainAppName("com.apple.Safari"))
        XCTAssertFalse(ExternalActionPolicy.isPlainAppName("../../tmp/evil"))
        XCTAssertFalse(ExternalActionPolicy.isPlainAppName("Utilities/Terminal"))
    }

    func testDispatcherRefusesScriptLinkWithoutCheckingTheScript() throws {
        let security = ScriptSecurityService(defaults: defaults, approvals: InMemoryScriptApprovalStore())
        security.isScriptExecutionEnabled = true
        let dispatcher = ActionDispatcher(scriptSecurityService: security, defaults: defaults)
        var prompted = false
        dispatcher.onScriptConfirmationNeeded = { _ in prompted = true }
        let result = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "keypath://script//bin/bash")), origin: .externalURL)
        guard case .failed = result else { return XCTFail("Expected a refusal") }
        XCTAssertFalse(prompted)
    }

    func testDispatcherAsksBeforeVirtualKeyFromLink() throws {
        let dispatcher = ActionDispatcher(defaults: defaults)
        var asked: ExternalActionConfirmation?
        dispatcher.onExternalActionConfirmationNeeded = { asked = $0 }
        _ = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "keypath://fakekey/nav/tap")), origin: .externalURL)
        let request = try XCTUnwrap(asked)
        request.deny()
        XCTAssertFalse(defaults.bool(forKey: ExternalActionPolicy.allowLinkedVirtualKeysKey))
    }

    func testDispatcherRefusesVirtualKeyLinkWhenItCannotAsk() throws {
        let dispatcher = ActionDispatcher(defaults: defaults)
        let result = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "keypath://fakekey/nav/tap")), origin: .externalURL)
        guard case .failed = result else { return XCTFail("Expected a refusal without a prompt") }
    }
}
