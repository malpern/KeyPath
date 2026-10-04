import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Exercises generated profiles through Kanata's parsed action-tree validator.
/// Supply the freshly built bridge explicitly for acceptance evidence; these tests
/// never load the installed app's library or start a capture/output runtime.
final class GeneratedSessionProfileEligibilityTests: KeyPathTestCase {
    func testOriginalBundledCatalogRequiresAdvancedBackend() throws {
        let collections = try originalCatalog()
        XCTAssertFalse(collections.isEmpty, "The actual bundled catalog must load")
        try assertEligibility(collections, expected: false)
    }

    func testFreshResetProfileIsEligible() throws {
        let resetCollections = RuleCollectionCatalog().defaultCollections().filter {
            $0.id == RuleCollectionIdentifier.macFunctionKeys
        }
        XCTAssertEqual(resetCollections.count, 1)
        try assertEligibility(resetCollections, expected: true)
    }

    func testEmptyProfileUsesSupportedKeyboardDefaults() throws {
        try assertEligibility([], expected: true)
    }

    func testSimpleCustomMappingDoesNotReceiveHiddenMediaDefaults() throws {
        let mapping = RuleCollection(
            name: "Session test mapping", summary: "q to a", category: .custom,
            mappings: [KeyMapping(input: "q", action: .keystroke(key: "a"))],
            isEnabled: true
        )
        try assertEligibility([mapping], expected: true)
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
        let caps = try XCTUnwrap(originalCatalog().first {
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

    func testFreshCatalogUsesOnlySupportedFunctionKeys() throws {
        let fresh = RuleCollectionCatalog().defaultCollections()
        XCTAssertEqual(fresh.filter(\.isEnabled).map(\.id), [RuleCollectionIdentifier.macFunctionKeys])
        try assertEligibility(fresh, expected: true)
    }

    func testUpgradingExistingProfilePreservesEnabledMediaAndCaps() throws {
        let catalog = RuleCollectionCatalog()
        let original = try originalCatalog()
        let media = try XCTUnwrap(original.first { $0.id == RuleCollectionIdentifier.macFunctionKeys })
        let caps = try XCTUnwrap(original.first { $0.id == RuleCollectionIdentifier.capsLockRemap })
        let upgradedMedia = catalog.upgradedCollection(from: media)
        let upgradedCaps = catalog.upgradedCollection(from: caps)
        XCTAssertEqual(upgradedMedia.isEnabled, media.isEnabled)
        XCTAssertEqual(upgradedMedia.mappings, media.mappings)
        XCTAssertEqual(upgradedCaps.isEnabled, caps.isEnabled)
        XCTAssertEqual(upgradedCaps.configuration, caps.configuration)
        try assertEligibility([upgradedMedia, upgradedCaps], expected: false)
    }

    @MainActor
    func testRejectedRawWritePreservesExistingConfigurationAndStores() async throws {
        let host = try bridgeRuntimeHost()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-write-rejection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let collectionsURL = directory.appendingPathComponent("RuleCollections.json")
        let rulesURL = directory.appendingPathComponent("CustomRules.json")
        let service = ConfigurationService(
            configDirectory: directory.path,
            ruleCollectionStore: .testStore(at: collectionsURL),
            customRulesStore: .testStore(at: rulesURL),
            sessionValidationRuntimeHost: host
        )
        let existing = "(defsrc q)(deflayer base a)"
        try await service.writeConfigurationContent(existing)
        let collectionBytes = Data("preserved collection snapshot".utf8)
        let ruleBytes = Data("preserved custom rule snapshot".utf8)
        try collectionBytes.write(to: collectionsURL)
        try ruleBytes.write(to: rulesURL)
        do {
            try await service.writeConfigurationContent("(defsrc caps)(deflayer base esc)")
            XCTFail("Unsupported Caps remapping must fail before writing")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("driverless session"), error.localizedDescription)
        }
        var staged = false
        service.onWillStageConfigurationWrite = { _ in staged = true }
        do {
            try await service.operationGate.withOperation { @MainActor permit in
                _ = try await service.stageRawConfiguration(
                    content: "(defsrc q)(deflayer base volu)", expectedContent: existing,
                    mutationPermit: permit
                )
            }
            XCTFail("Unsupported media output must fail before staging")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("driverless session"), error.localizedDescription)
        }
        XCTAssertFalse(staged, "Rejected candidates must not reach the staging callback")
        XCTAssertEqual(try String(contentsOfFile: service.configurationPath, encoding: .utf8), existing)
        XCTAssertEqual(try Data(contentsOf: collectionsURL), collectionBytes)
        XCTAssertEqual(try Data(contentsOf: rulesURL), ruleBytes)
    }

    private func originalCatalog() throws -> [RuleCollection] {
        let url = try XCTUnwrap(KeyPathAppKitResources.url(forResource: "rule-collection-catalog", withExtension: "json"))
        return try JSONDecoder().decode([RuleCollection].self, from: Data(contentsOf: url))
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
        let runtimeHost = try bridgeRuntimeHost()
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

    private func bridgeRuntimeHost() throws -> KanataRuntimeHost {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let explicitPath = ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"]
        let bridgePath = explicitPath ?? root
            .appendingPathComponent("build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib").path
        guard FileManager.default.fileExists(atPath: bridgePath) else {
            if explicitPath != nil {
                throw NSError(domain: "GeneratedSessionProfileEligibilityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Explicit session test bridge is missing: \(bridgePath)"])
            }
            throw XCTSkip("Build the local bridge or set KEYPATH_SESSION_TEST_BRIDGE_PATH")
        }
        return KanataRuntimeHost(
            launcherPath: "/unused/kanata-launcher", bridgeLibraryPath: bridgePath,
            bundledCorePath: "/unused/kanata", kanataEngineBundlePath: "/unused/Kanata Engine.app"
        )
    }
}
