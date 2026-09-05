import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class SimpleModsSaveTests: KeyPathTestCase {
    private struct Fixture {
        let url: URL
        let original: String
        let coordinator: SaveCoordinator
    }

    func testRejectedReloadRestoresFileAndEditorState() async throws {
        try await withFixture { fixture in
            var reloads = 0
            let service = SimpleModsService(configPath: fixture.url.path) { transform in
                await fixture.coordinator.editConfiguration(transform: transform) {
                    reloads += 1
                    XCTAssertTrue((try? String(contentsOf: fixture.url, encoding: .utf8))?.contains("f1 f2") == true)
                    return Self.reload(.rejected)
                }
            }
            try service.load()
            service.addMapping(fromKey: "f1", toKey: "f2")
            await service.flushPendingApplyForTesting()
            XCTAssertEqual(reloads, 1)
            XCTAssertEqual(try String(contentsOf: fixture.url, encoding: .utf8), fixture.original)
            XCTAssertFalse(service.installedMappings.contains { $0.fromKey == "f1" })
            XCTAssertNotNil(service.lastError)
            XCTAssertNotNil(service.lastRollbackReason)
            XCTAssertTrue(service.lastRollbackDetails?.contains("previous configuration file was restored") == true)
            XCTAssertEqual(service.lastSaveResult?.reloadResult?.disposition, .rejected)
        }
    }

    func testPendingReloadIsRetainedAsPersisted() async throws {
        try await withFixture { fixture in
            let service = SimpleModsService(configPath: fixture.url.path) { transform in
                await fixture.coordinator.editConfiguration(transform: transform) { Self.reload(.pending) }
            }
            try service.load()
            service.addMapping(fromKey: "f1", toKey: "f2")
            await service.flushPendingApplyForTesting()
            XCTAssertNil(service.lastError)
            XCTAssertEqual(service.lastSaveResult?.reloadResult?.disposition, .pending)
            XCTAssertTrue(try String(contentsOf: fixture.url, encoding: .utf8).contains("f1 f2"))
        }
    }

    func testExternalRevisionIsNotOverwrittenByStaleEditorState() async throws {
        try await withFixture { fixture in
            let service = SimpleModsService(configPath: fixture.url.path) { transform in
                await fixture.coordinator.editConfiguration(transform: transform) {
                    XCTFail("Stale edit must not reach runtime")
                    return Self.reload(.applied)
                }
            }
            try service.load()
            let external = fixture.original + "\n;; external change\n"
            try external.write(to: fixture.url, atomically: true, encoding: .utf8)
            service.addMapping(fromKey: "f1", toKey: "f2")
            await service.flushPendingApplyForTesting()
            XCTAssertEqual(try String(contentsOf: fixture.url, encoding: .utf8), external)
            XCTAssertNotNil(service.lastError)
        }
    }

    func testExternalEditAfterTransformIsPreserved() async throws {
        try await withFixture { fixture in
            let external = fixture.original + "\n;; external during preparation\n"
            let result = await fixture.coordinator.editConfiguration(transform: { source in
                try external.write(to: fixture.url, atomically: true, encoding: .utf8)
                return source + "\n;; proposed edit\n"
            }) {
                XCTFail("Changed source must not reach runtime")
                return Self.reload(.applied)
            }
            XCTAssertFalse(result.success)
            XCTAssertEqual(try String(contentsOf: fixture.url, encoding: .utf8), external)
        }
    }

    func testNewerEditWaitsForPreviousSaveWithoutLosingMappings() async throws {
        try await withFixture { fixture in
            let started = expectation(description: "first reload suspended")
            var continuation: CheckedContinuation<Void, Never>?
            var reloads = 0
            let service = SimpleModsService(configPath: fixture.url.path) { transform in
                await fixture.coordinator.editConfiguration(transform: transform) {
                    reloads += 1
                    if reloads == 1 {
                        await withCheckedContinuation { next in
                            continuation = next
                            started.fulfill()
                        }
                    }
                    return Self.reload(.applied)
                }
            }
            try service.load()
            service.addMapping(fromKey: "f1", toKey: "f2")
            let first = Task { await service.flushPendingApplyForTesting() }
            await fulfillment(of: [started], timeout: 5)
            service.addMapping(fromKey: "f3", toKey: "f4")
            let second = Task { await service.flushPendingApplyForTesting() }
            continuation?.resume()
            await first.value
            await second.value
            XCTAssertNil(service.lastError)
            XCTAssertEqual(reloads, 2)
            let content = try String(contentsOf: fixture.url, encoding: .utf8)
            XCTAssertTrue(content.contains("f1 f2"))
            XCTAssertTrue(content.contains("f3 f4"))
        }
    }

    func testRemovingLastMappingKeepsAValidLayerStructure() async throws {
        try await withFixture { fixture in
            let service = SimpleModsService(configPath: fixture.url.path) { transform in
                await fixture.coordinator.editConfiguration(transform: transform) { Self.reload(.applied) }
            }
            try service.load()
            service.addMapping(fromKey: "f1", toKey: "f2")
            await service.flushPendingApplyForTesting()
            let id = try XCTUnwrap(service.installedMappings.first?.id)
            service.removeMapping(id: id)
            await service.flushPendingApplyForTesting()
            XCTAssertNil(service.lastError)
            XCTAssertTrue(service.installedMappings.isEmpty)
            let content = try String(contentsOf: fixture.url, encoding: .utf8)
            XCTAssertTrue(content.contains("(deflayermap (base)"))
            XCTAssertFalse(content.contains("f1 f2"))
        }
    }

    func testAppliedRuntimeRefreshDoesNotInheritCancellation() async throws {
        try await withFixture { fixture in
            var refreshed = false
            let task = Task {
                await fixture.coordinator.editConfiguration(transform: { $0 }, runtimeDidApply: {
                    XCTAssertFalse(Task.isCancelled)
                    refreshed = true
                }) {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return Self.reload(.applied)
                }
            }
            let result = await task.value
            XCTAssertTrue(result.success)
            XCTAssertTrue(refreshed)
        }
    }

    func testRecoveryFailureDoesNotClaimRollbackSucceeded() async throws {
        try await withFixture { fixture in
            let service = SimpleModsService(configPath: fixture.url.path) { _ in
                .failure(NSError(domain: "save", code: 1, userInfo: [NSLocalizedDescriptionKey: "save rejected"]),
                         recoveryResult: .failed(
                             backupError: NSError(domain: "backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "backup unavailable"]),
                             fallbackError: NSError(domain: "fallback", code: 3, userInfo: [NSLocalizedDescriptionKey: "fallback unavailable"])
                         ))
            }
            try service.load()
            service.addMapping(fromKey: "f1", toKey: "f2")
            await service.flushPendingApplyForTesting()
            XCTAssertNil(service.lastRollbackReason)
            XCTAssertTrue(service.lastError?.contains("backup unavailable") == true)
            XCTAssertTrue(service.lastError?.contains("fallback unavailable") == true)
        }
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: disposition == .rejected ? "rejected" : nil, protocol: nil, disposition: disposition)
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simple-mods-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
        }
        let url = directory.appendingPathComponent("keypath.kbd")
        let original = "(defcfg)\n(defsrc f1 f3)\n;; KP:BEGIN simple_mods id=fixture version=1\n(deflayermap (base)\n)\n;; KP:END id=fixture\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let service = ConfigurationService(configDirectory: directory.path,
                                           ruleCollectionStore: .testStore(at: directory.appendingPathComponent("RuleCollections.json")),
                                           customRulesStore: .testStore(at: directory.appendingPathComponent("CustomRules.json")))
        try await body(Fixture(url: url, original: original, coordinator: SaveCoordinator(configurationService: service, engineClient: TCPEngineClient())))
    }
}
