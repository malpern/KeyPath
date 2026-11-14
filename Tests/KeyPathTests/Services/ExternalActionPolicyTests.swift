import Foundation
@testable import KeyPathAppKit
import XCTest

/// Links opened by other apps (web pages, documents, Raycast) are limited:
/// no scripts, web pages only for `open`, and virtual keys ask first.
@MainActor
final class ExternalActionPolicyTests: XCTestCase {
    private func decision(_ string: String, allowsVirtualKeys: Bool = false) throws -> ExternalActionPolicy.Decision {
        try ExternalActionPolicy.decision(for: XCTUnwrap(KeyPathActionURI(string: string)), allowsVirtualKeys: allowsVirtualKeys)
    }

    private func uri(_ string: String) throws -> KeyPathActionURI {
        try XCTUnwrap(KeyPathActionURI(string: string))
    }

    func testScriptsNeverRunFromLinks() throws {
        guard case .refuse = try decision("keypath://script/~/scripts/hello.sh") else {
            return XCTFail("A link must not start a script")
        }
    }

    func testOpenAllowsOnlyWebPages() throws {
        XCTAssertEqual(try decision("keypath://open/https:%2F%2Fexample.com"), .allow)
        XCTAssertEqual(try decision("keypath://open/example.com"), .allow)
        guard case .refuse = try decision("keypath://open/file:%2F%2F%2Fetc%2Fhosts") else {
            return XCTFail("file:// must be refused")
        }
        guard case .refuse = try decision("keypath://open/x-apple.systempreferences:%2F%2Fx") else {
            return XCTFail("Other app schemes must be refused")
        }
    }

    func testVirtualKeysAskUnlessAlwaysAllowed() throws {
        XCTAssertEqual(try decision("keypath://fakekey/nav-mode/tap"), .confirmVirtualKey(name: "nav-mode"))
        XCTAssertEqual(try decision("keypath://vkey/nav-mode/tap"), .confirmVirtualKey(name: "nav-mode"))
        XCTAssertEqual(try decision("keypath://fakekey/nav-mode/tap", allowsVirtualKeys: true), .allow)
    }

    func testEverydayActionsStayAvailable() throws {
        for uri in ["keypath://launch/Safari", "keypath://window/left", "keypath://layer/nav",
                    "keypath://settings/rules", "keypath://overlay/toggle", "keypath://notify?title=Hi",
                    "keypath://folder/~/Downloads", "keypath://runtime/stop", "keypath://system/mission-control"]
        {
            XCTAssertEqual(try decision(uri), .allow, uri)
        }
    }

    func testAppNamesCannotBePaths() {
        XCTAssertTrue(ExternalActionPolicy.isPlainAppName("Visual Studio Code"))
        XCTAssertTrue(ExternalActionPolicy.isPlainAppName("com.apple.Safari"))
        XCTAssertTrue(ExternalActionPolicy.isPlainAppName("Foo..Bar"))
        XCTAssertFalse(ExternalActionPolicy.isPlainAppName("../../tmp/evil"))
        XCTAssertFalse(ExternalActionPolicy.isPlainAppName(".."))
        XCTAssertFalse(ExternalActionPolicy.isPlainAppName("Utilities/Terminal"))
    }

    // MARK: - Dispatcher

    private func makeFixture() throws -> (ActionDispatcher, ScriptSecurityService, InMemoryLinkGrantStore, () -> Void) {
        let suite = "ExternalActionPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let security = ScriptSecurityService(defaults: defaults, approvals: InMemoryScriptApprovalStore())
        security.isScriptExecutionEnabled = true
        let grants = InMemoryLinkGrantStore()
        let dispatcher = ActionDispatcher(scriptSecurityService: security, scriptExecutor: { _ in }, linkGrants: grants)
        return (dispatcher, security, grants, { defaults.removePersistentDomain(forName: suite) })
    }

