@testable import KeyPathAppKit
import XCTest

final class DeviceSwitchConfigTests: XCTestCase {
    private let device0 = ConnectedDevice(
        hash: "0xAAAA0000",
        vendorID: 0x1234,
        productID: 0x5678,
        productKey: "External Keyboard",
        isVirtualHID: false
    )
    private let device1 = ConnectedDevice(
        hash: "0xBBBB1111",
        vendorID: 0x2345,
        productID: 0x6789,
        productKey: "Apple Internal Keyboard",
        isVirtualHID: false
    )

    // MARK: - renderDeviceSwitchExpression Tests

    func testKeyMappingDefaultsToNilDeviceOverrides() {
        let mapping = KeyMapping(input: "a", output: "b")
        XCTAssertNil(mapping.deviceOverrides)
    }

    func testKeyWithDeviceOverrides_EmitsSwitchExpression() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "x"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "b",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        assertContains(result, "(switch")
        assertContains(result, "((device 0)) x break")
        assertContains(result, "() b break")
    }

    func testDeviceOverrideWithUnknownHash_SkipsCase() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xDEADBEEF", output: "z"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        // Unknown hash should be skipped — only default case present
        XCTAssertFalse(result.contains("((device"), "Unknown device hash should be skipped")
        assertContains(result, "() a break")
    }

    func testMultipleDeviceOverrides_PreservesInputOrder() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xBBBB1111", output: "y"),
            DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "x"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        // Overrides should appear in the order they are provided,
        // but each should resolve to the correct device index
        let device1Pos = result.range(of: "((device 1)) y break")
        let device0Pos = result.range(of: "((device 0)) x break")
        XCTAssertNotNil(device1Pos, "Device 1 override should be present")
        XCTAssertNotNil(device0Pos, "Device 0 override should be present")

        // Override for device hash "0xBBBB1111" (index 1) comes first in the overrides array
        XCTAssertTrue(device1Pos!.lowerBound < device0Pos!.lowerBound,
                       "Overrides should appear in input order")
    }

    func testDefaultFallthroughAlwaysPresent() {
        // Even with no overrides at all, default is present
        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "caps",
            overrides: [],
            connectedDevices: [device0],
            inputKey: "caps"
        )

        assertContains(result, "() caps break")
    }

    func testDeviceSwitchAliasName_SanitizesSpecialCharacters() {
        let mapping = KeyMapping(input: "caps-lock", output: "esc")
        XCTAssertEqual(
            KanataConfiguration.deviceSwitchAliasName(for: mapping, layer: .base),
            "dev_base_caps_lock"
        )

        // Characters beyond `-` and ` ` should also be sanitized
        let mappingWithSpecial = KeyMapping(input: "key.name+extra", output: "esc")
        XCTAssertEqual(
            KanataConfiguration.deviceSwitchAliasName(for: mappingWithSpecial, layer: .base),
            "dev_base_key_name_extra"
        )
    }

    // MARK: - Behavior Override Tests

    func testDeviceOverrideWithDualRole_RendersTapHold() {
        let behavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: "a",
            holdAction: "lctl"
        ))
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "a", behavior: behavior),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "b",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        assertContains(result, "(switch")
        assertContains(result, "(tap-hold")
        assertContains(result, "lctl")
        assertContains(result, "((device 0))")
        assertContains(result, "() b break")
    }

    func testDeviceOverrideWithMacro_RendersMacro() {
        let behavior = MappingBehavior.macro(MacroBehavior(
            outputs: ["M-c", "v"]
        ))
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xBBBB1111", output: "a", behavior: behavior),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        assertContains(result, "(macro")
        assertContains(result, "((device 1))")
        assertContains(result, "() a break")
    }

    func testDeviceOverrideMixedBehaviorAndSimple() {
        // One device gets a tap-hold, another gets a simple remap
        let overrides = [
            DeviceKeyOverride(
                deviceHash: "0xAAAA0000",
                output: "esc",
                behavior: .dualRole(DualRoleBehavior(tapAction: "esc", holdAction: "lctl"))
            ),
            DeviceKeyOverride(deviceHash: "0xBBBB1111", output: "caps"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        assertContains(result, "((device 0)) (tap-hold")
        assertContains(result, "((device 1)) caps break")
        assertContains(result, "() a break")
    }

    func testAllOverridesUnresolvable_EmitsOnlyDefault() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xDEAD0001", output: "x"),
            DeviceKeyOverride(deviceHash: "0xDEAD0002", output: "y"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1],
            inputKey: "a"
        )

        XCTAssertFalse(result.contains("((device"), "No device cases should be present")
        assertContains(result, "() a break")
    }

    // MARK: - Full Config Snapshot Tests

    func testFullConfigWithDeviceOverrides_ContainsSwitchBlock() {
        let cache = DeviceSelectionCache.shared
        cache.updateConnectedDevices([device0, device1])
        defer { cache.reset() }

        let mapping = KeyMapping(
            input: "a",
            output: "b",
            deviceOverrides: [
                DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "x"),
                DeviceKeyOverride(deviceHash: "0xBBBB1111", output: "y"),
            ]
        )

        let collection = RuleCollection(
            name: "Custom Remaps",
            summary: "Test",
            category: .productivity,
            mappings: [mapping]
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        // The full config should contain the device switch alias definition
        assertContains(config, "dev_base_a")
        assertContains(config, "(switch")
        assertContains(config, "((device 0)) x break")
        assertContains(config, "((device 1)) y break")
        assertContains(config, "() b break")
        // The deflayer should reference the alias
        assertContains(config, "@dev_base_a")
    }

    func testFullConfigWithDeviceOverrides_OnNavLayer() {
        let cache = DeviceSelectionCache.shared
        cache.updateConnectedDevices([device0, device1])
        defer { cache.reset() }

        let mapping = KeyMapping(
            input: "h",
            output: "left",
            deviceOverrides: [
                DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "home"),
            ]
        )

        let collection = RuleCollection(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Navigation",
            summary: "Nav",
            category: .navigation,
            mappings: [mapping],
            isEnabled: true,
            isSystemDefault: false,
            icon: nil,
            tags: [],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            activationHint: nil,
            configuration: .list
        )

        let config = KanataConfiguration.generateFromCollections(
            [collection],
            navActivationMode: .tapToToggle
        )

        // Device switch should wrap the nav layer output
        assertContains(config, "dev_nav_h")
        assertContains(config, "((device 0)) home break")
        assertContains(config, "() left break")
        // The nav layer should still have one-shot exit wrapping around the switch alias
        assertContains(config, "release-layer nav")
    }

    func testFullConfigWithoutDeviceOverrides_IdenticalToBaseline() {
        // Ensure adding deviceOverrides: nil doesn't change output
        let fixedCollectionId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let fixedMappingId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        let mappingWithout = KeyMapping(id: fixedMappingId, input: "a", output: "b")
        let mappingWith = KeyMapping(id: fixedMappingId, input: "a", output: "b", deviceOverrides: nil)

        let collectionWithout = RuleCollection(
            id: fixedCollectionId, name: "Test", summary: "T", category: .productivity, mappings: [mappingWithout]
        )
        let collectionWith = RuleCollection(
            id: fixedCollectionId, name: "Test", summary: "T", category: .productivity, mappings: [mappingWith]
        )

        let configWithout = KanataConfiguration.generateFromCollections([collectionWithout])
        let configWith = KanataConfiguration.generateFromCollections([collectionWith])

        XCTAssertEqual(configWithout, configWith, "nil deviceOverrides should produce identical config")
    }

    func testFullConfigEmptyCacheWithOverrides_UsesDefault() {
        // When device cache is empty, overrides should be silently skipped.
        // The switch alias is still emitted with only the default case — this is
        // intentional: the code path doesn't special-case empty caches to avoid
        // complexity. The degenerate (switch () default break) is functionally
        // equivalent to a plain output and Kanata handles it correctly.
        let cache = DeviceSelectionCache.shared
        cache.reset() // Ensure empty
        defer { cache.reset() }

        let mapping = KeyMapping(
            input: "a",
            output: "b",
            deviceOverrides: [
                DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "x"),
            ]
        )

        let collection = RuleCollection(
            name: "Test", summary: "T", category: .productivity, mappings: [mapping]
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        // Switch alias emitted with only default case (no device-specific cases)
        assertContains(config, "dev_base_a")
        assertContains(config, "() b break")
        XCTAssertFalse(config.contains("((device"), "Empty cache should produce no device cases")
    }

    // MARK: - Integration with buildCollectionBlocks

    func testCollectionWithDeviceOverrides_GeneratesSwitchAlias() {
        // Set up connected devices in the cache
        let cache = DeviceSelectionCache.shared
        cache.updateConnectedDevices([device0, device1])

        defer { cache.reset() }

        let mapping = KeyMapping(
            input: "a",
            output: "b",
            deviceOverrides: [
                DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "x"),
            ]
        )

        let collection = RuleCollection(
            name: "Test",
            summary: "Test collection",
            category: .productivity,
            mappings: [mapping]
        )

        let (_, aliases, _, _) = KanataConfiguration.buildCollectionBlocks(
            from: [collection],
            leaderKeyPreference: nil
        )

        let deviceAlias = aliases.first(where: { $0.aliasName.hasPrefix("dev_") })
        XCTAssertNotNil(deviceAlias, "Should generate a device switch alias")
        assertContains(deviceAlias!.definition, "(switch")
        assertContains(deviceAlias!.definition, "((device 0)) x break")
        assertContains(deviceAlias!.definition, "() b break")
    }

    func testCollectionWithoutDeviceOverrides_NoSwitchAlias() {
        let mapping = KeyMapping(input: "a", output: "b")

        let collection = RuleCollection(
            name: "Test",
            summary: "Test collection",
            category: .productivity,
            mappings: [mapping]
        )

        let (_, aliases, _, _) = KanataConfiguration.buildCollectionBlocks(
            from: [collection],
            leaderKeyPreference: nil
        )

        let deviceAlias = aliases.first(where: { $0.aliasName.hasPrefix("dev_") })
        XCTAssertNil(deviceAlias, "Should not generate device switch alias when no overrides exist")
    }

    // MARK: - Helpers

    private func assertContains(
        _ config: String,
        _ snippet: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            config.contains(snippet),
            "Expected config to contain:\n\(snippet)\n\nActual output:\n\(config)",
            file: file,
            line: line
        )
    }
}
