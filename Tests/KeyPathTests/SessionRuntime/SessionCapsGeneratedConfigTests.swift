import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

final class SessionCapsGeneratedConfigTests: XCTestCase {
    func testUnsupportedMediaFunctionKeyModeIsRejected() throws {
        try SessionBridgeTestFixture.requireAvailable()
        var collection = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first {
            $0.id == RuleCollectionIdentifier.macFunctionKeys
        })
        collection.functionKeyMode = .media
        collection.mappings = RuleCollectionCatalog.functionKeyMappings(for: .media)
        let config = KanataConfiguration.generateFromCollections([collection], inputs: .empty)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("media-admission-\(UUID().uuidString).kbd")
        defer { try? FileManager.default.removeItem(at: path) }
        try config.write(to: path, atomically: true, encoding: .utf8)
        let admission = SessionCapsRuntimeSupport.validate(
            configPath: path.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, requireSelection: false
        )
        XCTAssertFalse(FunctionKeyMode.media.isSupportedInDriverlessSession)
        if case .valid = admission.result { XCTFail("Unsupported media output must remain rejected") }
    }

    @MainActor
    func testEveryBuiltInDefaultWithLeaderIsAdmitted() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let catalog = RuleCollectionCatalog().defaultCollections()
        XCTAssertEqual(catalog.count, 22, "Review new catalog entries for driverless support")
        for candidate in catalog {
            var collections = catalog
            for index in collections.indices {
                collections[index].isEnabled = collections[index].id == candidate.id
                    || collections[index].id == RuleCollectionIdentifier.macFunctionKeys
                    || collections[index].name == "Leader Key"
            }
            let config = KanataConfiguration.generateFromCollections(collections, inputs: .empty)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-admission-\(UUID().uuidString).kbd")
            defer { try? FileManager.default.removeItem(at: path) }
            try config.write(to: path, atomically: true, encoding: .utf8)
            let admission = SessionCapsRuntimeSupport.validate(
                configPath: path.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, requireSelection: false
            )
            if let reason = RuleCollectionCatalog.driverlessUnavailableReason(for: candidate.id) {
                XCTAssertEqual(candidate.id, RuleCollectionIdentifier.funLayer)
                XCTAssertTrue(reason.contains("which the current backend can't send"), reason)
                if case .valid = admission.result { XCTFail("Review support policy: previously unsupported collection now validates") }
            } else if case .valid = admission.result {
                // Every offered default must be admitted by the real bridge.
            } else {
                XCTFail("\(candidate.name) default refused: \(admission.result)")
            }
        }
    }

    func testEveryOfferedSystemActionIsAdmitted() throws {
        try SessionBridgeTestFixture.requireAvailable()
        for action in SystemActionInfo.allActions {
            let config = "(defsrc a)(deflayer base \(action.kanataOutput))"
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("action-\(UUID().uuidString).kbd")
            defer { try? FileManager.default.removeItem(at: path) }
            try config.write(to: path, atomically: true, encoding: .utf8)
            let admission = SessionCapsRuntimeSupport.validate(configPath: path.path,
                                                               runtimeHost: SessionBridgeTestFixture.runtimeHost, requireSelection: false)
            if case .valid = admission.result {
                XCTAssertTrue(action.isSupportedInDriverlessSession, action.id)
            } else {
                XCTAssertFalse(action.isSupportedInDriverlessSession, "Offered action \(action.id) was rejected: \(admission.result)")
            }
        }
    }

    func testHomeRowArrowsWithCapsAndLauncherIsAdmitted() throws {
        guard let bridge = ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"] else {
            throw XCTSkip("Requires the real parsed session bridge")
        }
        let catalog = RuleCollectionCatalog().defaultCollections()
        let names = ["Caps Lock Remap", "Home Row Arrows", "Quick Launcher"]
        var collections = catalog
        for index in collections.indices where names.contains(collections[index].name) {
            collections[index].isEnabled = true
        }
        XCTAssertEqual(collections.filter { names.contains($0.name) && $0.isEnabled }.count, 3)
        let config = KanataConfiguration.generateFromCollections(collections, inputs: .empty)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-arrows-caps-\(UUID().uuidString).kbd")
        defer { try? FileManager.default.removeItem(at: path) }
        try config.write(to: path, atomically: true, encoding: .utf8)
        let current = KanataRuntimeHost.current()
        let host = KanataRuntimeHost(launcherPath: current.launcherPath, bridgeLibraryPath: bridge,
                                     bundledCorePath: current.bundledCorePath, kanataEngineBundlePath: current.kanataEngineBundlePath)
        let admission = SessionCapsRuntimeSupport.validate(configPath: path.path, runtimeHost: host, requireSelection: false)
        guard case .valid = admission.result else {
            XCTFail("Home Row Arrows plus Caps and Launcher refused: \(admission.result)\n\(config)")
            return
        }
    }

    func testFreshProfileGeneratedCapsRemapIsAdmitted() throws {
        guard let bridge = ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"] else {
            throw XCTSkip("Requires the real parsed session bridge")
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-generated-caps-\(UUID().uuidString).kbd")
        defer { try? FileManager.default.removeItem(at: path) }
        let custom = [RuleCollection].collection(named: "Caps", mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))])
        let config = KanataConfiguration.generateFromCollections(custom + RuleCollectionCatalog().defaultCollections(), inputs: KanataGenerationInputs(leaderKeyPreference: .default))
        try config.write(to: path, atomically: true, encoding: .utf8)
        let current = KanataRuntimeHost.current()
        let host = KanataRuntimeHost(launcherPath: current.launcherPath, bridgeLibraryPath: bridge,
                                     bundledCorePath: current.bundledCorePath, kanataEngineBundlePath: current.kanataEngineBundlePath)
        let admission = SessionCapsRuntimeSupport.validate(configPath: path.path, runtimeHost: host, requireSelection: false)
        guard case .valid = admission.result else {
            XCTFail("Generated Caps remap was refused: \(admission.result)\n\(config)")
            return
        }
        XCTAssertTrue(admission.managedCaps)
    }

    func testCapsRemapCoexistsWithOrdinaryCustomLayer() throws {
        guard let bridge = ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"] else {
            throw XCTSkip("Requires the real parsed session bridge")
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-caps-layer-\(UUID().uuidString).kbd")
        defer { try? FileManager.default.removeItem(at: path) }
        let caps = RuleCollection(
            name: "Caps to Escape", summary: "Caps to Escape", category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))], isEnabled: true
        )
        let navigation = RuleCollection(
            name: "Custom navigation", summary: "Hold space for arrows", category: .custom,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))], isEnabled: true,
            targetLayer: .custom("arrows"),
            momentaryActivator: MomentaryActivator(input: "spc", targetLayer: .custom("arrows"))
        )
        let config = KanataConfiguration.generateFromCollections([caps, navigation], inputs: .empty)
        XCTAssertTrue(config.contains("(deflayer arrows"), "The layer must actually be generated")
        try config.write(to: path, atomically: true, encoding: .utf8)
        let current = KanataRuntimeHost.current()
        let host = KanataRuntimeHost(launcherPath: current.launcherPath, bridgeLibraryPath: bridge,
                                     bundledCorePath: current.bundledCorePath, kanataEngineBundlePath: current.kanataEngineBundlePath)
        let admission = SessionCapsRuntimeSupport.validate(configPath: path.path, runtimeHost: host, requireSelection: false)
        guard case .valid = admission.result else {
            XCTFail("Caps plus a custom layer was refused: \(admission.result)\n\(config)")
            return
        }
        XCTAssertTrue(admission.managedCaps)
    }
}
