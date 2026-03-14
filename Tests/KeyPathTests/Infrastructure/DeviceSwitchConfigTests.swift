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

    func testDeviceOverrideWithBehavior_RendersTapHold() {
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
        XCTAssertTrue(result.contains("((device 0))"), "Should have device 0 case")
        XCTAssertTrue(result.contains("() b break"), "Default fallthrough should be present")
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
}
