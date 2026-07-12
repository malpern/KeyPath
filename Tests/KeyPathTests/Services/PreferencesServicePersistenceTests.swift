@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class PreferencesServicePersistenceTests: XCTestCase {
    private static let preferenceKeys = [
        "KeyPath.Communication.Protocol",
        "KeyPath.TCP.ServerPort",
        "KeyPath.Notifications.Enabled",
        "KeyPath.Recording.ApplyMappingsDuringRecording",
        "KeyPath.Recording.IsSequenceMode",
        "KeyPath.Diagnostics.VerboseKanataLogging",
        "KeyPath.Testing.AccessibilityTestMode",
        "KeyPath.LeaderKey.Preference",
        "KeyPath.ContextHUD.DisplayMode",
        "KeyPath.ContextHUD.TriggerMode",
        "KeyPath.ContextHUD.Timeout",
        "KeyPath.ContextHUD.HoldDelayPreset",
        "KeyPath.ContextHUD.HoldDelayCustomMs",
        "KeyPath.KindaVim.LeaderHUDMode",
        "KeyPath.Neovim.ReferenceTopics",
        "KeyPath.Neovim.ReferenceTopicsVersion",
        "KeyPath.Display.KeyLabelStyle",
        "KeyPath.Overlay.UnmappedLayerKeyStyle",
        "KeyPath.Education.OverlayHiddenHintShowCount",
        "KeyPath.Overlay.SuppressedBundleIDs",
    ]

    private func withPreservedDefaults<T>(
        keys: [String] = PreferencesServicePersistenceTests.preferenceKeys,
        _ body: () throws -> T
    ) rethrows -> T {
        let savedValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = savedValues[key] {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        return try body()
    }

    // MARK: - Critical Preference Round Trips

    func testCriticalSettings_RoundTripThroughUserDefaults() {
        withPreservedDefaults {
            for key in Self.preferenceKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }

            let leader = LeaderKeyPreference(
                key: "tab",
                targetLayer: .custom("window"),
                enabled: false
            )
            let writer = PreferencesService()
            writer.tcpServerPort = 45678
            writer.notificationsEnabled = false
            writer.applyMappingsDuringRecording = false
            writer.isSequenceMode = false
            writer.verboseKanataLogging = false
            writer.accessibilityTestMode = true
            writer.keyLabelStyle = .text
            writer.unmappedLayerKeyStyle = .dimmed
            writer.leaderKeyPreference = leader
            writer.overlayHiddenHintShowCount = 3
            writer.overlaySuppressedBundleIDs = Set(["com.example.Editor", "com.example.Terminal"])
            writer.contextHUDDisplayMode = .both
            writer.contextHUDTriggerMode = .tapToToggle
            writer.contextHUDTimeout = 6.5
            writer.contextHUDHoldDelayPreset = .custom
            writer.contextHUDHoldDelayCustomMs = 750
            writer.kindaVimLeaderHUDMode = .cheatSheetOnly
            writer.neovimReferenceTopics = Set([
                NeovimTerminalCategory.basicMotions.rawValue,
                NeovimTerminalCategory.search.rawValue,
            ])

            let loaded = PreferencesService()

            XCTAssertEqual(loaded.tcpServerPort, 45678)
            XCTAssertFalse(loaded.notificationsEnabled)
            XCTAssertFalse(loaded.applyMappingsDuringRecording)
            XCTAssertFalse(loaded.isSequenceMode)
            XCTAssertFalse(loaded.verboseKanataLogging)
            XCTAssertTrue(loaded.accessibilityTestMode)
            XCTAssertEqual(loaded.keyLabelStyle, .text)
            XCTAssertEqual(loaded.unmappedLayerKeyStyle, .dimmed)
            XCTAssertEqual(loaded.leaderKeyPreference, leader)
            XCTAssertEqual(loaded.overlayHiddenHintShowCount, 3)
            XCTAssertEqual(loaded.overlaySuppressedBundleIDs, Set(["com.example.Editor", "com.example.Terminal"]))
            XCTAssertEqual(loaded.contextHUDDisplayMode, .both)
            XCTAssertEqual(loaded.contextHUDTriggerMode, .tapToToggle)
            XCTAssertEqual(loaded.contextHUDTimeout, 6.5)
            XCTAssertEqual(loaded.contextHUDHoldDelayPreset, .custom)
            XCTAssertEqual(loaded.contextHUDHoldDelayCustomMs, 750)
            XCTAssertEqual(loaded.contextHUDHoldDelayMs, 750)
            XCTAssertEqual(loaded.kindaVimLeaderHUDMode, .cheatSheetOnly)
            XCTAssertEqual(
                loaded.neovimReferenceTopics,
                Set([
                    NeovimTerminalCategory.basicMotions.rawValue,
                    NeovimTerminalCategory.search.rawValue,
                ])
            )
        }
    }

    func testLoadClampsInvalidPersistedRuntimeAndHUDValues() {
        withPreservedDefaults {
            UserDefaults.standard.set(80, forKey: "KeyPath.TCP.ServerPort")
            UserDefaults.standard.set(99.0, forKey: "KeyPath.ContextHUD.Timeout")
            UserDefaults.standard.set(-25, forKey: "KeyPath.ContextHUD.HoldDelayCustomMs")

            let prefs = PreferencesService()

            XCTAssertEqual(prefs.tcpServerPort, 37001)
            XCTAssertNil(UserDefaults.standard.object(forKey: "KeyPath.TCP.ServerPort"))
            XCTAssertEqual(prefs.contextHUDTimeout, 10.0)
            XCTAssertEqual(UserDefaults.standard.double(forKey: "KeyPath.ContextHUD.Timeout"), 10.0)
            XCTAssertEqual(prefs.contextHUDHoldDelayCustomMs, 100)
            XCTAssertEqual(UserDefaults.standard.integer(forKey: "KeyPath.ContextHUD.HoldDelayCustomMs"), 100)
        }
    }

    func testLoadFallsBackForInvalidStoredEnumsAndLeaderPreference() {
        withPreservedDefaults {
            UserDefaults.standard.set("udp", forKey: "KeyPath.Communication.Protocol")
            UserDefaults.standard.set("emoji", forKey: "KeyPath.Display.KeyLabelStyle")
            UserDefaults.standard.set("invisible", forKey: "KeyPath.Overlay.UnmappedLayerKeyStyle")
            UserDefaults.standard.set("drawer", forKey: "KeyPath.ContextHUD.DisplayMode")
            UserDefaults.standard.set("doubleTap", forKey: "KeyPath.ContextHUD.TriggerMode")
            UserDefaults.standard.set("instant", forKey: "KeyPath.ContextHUD.HoldDelayPreset")
            UserDefaults.standard.set("coach", forKey: "KeyPath.KindaVim.LeaderHUDMode")
            UserDefaults.standard.set(Data("not-json".utf8), forKey: "KeyPath.LeaderKey.Preference")
            UserDefaults.standard.set(["search", "bogus-topic"], forKey: "KeyPath.Neovim.ReferenceTopics")
            UserDefaults.standard.set(2, forKey: "KeyPath.Neovim.ReferenceTopicsVersion")

            let prefs = PreferencesService()

            XCTAssertEqual(prefs.communicationProtocol, .tcp)
            XCTAssertEqual(prefs.keyLabelStyle, .symbols)
            XCTAssertEqual(prefs.unmappedLayerKeyStyle, .baseLayer)
            XCTAssertEqual(prefs.contextHUDDisplayMode, .overlayOnly)
            XCTAssertEqual(prefs.contextHUDTriggerMode, .holdToShow)
            XCTAssertEqual(prefs.contextHUDHoldDelayPreset, .long)
            XCTAssertEqual(prefs.kindaVimLeaderHUDMode, .off)
            XCTAssertEqual(prefs.leaderKeyPreference, .default)
            XCTAssertEqual(prefs.neovimReferenceTopics, Set([NeovimTerminalCategory.search.rawValue]))
        }
    }

    func testRuntimeAffectingPreferenceChangesPostNotifications() {
        withPreservedDefaults {
            let prefs = PreferencesService()
            let recorder = NotificationRecorder()
            let center = NotificationCenter.default
            let observedNames: [Notification.Name] = [
                .verboseLoggingChanged,
                .accessibilityTestModeChanged,
                .overlaySuppressedBundleIDsChanged,
                .configAffectingPreferenceChanged,
            ]
            let observers = observedNames.map { name in
                center.addObserver(forName: name, object: nil, queue: nil) { notification in
                    recorder.record(notification.name)
                }
            }
            defer {
                for observer in observers {
                    center.removeObserver(observer)
                }
            }

            prefs.verboseKanataLogging.toggle()
            prefs.accessibilityTestMode.toggle()
            prefs.overlaySuppressedBundleIDs = Set(["com.example.SuppressMe"])
            prefs.contextHUDTriggerMode = prefs.contextHUDTriggerMode == .holdToShow ? .tapToToggle : .holdToShow
            prefs.contextHUDHoldDelayPreset = .custom
            prefs.contextHUDHoldDelayCustomMs = 444

            let postedNames = recorder.names
            XCTAssertTrue(postedNames.contains(.verboseLoggingChanged))
            XCTAssertTrue(postedNames.contains(.accessibilityTestModeChanged))
            XCTAssertTrue(postedNames.contains(.overlaySuppressedBundleIDsChanged))
            XCTAssertGreaterThanOrEqual(
                postedNames.filter { $0 == .configAffectingPreferenceChanged }.count,
                3
            )
        }
    }

    func testRuntimePreferencesAffectKanataLaunchArguments() {
        withPreservedDefaults {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PreferencesServiceConfigArgs-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let configService = ConfigurationService(configDirectory: tempDir.path)
            let manager = ConfigurationManager(
                configurationService: configService,
                configBackupManager: ConfigBackupManager(configPath: configService.configurationPath),
                configFileWatcher: nil
            )

            let prefs = PreferencesService.shared
            let originalPort = prefs.tcpServerPort
            let originalVerboseLogging = prefs.verboseKanataLogging
            defer {
                prefs.tcpServerPort = originalPort
                prefs.verboseKanataLogging = originalVerboseLogging
            }

            prefs.tcpServerPort = 45678
            prefs.verboseKanataLogging = true

            let verboseArgs = manager.buildKanataArguments(checkOnly: false)
            XCTAssertEqual(verboseArgs.portArgumentValue, "45678")
            XCTAssertTrue(verboseArgs.contains("--trace"))
            XCTAssertTrue(verboseArgs.contains("--log-layer-changes"))

            prefs.verboseKanataLogging = false
            let normalArgs = manager.buildKanataArguments(checkOnly: false)
            XCTAssertEqual(normalArgs.portArgumentValue, "45678")
            XCTAssertFalse(normalArgs.contains("--trace"))
            XCTAssertTrue(normalArgs.contains("--log-layer-changes"))
        }
    }

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

    // MARK: - Legacy TCP Port Migration

    func testRetiredCommandActionsPreferenceIsRemovedOnLoad() {
        let key = "KeyPath.Security.ConfigCommandActionsEnabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(true, forKey: key)

        _ = PreferencesService()

        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    /// An old install that still has the UDP-era port (54141) stored should be
    /// migrated to the current default (37001) on load, and the stale key
    /// cleared so it tracks the default going forward. This is the fix for the
    /// "no TCP" mismatch where the app dialed 54141 while kanata listened on 37001.
    func testTcpServerPort_LegacyUDPEraPortMigratesToDefault() {
        let key = "KeyPath.TCP.ServerPort"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(54141, forKey: key)

        let prefs = PreferencesService()

        XCTAssertEqual(prefs.tcpServerPort, 37001, "Legacy port should migrate to current default")
        XCTAssertNil(
            UserDefaults.standard.object(forKey: key),
            "Stale key should be cleared so the port tracks the default going forward"
        )
    }

    /// A deliberately-chosen non-legacy port must NOT be clobbered by the migration.
    func testTcpServerPort_DeliberateCustomPortPreserved() {
        let key = "KeyPath.TCP.ServerPort"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(8123, forKey: key)

        let prefs = PreferencesService()

        XCTAssertEqual(prefs.tcpServerPort, 8123, "A non-legacy custom port must be preserved")
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

private extension [String] {
    var portArgumentValue: String? {
        guard let index = firstIndex(of: "--port"), index + 1 < count else { return nil }
        return self[index + 1]
    }
}

private final class NotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedNames: [Notification.Name] = []

    var names: [Notification.Name] {
        lock.lock()
        defer { lock.unlock() }
        return recordedNames
    }

    func record(_ name: Notification.Name) {
        lock.lock()
        recordedNames.append(name)
        lock.unlock()
    }
}
