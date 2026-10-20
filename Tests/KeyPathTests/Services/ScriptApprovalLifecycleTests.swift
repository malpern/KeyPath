import Foundation
@testable import KeyPathAppKit
import XCTest

@MainActor
final class ScriptApprovalLifecycleTests: XCTestCase {
    func testDisablingScriptsRevokesPendingConfirmation() async throws {
        try await withFixture { dispatcher, security, path, executed in
            var confirm: (() -> Void)?
            var errors: [String] = []
            dispatcher.onScriptConfirmationNeeded = { _, approve, _ in confirm = approve }
            dispatcher.onError = { errors.append($0) }
            _ = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "script:" + path)))
            let approve = try XCTUnwrap(confirm)
            security.isScriptExecutionEnabled = false
            approve()
            await dispatcher.scriptTask?.value
            XCTAssertTrue(executed.paths.isEmpty)
            XCTAssertTrue(errors.contains(where: { $0.contains("disabled") }))
        }
    }

    func testDeletedScriptCannotUsePendingConfirmation() async throws {
        try await withFixture { dispatcher, _, path, executed in
            var confirm: (() -> Void)?
            dispatcher.onScriptConfirmationNeeded = { _, approve, _ in confirm = approve }
            _ = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "script:" + path)))
            try FileManager.default.removeItem(atPath: path)
            try XCTUnwrap(confirm)()
            await dispatcher.scriptTask?.value
            XCTAssertTrue(executed.paths.isEmpty)
        }
    }

    func testApprovedScriptExecutesOnceWithoutAnotherDialog() async throws {
        try await withFixture { dispatcher, _, path, executed in
            var confirm: (() -> Void)?
            var prompts = 0
            dispatcher.onScriptConfirmationNeeded = { _, approve, _ in prompts += 1; confirm = approve }
            _ = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "script:" + path)))
            try XCTUnwrap(confirm)()
            await dispatcher.scriptTask?.value
            XCTAssertEqual(prompts, 1)
            XCTAssertEqual(executed.paths, [path])
        }
    }

    func testCancelledScriptDoesNotExecute() async throws {
        try await withFixture { dispatcher, _, path, executed in
            dispatcher.onScriptConfirmationNeeded = { _, _, cancel in cancel() }
            _ = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "script:" + path)))
            await dispatcher.scriptTask?.value
            XCTAssertTrue(executed.paths.isEmpty)
        }
    }

    func testMissingConfirmationHandlerReportsFailure() async throws {
        try await withFixture { dispatcher, _, path, executed in
            let result = try dispatcher.dispatch(XCTUnwrap(KeyPathActionURI(string: "script:" + path)))
            if case .failed = result {} else { XCTFail("No approval UI cannot be reported as success") }
            XCTAssertTrue(executed.paths.isEmpty)
        }
    }

    private final class Executed { var paths: [String] = [] }

    private func withFixture(_ body: (ActionDispatcher, ScriptSecurityService, String, Executed) async throws -> Void) async throws {
        let suite = "ScriptApprovalLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("approval-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        let security = ScriptSecurityService(defaults: defaults)
        security.isScriptExecutionEnabled = true
        security.bypassFirstRunDialog = false
        let executed = Executed()
        let dispatcher = ActionDispatcher(scriptSecurityService: security, scriptExecutor: { executed.paths.append($0) })
        try await body(dispatcher, security, script.path, executed)
    }
}
