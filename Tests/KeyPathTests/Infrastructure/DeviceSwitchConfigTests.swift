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

        XCTAssertTrue(result.contains("(switch"), "Should contain switch keyword")
        XCTAssertTrue(result.contains("((device 0)) x break"), "Should map device 0 to override output")
        XCTAssertTrue(result.contains("() b break"), "Should contain default fallthrough")
    }

    func testDeviceOverrideWithUnknownHash_SkipsCase() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xDEADBEEF", output: "z"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1]
        )

        // Unknown hash should be skipped — only default case present
        XCTAssertFalse(result.contains("((device"), "Unknown device hash should be skipped")
        XCTAssertTrue(result.contains("() a break"), "Default fallthrough should always be present")
    }

    func testMultipleDeviceOverrides_PreservesInputOrder() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xBBBB1111", output: "y"),
            DeviceKeyOverride(deviceHash: "0xAAAA0000", output: "x"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1]
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
            connectedDevices: [device0]
        )

        XCTAssertTrue(result.contains("() caps break"), "Default fallthrough must always be present")
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

        XCTAssertTrue(result.contains("(switch"), "Should contain switch keyword")
        XCTAssertTrue(result.contains("(tap-hold"), "Behavior override should render tap-hold")
        XCTAssertTrue(result.contains("lctl"), "Should contain hold action")
        XCTAssertTrue(result.contains("((device 0))"), "Should have device 0 case")
        XCTAssertTrue(result.contains("() b break"), "Default fallthrough should be present")
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

        XCTAssertTrue(result.contains("(macro"), "Macro behavior should render macro expression")
        XCTAssertTrue(result.contains("((device 1))"), "Should map to device index 1")
        XCTAssertTrue(result.contains("() a break"), "Default fallthrough should be present")
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

        XCTAssertTrue(result.contains("((device 0)) (tap-hold"), "Device 0 should get tap-hold")
        XCTAssertTrue(result.contains("((device 1)) caps break"), "Device 1 should get simple remap")
        XCTAssertTrue(result.contains("() a break"), "Default fallthrough should be present")
    }

    func testAllOverridesUnresolvable_EmitsOnlyDefault() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xDEAD0001", output: "x"),
            DeviceKeyOverride(deviceHash: "0xDEAD0002", output: "y"),
        ]

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device0, device1]
        )

        XCTAssertFalse(result.contains("((device"), "No device cases should be present")
        XCTAssertTrue(result.contains("() a break"), "Only default fallthrough should be present")
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
        // When device cache is empty, overrides should be silently skipped
        // (this tests the graceful degradation path)
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

        // Should still have the switch alias (with only default case)
        assertContains(config, "dev_base_a")
        assertContains(config, "() b break")
        // Should NOT have any device-specific cases
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
        XCTAssertTrue(deviceAlias!.definition.contains("(switch"), "Alias should contain switch block")
        XCTAssertTrue(deviceAlias!.definition.contains("((device 0)) x break"), "Should contain device override")
        XCTAssertTrue(deviceAlias!.definition.contains("() b break"), "Should contain default fallthrough")
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
