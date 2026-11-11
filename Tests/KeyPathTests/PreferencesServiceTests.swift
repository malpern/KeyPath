@testable import KeyPathAppKit
import XCTest

@MainActor
final class PreferencesServiceTests: XCTestCase {
    func testCanonicalDefaultsFallsBackToStandardWhenSuiteIsUnavailable() {
        let key = "PreferencesServiceTests.canonicalDefaultsFallback"
        let defaults = PreferencesService.canonicalDefaults(using: nil)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        defaults.set(true, forKey: key)

        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }

    // MARK: - Communication Config Description

    func testCommunicationConfigDescriptionNamesTheOwnerCheckedSocket() {
        let desc = PreferencesService().communicationConfigDescription
        XCTAssertTrue(desc.contains("Unix-domain socket"))
        XCTAssertFalse(desc.contains("37001"))
    }

    // MARK: - Context HUD Hold Delay

    func testContextHUDHoldDelayMs_ShortPreset() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayPreset = .short
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 150)
    }

    func testContextHUDHoldDelayMs_MediumPreset() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayPreset = .medium
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 200)
    }

    func testContextHUDHoldDelayMs_LongPreset() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayPreset = .long
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 300)
    }

    func testContextHUDHoldDelayMs_CustomPresetUsesCustomValue() {
        let prefs = PreferencesService()
        prefs.contextHUDHoldDelayCustomMs = 175
        prefs.contextHUDHoldDelayPreset = .custom
        XCTAssertEqual(prefs.contextHUDHoldDelayMs, 175)
    }

    // MARK: - Preferred Protocol

    func testPreferredProtocol_AlwaysTCP() {
        let prefs = PreferencesService()
        XCTAssertEqual(prefs.preferredProtocol, .tcp)
    }

    // MARK: - Reset Communication Settings

    func testResetCommunicationSettings_RestoresDefaults() {
        let prefs = PreferencesService()
        prefs.resetCommunicationSettings()
        XCTAssertEqual(prefs.communicationProtocol, .tcp)
    }

    // MARK: - Enum Display Names

    func testKeyLabelStyle_AllCasesHaveDisplayNames() {
        for style in KeyLabelStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty, "\(style) missing displayName")
            XCTAssertFalse(style.description.isEmpty, "\(style) missing description")
        }
    }

    func testContextHUDDisplayMode_AllCasesHaveDisplayNames() {
        for mode in ContextHUDDisplayMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) missing displayName")
        }
    }

    func testContextHUDTriggerMode_AllCasesHaveDisplayNames() {
        for mode in ContextHUDTriggerMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) missing displayName")
            XCTAssertFalse(mode.description.isEmpty, "\(mode) missing description")
        }
    }

    func testContextHUDHoldDelayPreset_AllCasesHaveDisplayNames() {
        for preset in ContextHUDHoldDelayPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "\(preset) missing displayName")
        }
    }

    func testContextHUDHoldDelayPreset_MillisecondsValues() {
        XCTAssertEqual(ContextHUDHoldDelayPreset.short.milliseconds, 150)
        XCTAssertEqual(ContextHUDHoldDelayPreset.medium.milliseconds, 200)
        XCTAssertEqual(ContextHUDHoldDelayPreset.long.milliseconds, 300)
        XCTAssertNil(ContextHUDHoldDelayPreset.custom.milliseconds)
    }

    func testKindaVimLeaderHUDMode_AllCasesHaveDisplayNames() {
        for mode in KindaVimLeaderHUDMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) missing displayName")
            XCTAssertFalse(mode.description.isEmpty, "\(mode) missing description")
        }
    }

    func testCommunicationProtocol_TCPHasDisplayInfo() {
        let proto = CommunicationProtocol.tcp
        XCTAssertFalse(proto.displayName.isEmpty)
        XCTAssertFalse(proto.description.isEmpty)
    }

    // MARK: - KeyLabelStyle raw values

    func testKeyLabelStyle_RawValues() {
        XCTAssertEqual(KeyLabelStyle.symbols.rawValue, "symbols")
        XCTAssertEqual(KeyLabelStyle.text.rawValue, "text")
    }

    func testKeyLabelStyle_InitFromRawValue() {
        XCTAssertEqual(KeyLabelStyle(rawValue: "symbols"), .symbols)
        XCTAssertEqual(KeyLabelStyle(rawValue: "text"), .text)
        XCTAssertNil(KeyLabelStyle(rawValue: "unknown"))
    }
}
