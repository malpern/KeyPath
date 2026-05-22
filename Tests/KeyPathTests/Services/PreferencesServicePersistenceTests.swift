@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class PreferencesServicePersistenceTests: XCTestCase {
    // MARK: - Value Clamping Tests

    func testContextHUDTimeout_ClampedToMinimum() {
        let prefs = PreferencesService()
        prefs.contextHUDTimeout = 0.5
        XCTAssertEqual(prefs.contextHUDTimeout, 1.0, "Timeout should be clamped to minimum 1.0")
    }

    func testContextHUDTimeout_ClampedToMaximum() {
        let prefs = PreferencesService()
        prefs.contextHUDTimeout = 15.0
        XCTAssertEqual(prefs.contextHUDTimeout, 10.0, "Timeout should be clamped to maximum 10.0")
    }

    func testContextHUDTimeout_AcceptsValidValue() {
        let prefs = PreferencesService()
        prefs.contextHUDTimeout = 5.0
        XCTAssertEqual(prefs.contextHUDTimeout, 5.0)
    }

    func testContextHUDTimeout_AcceptsBoundaries() {
        let prefs = PreferencesService()
        prefs.contextHUDTimeout = 1.0
        XCTAssertEqual(prefs.contextHUDTimeout, 1.0)
        prefs.contextHUDTimeout = 10.0
        XCTAssertEqual(prefs.contextHUDTimeout, 10.0)
    }

    func testContextHUDHoldDelayCustomMs_ClampedToMinimum() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = 50
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100, "Custom delay clamped to min 100ms")
    }

    func testContextHUDHoldDelayCustomMs_ClampedToMaximum() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = 3000
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 2000, "Custom delay clamped to max 2000ms")
    }

    func testContextHUDHoldDelayCustomMs_AcceptsValidValue() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = 500
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 500)
    }

    func testContextHUDHoldDelayCustomMs_AcceptsBoundaries() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = 100
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
        prefs.contextHUDHoldDelayCustomMs = 2000
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 2000)
    }

    func testContextHUDTimeout_ZeroClampedToMin() {
        let prefs = PreferencesService()
        prefs.contextHUDTimeout = 0
        XCTAssertEqual(prefs.contextHUDTimeout, 1.0)
    }

    func testContextHUDTimeout_NegativeClampedToMin() {
        let prefs = PreferencesService()
        prefs.contextHUDTimeout = -5
        XCTAssertEqual(prefs.contextHUDTimeout, 1.0)
    }

    func testContextHUDHoldDelayCustomMs_ZeroClampedToMin() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = 0
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
    }

    func testContextHUDHoldDelayCustomMs_NegativeClampedToMin() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = -100
        XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
    }

    // MARK: - TCP Port Validation

    func testTcpServerPort_ValidPortAccepted() {
        let prefs = PreferencesService()
        let originalPort = prefs.tcpServerPort
        prefs.tcpServerPort = 8080
        XCTAssertEqual(prefs.tcpServerPort, 8080)
        prefs.tcpServerPort = originalPort
    }

    func testTcpServerPort_InvalidPortReverts() {
        let prefs = PreferencesService()
        let originalPort = prefs.tcpServerPort
        prefs.tcpServerPort = 80
        XCTAssertEqual(prefs.tcpServerPort, originalPort, "Invalid port should revert to previous")
    }

    func testTcpServerPort_BoundaryValues() {
        let prefs = PreferencesService()
        XCTAssertTrue(prefs.isValidPort(1024))
        XCTAssertTrue(prefs.isValidPort(65535))
        XCTAssertFalse(prefs.isValidPort(1023))
        XCTAssertFalse(prefs.isValidPort(65536))
    }

    // MARK: - LeaderKeyPreference Codable Tests

    func testLeaderKeyPreference_DefaultValues() {
        let pref = LeaderKeyPreference.default
        XCTAssertEqual(pref.key, "space")
        XCTAssertEqual(pref.targetLayer, .navigation)
        XCTAssertTrue(pref.enabled)
    }

    func testLeaderKeyPreference_RoundTripCodable() throws {
        let original = LeaderKeyPreference(
            key: "tab",
            targetLayer: .custom("window"),
            enabled: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testLeaderKeyPreference_NavigationLayerRoundTrip() throws {
        let original = LeaderKeyPreference(
            key: "space",
            targetLayer: .navigation,
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .navigation)
    }

    func testLeaderKeyPreference_BaseLayerRoundTrip() throws {
        let original = LeaderKeyPreference(
            key: "caps",
            targetLayer: .base,
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .base)
    }

    func testLeaderKeyPreference_CustomLayerRoundTrip() throws {
        let original = LeaderKeyPreference(
            key: "ralt",
            targetLayer: .custom("symbols"),
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .custom("symbols"))
    }

    func testLeaderKeyPreference_InvalidJsonFallsBackToDefault() {
        let invalidData = "not json".data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(LeaderKeyPreference.self, from: invalidData)
        XCTAssertNil(decoded, "Invalid JSON should fail to decode")
    }

    func testLeaderKeyPreference_Equatable() {
        let a = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)
        let b = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)
        let c = LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Overlay Suppressed Bundle IDs

    func testOverlaySuppressedBundleIDs_DefaultContainsFigma() {
        let prefs = PreferencesService()
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.figma.Desktop"))
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.figma.agent"))
    }

    func testOverlaySuppressedBundleIDs_SetOperations() {
        let prefs = PreferencesService()
        let originalIDs = prefs.overlaySuppressedBundleIDs

        prefs.overlaySuppressedBundleIDs.insert("com.test.app")
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.test.app"))

        prefs.overlaySuppressedBundleIDs.remove("com.test.app")
        XCTAssertFalse(prefs.overlaySuppressedBundleIDs.contains("com.test.app"))

        prefs.overlaySuppressedBundleIDs = originalIDs
    }

    func testOverlaySuppressedBundleIDs_DeduplicatesOnStorage() {
        let prefs = PreferencesService()
        let originalIDs = prefs.overlaySuppressedBundleIDs

        prefs.overlaySuppressedBundleIDs = Set(["com.a.app", "com.a.app", "com.b.app"])
        XCTAssertEqual(prefs.overlaySuppressedBundleIDs.count, 2)
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.a.app"))
        XCTAssertTrue(prefs.overlaySuppressedBundleIDs.contains("com.b.app"))

        prefs.overlaySuppressedBundleIDs = originalIDs
    }

    // MARK: - Neovim Reference Topics

    func testNeovimReferenceTopics_DefaultsNotEmpty() {
        let prefs = PreferencesService()
        XCTAssertFalse(prefs.neovimReferenceTopics.isEmpty)
    }

    func testNeovimReferenceTopics_ContainsValidCategories() {
        let prefs = PreferencesService()
        let validCategories = Set(NeovimTerminalCategory.allCases.map(\.rawValue))
        for topic in prefs.neovimReferenceTopics {
            XCTAssertTrue(validCategories.contains(topic), "\(topic) is not a valid category")
        }
    }

    // MARK: - Enum Raw Value Round-Trip Tests

    func testContextHUDDisplayMode_RawValueRoundTrip() {
        for mode in ContextHUDDisplayMode.allCases {
            let raw = mode.rawValue
            let restored = ContextHUDDisplayMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "Round-trip failed for \(mode)")
        }
    }

    func testContextHUDTriggerMode_RawValueRoundTrip() {
        for mode in ContextHUDTriggerMode.allCases {
            let raw = mode.rawValue
            let restored = ContextHUDTriggerMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "Round-trip failed for \(mode)")
        }
    }

    func testContextHUDHoldDelayPreset_RawValueRoundTrip() {
        for preset in ContextHUDHoldDelayPreset.allCases {
            let raw = preset.rawValue
            let restored = ContextHUDHoldDelayPreset(rawValue: raw)
            XCTAssertEqual(restored, preset, "Round-trip failed for \(preset)")
        }
    }

    func testKindaVimLeaderHUDMode_RawValueRoundTrip() {
        for mode in KindaVimLeaderHUDMode.allCases {
            let raw = mode.rawValue
            let restored = KindaVimLeaderHUDMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "Round-trip failed for \(mode)")
        }
    }

    func testCommunicationProtocol_RawValueRoundTrip() {
        for proto in CommunicationProtocol.allCases {
            let raw = proto.rawValue
            let restored = CommunicationProtocol(rawValue: raw)
            XCTAssertEqual(restored, proto)
        }
    }

    // MARK: - Invalid Enum Raw Values

    func testContextHUDDisplayMode_InvalidRawValueReturnsNil() {
        XCTAssertNil(ContextHUDDisplayMode(rawValue: "invalid"))
    }

    func testContextHUDTriggerMode_InvalidRawValueReturnsNil() {
        XCTAssertNil(ContextHUDTriggerMode(rawValue: "invalid"))
    }

    func testContextHUDHoldDelayPreset_InvalidRawValueReturnsNil() {
        XCTAssertNil(ContextHUDHoldDelayPreset(rawValue: "invalid"))
    }

    func testKeyLabelStyle_InvalidRawValueReturnsNil() {
        XCTAssertNil(KeyLabelStyle(rawValue: "invalid"))
    }

    func testKindaVimLeaderHUDMode_InvalidRawValueReturnsNil() {
        XCTAssertNil(KindaVimLeaderHUDMode(rawValue: "invalid"))
    }

    // MARK: - Hold Delay Computed Property

    func testContextHUDHoldDelayMs_CustomUsesStoredValue() {
        let prefs = PreferencesService()
        let original = prefs.contextHUDHoldDelayPreset
        let originalMs = prefs.contextHUDHoldDelayCustomMs

        prefs.contextHUDHoldDelayCustomMs = 450
        prefs.contextHUDHoldDelayPreset = .custom
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 450)

        prefs.contextHUDHoldDelayPreset = original
        prefs.contextHUDHoldDelayCustomMs = originalMs
    }

    func testContextHUDHoldDelayMs_PresetOverridesCustom() {
        let prefs = PreferencesService()
        let original = prefs.contextHUDHoldDelayPreset

        prefs.contextHUDHoldDelayCustomMs = 999
        prefs.contextHUDHoldDelayPreset = .short
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 150, "Preset value should win over custom")

        prefs.contextHUDHoldDelayPreset = original
    }

    // MARK: - Default Values

    func testDefaultValues_AreReasonable() {
        let prefs = PreferencesService()
        XCTAssertEqual(prefs.communicationProtocol, .tcp)
        XCTAssertTrue(prefs.isValidPort(prefs.tcpServerPort))
        XCTAssertTrue(prefs.notificationsEnabled)
        XCTAssertTrue(prefs.isSequenceMode)
    }

    func testDefaultContextHUDTimeout_InRange() {
        let prefs = PreferencesService()
        XCTAssertGreaterThanOrEqual(prefs.contextHUDTimeout, 1.0)
        XCTAssertLessThanOrEqual(prefs.contextHUDTimeout, 10.0)
    }

    func testDefaultContextHUDHoldDelay_InRange() {
        let prefs = PreferencesService()
        XCTAssertGreaterThanOrEqual(prefs.contextHUDHoldDelayCustomMs, 100)
        XCTAssertLessThanOrEqual(prefs.contextHUDHoldDelayCustomMs, 2000)
    }

    // MARK: - RuleCollectionLayer Codable Tests

    func testRuleCollectionLayer_BaseCodableRoundTrip() throws {
        let original = RuleCollectionLayer.base
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRuleCollectionLayer_NavigationCodableRoundTrip() throws {
        let original = RuleCollectionLayer.navigation
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRuleCollectionLayer_CustomCodableRoundTrip() throws {
        let original = RuleCollectionLayer.custom("window")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Reset Behavior

    func testResetCommunicationSettings_RestoresProtocolAndPort() {
        let prefs = PreferencesService()
        let defaultPort = 37001

        prefs.tcpServerPort = 9999
        prefs.resetCommunicationSettings()

        XCTAssertEqual(prefs.communicationProtocol, .tcp)
        XCTAssertEqual(prefs.tcpServerPort, defaultPort)
    }

    // MARK: - Config Description

    func testCommunicationConfigDescription_Format() {
        let prefs = PreferencesService()
        let desc = prefs.communicationConfigDescription
        XCTAssertTrue(desc.contains("TCP"), "Should mention protocol")
        XCTAssertTrue(desc.contains("\(prefs.tcpServerPort)"), "Should include port")
    }

    // MARK: - NeovimTerminalCategory Tests

    func testNeovimTerminalCategory_AllCasesHaveTitles() {
        for category in NeovimTerminalCategory.allCases {
            XCTAssertFalse(category.title.isEmpty, "\(category) missing title")
        }
    }

    func testNeovimTerminalCategory_HasExpectedCases() {
        XCTAssertGreaterThanOrEqual(NeovimTerminalCategory.allCases.count, 9)
        XCTAssertNotNil(NeovimTerminalCategory(rawValue: "basicMotions"))
        XCTAssertNotNil(NeovimTerminalCategory(rawValue: "operators"))
        XCTAssertNotNil(NeovimTerminalCategory(rawValue: "search"))
    }

    func testNeovimTerminalCategory_InvalidRawValue() {
        XCTAssertNil(NeovimTerminalCategory(rawValue: "nonexistent"))
    }
}
