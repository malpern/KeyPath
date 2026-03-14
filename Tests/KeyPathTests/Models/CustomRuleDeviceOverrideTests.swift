@testable import KeyPathAppKit
@preconcurrency import XCTest

final class CustomRuleDeviceOverrideTests: XCTestCase {
    // MARK: - Model Tests

    func testAsKeyMappingIncludesDeviceOverrides() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xABCD1234", output: "b", behavior: nil)
        ]
        let rule = CustomRule(input: "a", output: "a", deviceOverrides: overrides)

        let mapping = rule.asKeyMapping()

        XCTAssertEqual(mapping.input, "a")
        XCTAssertEqual(mapping.output, "a")
        XCTAssertEqual(mapping.deviceOverrides?.count, 1)
        XCTAssertEqual(mapping.deviceOverrides?.first?.deviceHash, "0xABCD1234")
        XCTAssertEqual(mapping.deviceOverrides?.first?.output, "b")
    }

    func testAsKeyMappingWithoutDeviceOverridesReturnsNil() {
        let rule = CustomRule(input: "a", output: "b")

        let mapping = rule.asKeyMapping()

        XCTAssertNil(mapping.deviceOverrides)
    }

    func testDeviceOverrideWithBehavior() {
        let dualRole = DualRoleBehavior(
            tapAction: "b",
            holdAction: "lctl",
            tapTimeout: 200,
            holdTimeout: 200
        )
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xDEAD", output: "b", behavior: .dualRole(dualRole))
        ]
        let rule = CustomRule(input: "a", output: "a", deviceOverrides: overrides)

        let mapping = rule.asKeyMapping()

        XCTAssertNotNil(mapping.deviceOverrides?.first?.behavior)
        if case .dualRole(let loaded) = mapping.deviceOverrides?.first?.behavior {
            XCTAssertEqual(loaded.holdAction, "lctl")
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    // MARK: - Codable Round-Trip Tests

    func testCodableRoundTripPreservesDeviceOverrides() throws {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 1000)
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xABCD1234", output: "b", behavior: nil),
            DeviceKeyOverride(deviceHash: "0xDEADBEEF", output: "c", behavior: nil)
        ]
        let original = CustomRule(
            id: UUID(),
            title: "Per-device test",
            input: "a",
            output: "a",
            isEnabled: true,
            createdAt: fixedDate,
            deviceOverrides: overrides
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomRule.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.deviceOverrides?.count, 2)
        XCTAssertEqual(decoded.deviceOverrides?[0].deviceHash, "0xABCD1234")
        XCTAssertEqual(decoded.deviceOverrides?[0].output, "b")
        XCTAssertEqual(decoded.deviceOverrides?[1].deviceHash, "0xDEADBEEF")
        XCTAssertEqual(decoded.deviceOverrides?[1].output, "c")
    }

    func testDecodeLegacyJSONWithoutDeviceOverridesDefaultsToNil() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "",
          "input": "a",
          "output": "b",
          "isEnabled": true,
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CustomRule.self, from: json)

        XCTAssertEqual(decoded.id, id)
        XCTAssertNil(decoded.deviceOverrides)
    }

    func testCodableRoundTripWithBehaviorOverride() throws {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 2000)
        let dualRole = DualRoleBehavior(
            tapAction: "b",
            holdAction: "lctl",
            tapTimeout: 200,
            holdTimeout: 200
        )
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xCAFE", output: "b", behavior: .dualRole(dualRole))
        ]
        let original = CustomRule(
            id: UUID(),
            title: "Hold test",
            input: "a",
            output: "a",
            isEnabled: true,
            createdAt: fixedDate,
            deviceOverrides: overrides
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomRule.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.deviceOverrides?.count, 1)
        if case .dualRole(let loaded) = decoded.deviceOverrides?.first?.behavior {
            XCTAssertEqual(loaded.holdAction, "lctl")
        } else {
            XCTFail("Expected dualRole behavior after round-trip")
        }
    }

    // MARK: - ConnectedDevice SF Symbol Tests

    func testAppleDeviceGetLaptopSymbol() {
        let device = ConnectedDevice(
            hash: "0x1234",
            vendorID: 0x05AC,
            productID: 0x0342,
            productKey: "Apple Internal Keyboard",
            isVirtualHID: false
        )
        XCTAssertEqual(device.sfSymbolName, "laptopcomputer")
    }

    func testExternalDeviceGetKeyboardSymbol() {
        let device = ConnectedDevice(
            hash: "0x5678",
            vendorID: 0x29EA,
            productID: 0x0041,
            productKey: "Kinesis Advantage360",
            isVirtualHID: false
        )
        XCTAssertEqual(device.sfSymbolName, "keyboard")
    }

    // MARK: - DeviceConditionInfo Tests

    func testDeviceConditionInfoIdentity() {
        let info = DeviceConditionInfo(
            deviceHash: "0xABCD",
            displayName: "Kinesis",
            sfSymbolName: "keyboard"
        )
        XCTAssertEqual(info.id, "0xABCD")
        XCTAssertEqual(info.displayName, "Kinesis")
        XCTAssertEqual(info.sfSymbolName, "keyboard")
    }

    func testDeviceConditionInfoEquality() {
        let a = DeviceConditionInfo(deviceHash: "0xABCD", displayName: "Kinesis", sfSymbolName: "keyboard")
        let b = DeviceConditionInfo(deviceHash: "0xABCD", displayName: "Kinesis", sfSymbolName: "keyboard")
        let c = DeviceConditionInfo(deviceHash: "0xDEAD", displayName: "Moonlander", sfSymbolName: "keyboard")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Config Generation Integration

    func testDeviceOverrideProducesDeviceSwitchConfig() {
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xABCD1234", output: "b", behavior: nil)
        ]
        let rule = CustomRule(input: "a", output: "a", deviceOverrides: overrides)
        let mapping = rule.asKeyMapping()

        // The mapping should have the identity output as default and the override
        XCTAssertEqual(mapping.output, "a")
        XCTAssertEqual(mapping.deviceOverrides?.first?.output, "b")

        // Verify config generation produces switch expression
        let device = ConnectedDevice(
            hash: "0xABCD1234",
            vendorID: 0x29EA,
            productID: 0x0041,
            productKey: "Test Keyboard",
            isVirtualHID: false
        )

        let result = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: "a",
            overrides: overrides,
            connectedDevices: [device]
        )

        XCTAssertTrue(result.contains("switch"), "Switch expression should contain 'switch'")
        XCTAssertTrue(result.contains("b"), "Switch expression should contain the override output 'b'")
        XCTAssertTrue(result.contains("a"), "Switch expression should contain the default output 'a'")
    }

    func testDeviceOverrideEndToEndCustomRuleToConfig() {
        // Simulate the full flow: CustomRule with device override → KeyMapping → config output
        let device0 = ConnectedDevice(
            hash: "0xAAAA0000", vendorID: 0x05AC, productID: 0x0342,
            productKey: "Apple Internal Keyboard", isVirtualHID: false
        )
        let device1 = ConnectedDevice(
            hash: "0xBBBB1111", vendorID: 0x29EA, productID: 0x0041,
            productKey: "Kinesis Advantage360", isVirtualHID: false
        )

        // User mapped 'a' → 'b' only on the Kinesis
        // Default (Apple) stays identity: a → a
        let overrides = [
            DeviceKeyOverride(deviceHash: "0xBBBB1111", output: "b", behavior: nil)
        ]
        let rule = CustomRule(input: "a", output: "a", deviceOverrides: overrides)
        let mapping = rule.asKeyMapping()

        let config = KanataConfiguration.renderDeviceSwitchExpression(
            defaultOutput: mapping.output,
            overrides: mapping.deviceOverrides!,
            connectedDevices: [device0, device1]
        )

        // device1 is index 1 in the connected devices list
        XCTAssertTrue(config.contains("switch"), "Should generate switch expression")
        XCTAssertTrue(config.contains("device"), "Should reference device in condition")
        XCTAssertTrue(config.contains("b"), "Should contain the override output")
    }
}
