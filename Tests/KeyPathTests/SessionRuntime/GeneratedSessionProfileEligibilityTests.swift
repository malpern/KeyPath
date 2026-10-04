import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Exercises generated profiles through Kanata's parsed action-tree validator.
/// Supply the freshly built bridge explicitly for acceptance evidence; these tests
/// never load the installed app's library or start a capture/output runtime.
final class GeneratedSessionProfileEligibilityTests: XCTestCase {
    func testActualDefaultCatalogRequiresAdvancedBackend() throws {
        let collections = RuleCollectionCatalog().defaultCollections()
        XCTAssertFalse(collections.isEmpty, "The actual bundled catalog must load")
        try assertEligibility(collections, expected: false)
    }

    func testResetProfileStillRequiresAdvancedBackend() throws {
        let resetCollections = RuleCollectionCatalog().defaultCollections().filter {
            $0.id == RuleCollectionIdentifier.macFunctionKeys
        }
        XCTAssertEqual(resetCollections.count, 1)
        try assertEligibility(resetCollections, expected: false)
    }

    func testEmptyProfileStillGeneratesUnsupportedMediaDefaults() throws {
        try assertEligibility([], expected: false)
    }

    func testSimpleCustomMappingStillReceivesUnsupportedMediaDefaults() throws {
        let mapping = RuleCollection(
            name: "Session test mapping", summary: "q to a", category: .custom,
            mappings: [KeyMapping(input: "q", action: .keystroke(key: "a"))],
            isEnabled: true
        )
        try assertEligibility([mapping], expected: false)
    }

    func testExplicitFunctionKeyProfileIsEligible() throws {
        try assertEligibility([functionKeys()], expected: true)
    }

    func testSimpleMappingWithExplicitFunctionKeysIsEligible() throws {
        let mapping = RuleCollection(
            name: "Session test mapping", summary: "q to a", category: .custom,
            mappings: [KeyMapping(input: "q", action: .keystroke(key: "a"))],
            isEnabled: true
        )
        try assertEligibility([functionKeys(), mapping], expected: true)
    }

    func testCapsRemapRemainsRejectedWithSupportedFunctionOutputs() throws {
        let caps = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        })
        XCTAssertTrue(caps.isEnabled)
        try assertEligibility([functionKeys(), caps], expected: false)
    }

    func testGeneratedVirtualHIDExclusionRequiresAdvancedBackend() throws {
        let virtualDevice = ConnectedDevice(
            hash: "session-test-virtual", vendorID: 1, productID: 1,
            productKey: "Session Test VirtualHID", isVirtualHID: true
        )
        let inputs = KanataGenerationInputs(
            deviceGenerationInput: DeviceGenerationInput(
                selections: [], connectedDevices: [virtualDevice]
            )
        )
        let config = KanataConfiguration.generateFromCollections([functionKeys()], inputs: inputs)
        XCTAssertTrue(config.contains("macos-dev-names-exclude"))
        try assertEligibility(config, expected: false)
    }

    private func functionKeys() -> RuleCollection {
        var collection = KanataConfiguration.systemDefaultCollections[0]
        collection.mappings = RuleCollectionCatalog.functionKeyMappings(for: .function)
        collection.functionKeyMode = .function
        return collection
    }

    private func assertEligibility(
        _ collections: [RuleCollection], expected: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let config = KanataConfiguration.generateFromCollections(collections, inputs: .empty)
        try assertEligibility(config, expected: expected, file: file, line: line)
    }

    private func assertEligibility(
        _ config: String, expected: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let explicitPath = ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"]
        let bridgePath = explicitPath ?? root
            .appendingPathComponent("build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib").path
        guard FileManager.default.fileExists(atPath: bridgePath) else {
            if explicitPath != nil {
                XCTFail("Explicit session test bridge is missing: \(bridgePath)", file: file, line: line)
                return
            }
            throw XCTSkip("Build the local bridge or set KEYPATH_SESSION_TEST_BRIDGE_PATH")
        }
        let runtimeHost = KanataRuntimeHost(
            launcherPath: "/unused/kanata-launcher", bridgeLibraryPath: bridgePath,
            bundledCorePath: "/unused/kanata", kanataEngineBundlePath: "/unused/Kanata Engine.app"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("generated-session-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("keypath.kbd")
        try config.write(to: path, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            KanataHostBridge.validateConfig(runtimeHost: runtimeHost, configPath: path.path),
            .valid, "Eligibility must be tested on a valid generated Kanata config", file: file, line: line
        )
        // Match SessionRuntimeWorker and ConfigReloadCoordinator exactly. Caps Lock
        // has a translation entry but cannot be safely captured/remapped by session.
        let usages = SessionKeyMap.keyCodeToUsage.values.filter { $0 != 57 }.sorted()
        let result = KanataHostBridge.validateSessionConfig(
            runtimeHost: runtimeHost, configPath: path.path, supportedUsages: usages
        )
        if expected {
            XCTAssertEqual(result, .valid, file: file, line: line)
        } else if case let .invalid(reason) = result {
            XCTAssertTrue(reason.contains("advanced driver backend"), reason, file: file, line: line)
        } else {
            XCTFail("Expected semantic rejection, received \(result)", file: file, line: line)
        }
    }
}