    func testDispatcherRefusesScriptLinkWithoutAsking() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        var prompted = false
        dispatcher.onScriptConfirmationNeeded = { _ in prompted = true }
        guard case .failed = try dispatcher.dispatch(uri("keypath://script//bin/bash"), origin: .externalURL) else {
            return XCTFail("Expected a refusal")
        }
        XCTAssertFalse(prompted)
    }

    func testDispatcherRefusesNonWebOpenFromLink() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        guard case .failed = try dispatcher.dispatch(uri("keypath://open/file:%2F%2F%2Fetc%2Fhosts"), origin: .externalURL) else {
            return XCTFail("Expected a refusal")
        }
    }

    func testScriptsFromConfigUIAndShortcutsStillAsk() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        var prompts = 0
        dispatcher.onScriptConfirmationNeeded = { prompts += 1; $0.cancel() }
        for origin in [ActionOrigin.engine, .app, .shortcut] {
            _ = try dispatcher.dispatch(uri("script:/bin/bash"), origin: origin)
        }
        XCTAssertEqual(prompts, 3, "Only links from other apps are refused; other origins reach the script prompt")
    }

    func testDispatcherAsksBeforeVirtualKeyFromLink() throws {
        let (dispatcher, _, grants, cleanup) = try makeFixture()
        defer { cleanup() }
        var asked: ExternalActionConfirmation?
        dispatcher.onExternalActionConfirmationNeeded = { asked = $0 }
        _ = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .externalURL)
        let request = try XCTUnwrap(asked)
        XCTAssertEqual(request.virtualKey, "nav")
        request.deny()
        XCTAssertFalse(grants.allowsVirtualKeys)
    }

    func testVirtualKeyFromConfigDoesNotAsk() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        var asked = false
        dispatcher.onExternalActionConfirmationNeeded = { _ in asked = true }
        _ = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .engine)
        XCTAssertFalse(asked)
    }

    func testDispatcherRefusesVirtualKeyLinkWhenItCannotAsk() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        guard case .failed = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .externalURL) else {
            return XCTFail("Expected a refusal without a prompt")
        }
    }

    func testAlwaysAllowLetsLaterLinksPressVirtualKeysWithoutAsking() throws {
        let (dispatcher, _, grants, cleanup) = try makeFixture()
        defer { cleanup() }
        var prompts = 0
        dispatcher.onExternalActionConfirmationNeeded = { prompts += 1; $0.alwaysAllow() }
        _ = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .externalURL)
        XCTAssertTrue(grants.allowsVirtualKeys)
        _ = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .externalURL)
        XCTAssertEqual(prompts, 1)
    }

    func testFailedAlwaysAllowStillAsksNextTime() throws {
        final class RefusingGrants: LinkGrantStore {
            var allowsVirtualKeys: Bool {
                false
            }

            func setAllowsVirtualKeys(_: Bool) -> Bool {
                false
            }
        }
        let dispatcher = ActionDispatcher(linkGrants: RefusingGrants())
        var errors: [String] = []
        var prompts = 0
        dispatcher.onError = { errors.append($0) }
        dispatcher.onExternalActionConfirmationNeeded = { prompts += 1; $0.alwaysAllow() }
        _ = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .externalURL)
        _ = try dispatcher.dispatch(uri("keypath://fakekey/nav/tap"), origin: .externalURL)
        XCTAssertEqual(prompts, 2)
        XCTAssertTrue(errors.contains(where: { $0.contains("couldn't save") }))
    }

    func testDispatcherRefusesLaunchPathFromAnyOrigin() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        for origin in [ActionOrigin.externalURL, .engine] {
            guard case .failed = try dispatcher.dispatch(uri("keypath://launch/..%2F..%2Ftmp%2Fevil"), origin: origin) else {
                return XCTFail("A path must not be launched (\(origin))")
            }
        }
    }

    func testLaunchPathFromLinkIsRefused() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        guard case .failed = try dispatcher.dispatch(uri("keypath://launch/..%2Ftmp%2Fevil"), origin: .externalURL) else {
            return XCTFail("A path from a link must not be launched")
        }
    }

    func testMixedCaseScriptLinkIsNotRun() throws {
        let (dispatcher, _, _, cleanup) = try makeFixture()
        defer { cleanup() }
        var prompted = false
        dispatcher.onScriptConfirmationNeeded = { _ in prompted = true }
        let result = try dispatcher.dispatch(uri("keypath://Script//bin/bash"), origin: .externalURL)
        guard case .unknownAction = result else { return XCTFail("Only exact action names route") }
        XCTAssertFalse(prompted)
    }
}
