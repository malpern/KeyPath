import Foundation
import KeyPathCore
import Observation

/// Communication protocol for Kanata integration
/// TCP is the only supported protocol (Kanata v1.9.0 - see ADR-013)
enum CommunicationProtocol: String, CaseIterable {
    case tcp

    var displayName: String {
        "TCP (Reliable)"
    }

    var description: String {
        "Reliable TCP protocol for config reloading (no authentication required - see ADR-013)"
    }
}

/// Display mode for the Context HUD
enum ContextHUDDisplayMode: String, CaseIterable {
    case overlayOnly
    case hudOnly
    case both

    var displayName: String {
        switch self {
        case .overlayOnly: "Overlay Only"
        case .hudOnly: "HUD Only"
        case .both: "Both"
        }
    }
}

/// How the overlay/HUD is triggered when the modifier (Hyper/Meh) is activated
public enum ContextHUDTriggerMode: String, CaseIterable, Sendable {
    /// Show while holding modifier, dismiss on release
    case holdToShow
    /// Tap modifier to toggle visibility on/off
    case tapToToggle

    public var displayName: String {
        switch self {
        case .holdToShow: "Hold to Show"
        case .tapToToggle: "Tap to Toggle"
        }
    }

    public var description: String {
        switch self {
        case .holdToShow: "Appears while holding, dismisses on release"
        case .tapToToggle: "Tap to show, tap again or press Esc to dismiss"
        }
    }
}

/// Hold-duration presets for triggering the Shortcut List/navigation layer.
public enum ContextHUDHoldDelayPreset: String, CaseIterable, Sendable {
    case short
    case medium
    case long
    case custom

    public var displayName: String {
        switch self {
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        case .custom: "Custom"
        }
    }

    var milliseconds: Int? {
        switch self {
        case .short: 150
        case .medium: 200
        case .long: 300
        case .custom: nil
        }
    }
}

/// Controls how KindaVim content is presented in the leader-hold shortcut list.
public enum KindaVimLeaderHUDMode: String, CaseIterable, Sendable {
    case contextualCoach
    case cheatSheetOnly
    case off

    public var displayName: String {
        switch self {
        case .contextualCoach: "Contextual Coach + Cheatsheet"
        case .cheatSheetOnly: "Cheatsheet Only"
        case .off: "Use Standard Key List"
        }
    }

    public var description: String {
        switch self {
        case .contextualCoach:
            "Mode-aware tips plus a compact command reference."
        case .cheatSheetOnly:
            "Show quick command reference without coaching tips."
        case .off:
            "Use the regular layer key list for leader hold."
        }
    }
}

/// Manages KeyPath application preferences and settings
// SAFETY: @unchecked Sendable — all mutable state is backed by UserDefaults (thread-safe)
// and the shared instance is confined to @MainActor. @Observable macro prevents conforming
// to Sendable directly; @unchecked bridges the gap.
@Observable
final class PreferencesService: @unchecked Sendable {
    // MARK: - Shared instance (backward compatible)

    @MainActor static let shared = PreferencesService()

    // MARK: - Communication Protocol Configuration

    /// Communication protocol preference (always TCP)
    var communicationProtocol: CommunicationProtocol {
        didSet {
            UserDefaults.standard.set(communicationProtocol.rawValue, forKey: Keys.communicationProtocol)
            AppLogger.shared.log(
                "🔧 [PreferencesService] Communication protocol: \(communicationProtocol.rawValue)"
            )
        }
    }

    // MARK: - TCP Server Configuration

    /// TCP server port for Kanata communication
    var tcpServerPort: Int {
        didSet {
            // Validate port range and revert if invalid
            if !isValidPort(tcpServerPort) {
                AppLogger.shared.log(
                    "❌ [PreferencesService] Invalid TCP port \(tcpServerPort), reverting to \(oldValue)"
                )
                tcpServerPort = oldValue
            } else {
                UserDefaults.standard.set(tcpServerPort, forKey: Keys.tcpServerPort)
                AppLogger.shared.log("🔧 [PreferencesService] TCP server port: \(tcpServerPort)")
            }
        }
    }

    /// Whether user notifications are enabled
    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            AppLogger.shared.log("🔔 [PreferencesService] Notifications enabled: \(notificationsEnabled)")
        }
    }

    /// When true, leave mappings active while recording (effective preview).
    /// When false, temporarily suspend mappings so the recorder captures raw keys.
    var applyMappingsDuringRecording: Bool {
        didSet {
            UserDefaults.standard.set(
                applyMappingsDuringRecording, forKey: Keys.applyMappingsDuringRecording
            )
            AppLogger.shared.log(
                "🎛️ [Preferences] applyMappingsDuringRecording = \(applyMappingsDuringRecording)"
            )
        }
    }

    /// When true, capture keys in sequence (one after another).
    /// When false, capture keys as combination (all pressed together).
    var isSequenceMode: Bool {
        didSet {
            UserDefaults.standard.set(isSequenceMode, forKey: Keys.isSequenceMode)
            AppLogger.shared.log("🎛️ [Preferences] isSequenceMode = \(isSequenceMode)")
        }
    }

    /// When true, enable comprehensive trace logging in Kanata (--trace flag)
    /// Logs every key event with timing information for debugging performance issues
    var verboseKanataLogging: Bool {
        didSet {
            UserDefaults.standard.set(verboseKanataLogging, forKey: Keys.verboseKanataLogging)
            AppLogger.shared.log("📊 [Preferences] verboseKanataLogging = \(verboseKanataLogging)")
            // Post notification so RuntimeCoordinator can restart with new flags
            NotificationCenter.default.post(name: .verboseLoggingChanged, object: nil)
        }
    }

    // MARK: - Testing

    /// When true, makes the overlay window discoverable by automation tools (Peekaboo).
    /// Toggling posts a notification so the overlay controller can recreate its window with the new style.
    var accessibilityTestMode: Bool {
        didSet {
            UserDefaults.standard.set(accessibilityTestMode, forKey: Keys.accessibilityTestMode)
            AppLogger.shared.log("🧪 [Preferences] accessibilityTestMode = \(accessibilityTestMode)")
            NotificationCenter.default.post(name: .accessibilityTestModeChanged, object: nil)
        }
    }

    // MARK: - Leader Key Configuration

    /// Primary leader key preference (Space → Nav by default)
    /// This is independent of any collection - collections just target this layer
    var leaderKeyPreference: LeaderKeyPreference {
        didSet {
            if let data = try? JSONEncoder().encode(leaderKeyPreference) {
                UserDefaults.standard.set(data, forKey: Keys.leaderKeyPreference)
                AppLogger.shared.log("🎯 [Preferences] Leader key: \(leaderKeyPreference.key) → \(leaderKeyPreference.targetLayer.displayName) (enabled: \(leaderKeyPreference.enabled))")
            }
        }
    }

    // MARK: - Education Hints

    /// How many times the "Overlay Hidden" education message has been shown
    var overlayHiddenHintShowCount: Int {
        didSet {
            UserDefaults.standard.set(overlayHiddenHintShowCount, forKey: Keys.overlayHiddenHintShowCount)
        }
    }

    // MARK: - Context HUD Configuration

    /// Display mode for the Context HUD (overlay only, HUD only, or both)
    var contextHUDDisplayMode: ContextHUDDisplayMode {
        didSet {
            UserDefaults.standard.set(contextHUDDisplayMode.rawValue, forKey: Keys.contextHUDDisplayMode)
            AppLogger.shared.log("🎯 [Preferences] contextHUDDisplayMode = \(contextHUDDisplayMode.rawValue)")
        }
    }

    /// How the HUD/overlay is triggered by the modifier key
    var contextHUDTriggerMode: ContextHUDTriggerMode {
        didSet {
            UserDefaults.standard.set(contextHUDTriggerMode.rawValue, forKey: Keys.contextHUDTriggerMode)
            AppLogger.shared.log("🎯 [Preferences] contextHUDTriggerMode = \(contextHUDTriggerMode.rawValue)")
            // Trigger config regeneration since this affects Kanata layer activation behavior
            NotificationCenter.default.post(name: .configAffectingPreferenceChanged, object: nil)
        }
    }

    /// Auto-dismiss timeout for the Context HUD (seconds, 1-10)
    var contextHUDTimeout: TimeInterval {
        didSet {
            let clamped = min(max(contextHUDTimeout, 1), 10)
            if clamped != contextHUDTimeout {
                contextHUDTimeout = clamped
            } else {
                UserDefaults.standard.set(contextHUDTimeout, forKey: Keys.contextHUDTimeout)
                AppLogger.shared.log("🎯 [Preferences] contextHUDTimeout = \(contextHUDTimeout)s")
            }
        }
    }

    /// Preset hold duration for triggering Shortcut List/navigation layer.
    var contextHUDHoldDelayPreset: ContextHUDHoldDelayPreset {
        didSet {
            UserDefaults.standard.set(contextHUDHoldDelayPreset.rawValue, forKey: Keys.contextHUDHoldDelayPreset)
            AppLogger.shared.log("🎯 [Preferences] contextHUDHoldDelayPreset = \(contextHUDHoldDelayPreset.rawValue)")
            NotificationCenter.default.post(name: .configAffectingPreferenceChanged, object: nil)
        }
    }

    /// Custom hold duration in milliseconds (used when preset is `.custom`).
    var contextHUDHoldDelayCustomMs: Int {
        didSet {
            let clamped = min(max(contextHUDHoldDelayCustomMs, 100), 2000)
            if clamped != contextHUDHoldDelayCustomMs {
                contextHUDHoldDelayCustomMs = clamped
            } else {
                UserDefaults.standard.set(contextHUDHoldDelayCustomMs, forKey: Keys.contextHUDHoldDelayCustomMs)
                AppLogger.shared.log("🎯 [Preferences] contextHUDHoldDelayCustomMs = \(contextHUDHoldDelayCustomMs)")
                NotificationCenter.default.post(name: .configAffectingPreferenceChanged, object: nil)
            }
        }
    }

    /// Effective hold duration in milliseconds used by generated config.
    var contextHUDHoldDelayMs: Int {
        contextHUDHoldDelayPreset.milliseconds ?? contextHUDHoldDelayCustomMs
    }

    /// Presentation mode for KindaVim in leader-hold HUD/key list.
    var kindaVimLeaderHUDMode: KindaVimLeaderHUDMode {
        didSet {
            UserDefaults.standard.set(kindaVimLeaderHUDMode.rawValue, forKey: Keys.kindaVimLeaderHUDMode)
            AppLogger.shared.log("🎯 [Preferences] kindaVimLeaderHUDMode = \(kindaVimLeaderHUDMode.rawValue)")
        }
    }

    /// Selected educational Neovim topics shown in leader-hold quick reference.
    /// Stores raw values from `NeovimTerminalCategory`.
    var neovimReferenceTopics: Set<String> {
        didSet {
            let effective = neovimReferenceTopics.isEmpty ? Defaults.neovimReferenceTopics : neovimReferenceTopics
            if effective != neovimReferenceTopics {
                neovimReferenceTopics = effective
                return
            }
            UserDefaults.standard.set(Array(effective).sorted(), forKey: Keys.neovimReferenceTopics)
            AppLogger.shared.log(
                "🎯 [Preferences] neovimReferenceTopics = \(Array(effective).sorted().joined(separator: ","))"
            )
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let communicationProtocol = "KeyPath.Communication.Protocol"
        static let tcpServerPort = "KeyPath.TCP.ServerPort"
        static let notificationsEnabled = "KeyPath.Notifications.Enabled"
        static let applyMappingsDuringRecording = "KeyPath.Recording.ApplyMappingsDuringRecording"
        static let isSequenceMode = "KeyPath.Recording.IsSequenceMode"
        static let verboseKanataLogging = "KeyPath.Diagnostics.VerboseKanataLogging"
        static let accessibilityTestMode = "KeyPath.Testing.AccessibilityTestMode"
        static let leaderKeyPreference = "KeyPath.LeaderKey.Preference"
        static let contextHUDDisplayMode = "KeyPath.ContextHUD.DisplayMode"
        static let contextHUDTriggerMode = "KeyPath.ContextHUD.TriggerMode"
        static let contextHUDTimeout = "KeyPath.ContextHUD.Timeout"
        static let contextHUDHoldDelayPreset = "KeyPath.ContextHUD.HoldDelayPreset"
        static let contextHUDHoldDelayCustomMs = "KeyPath.ContextHUD.HoldDelayCustomMs"
        static let kindaVimLeaderHUDMode = "KeyPath.KindaVim.LeaderHUDMode"
        static let neovimReferenceTopics = "KeyPath.Neovim.ReferenceTopics"
        static let neovimReferenceTopicsVersion = "KeyPath.Neovim.ReferenceTopicsVersion"
        static let overlayHiddenHintShowCount = "KeyPath.Education.OverlayHiddenHintShowCount"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let communicationProtocol = CommunicationProtocol.tcp // TCP is only protocol
        static let tcpServerPort = 37001 // Default port for Kanata TCP server
        static let notificationsEnabled = true
        static let applyMappingsDuringRecording = true
        static let isSequenceMode = true
        #if DEBUG
            static let verboseKanataLogging = true // Debug builds favor diagnostics
        #else
            static let verboseKanataLogging = false // Release builds favor smaller logs
        #endif
        static let accessibilityTestMode = false
        static let contextHUDDisplayMode = ContextHUDDisplayMode.both
        static let contextHUDTriggerMode = ContextHUDTriggerMode.holdToShow
        static let contextHUDTimeout: TimeInterval = 3.0
        static let contextHUDHoldDelayPreset = ContextHUDHoldDelayPreset.long
        static let contextHUDHoldDelayCustomMs = 200
        static let kindaVimLeaderHUDMode = KindaVimLeaderHUDMode.contextualCoach
        static let neovimReferenceTopics = NeovimTerminalCategory.defaultRawValues
        static let neovimReferenceTopicsVersion = 2
    }

    // MARK: - Initialization

    init() {
        // Load stored preferences or use defaults
        let protocolString =
            UserDefaults.standard.string(forKey: Keys.communicationProtocol)
                ?? Defaults.communicationProtocol.rawValue
        communicationProtocol =
            CommunicationProtocol(rawValue: protocolString) ?? Defaults.communicationProtocol

        tcpServerPort =
            UserDefaults.standard.object(forKey: Keys.tcpServerPort) as? Int ?? Defaults.tcpServerPort

        notificationsEnabled =
            UserDefaults.standard.object(forKey: Keys.notificationsEnabled) as? Bool
                ?? Defaults.notificationsEnabled

        // Recording preferences
        applyMappingsDuringRecording =
            UserDefaults.standard.object(forKey: Keys.applyMappingsDuringRecording) as? Bool
                ?? Defaults.applyMappingsDuringRecording

        isSequenceMode =
            UserDefaults.standard.object(forKey: Keys.isSequenceMode) as? Bool
                ?? Defaults.isSequenceMode

        verboseKanataLogging =
            UserDefaults.standard.object(forKey: Keys.verboseKanataLogging) as? Bool
                ?? Defaults.verboseKanataLogging

        // Testing preferences
        accessibilityTestMode =
            UserDefaults.standard.object(forKey: Keys.accessibilityTestMode) as? Bool
                ?? Defaults.accessibilityTestMode

        // Leader key preference
        if let data = UserDefaults.standard.data(forKey: Keys.leaderKeyPreference),
           let stored = try? JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        {
            leaderKeyPreference = stored
        } else {
            leaderKeyPreference = .default
        }

        // Education hints
        overlayHiddenHintShowCount =
            UserDefaults.standard.object(forKey: Keys.overlayHiddenHintShowCount) as? Int ?? 0

        // Context HUD preferences
        let hudModeString = UserDefaults.standard.string(forKey: Keys.contextHUDDisplayMode)
            ?? Defaults.contextHUDDisplayMode.rawValue
        contextHUDDisplayMode = ContextHUDDisplayMode(rawValue: hudModeString)
            ?? Defaults.contextHUDDisplayMode

        let triggerModeString = UserDefaults.standard.string(forKey: Keys.contextHUDTriggerMode)
            ?? Defaults.contextHUDTriggerMode.rawValue
        contextHUDTriggerMode = ContextHUDTriggerMode(rawValue: triggerModeString)
            ?? Defaults.contextHUDTriggerMode

        contextHUDTimeout = UserDefaults.standard.object(forKey: Keys.contextHUDTimeout) as? TimeInterval
            ?? Defaults.contextHUDTimeout

        let holdDelayPresetString = UserDefaults.standard.string(forKey: Keys.contextHUDHoldDelayPreset)
            ?? Defaults.contextHUDHoldDelayPreset.rawValue
        contextHUDHoldDelayPreset = ContextHUDHoldDelayPreset(rawValue: holdDelayPresetString)
            ?? Defaults.contextHUDHoldDelayPreset

        contextHUDHoldDelayCustomMs =
            UserDefaults.standard.object(forKey: Keys.contextHUDHoldDelayCustomMs) as? Int
                ?? Defaults.contextHUDHoldDelayCustomMs

        let kindaVimHUDModeString = UserDefaults.standard.string(forKey: Keys.kindaVimLeaderHUDMode)
            ?? Defaults.kindaVimLeaderHUDMode.rawValue
        kindaVimLeaderHUDMode = KindaVimLeaderHUDMode(rawValue: kindaVimHUDModeString)
            ?? Defaults.kindaVimLeaderHUDMode

        let storedNeovimTopics = Set(UserDefaults.standard.stringArray(forKey: Keys.neovimReferenceTopics) ?? [])
        let validNeovimTopics = Set(NeovimTerminalCategory.allCases.map(\.rawValue))
        let sanitizedNeovimTopics = storedNeovimTopics.intersection(validNeovimTopics)
        let topicsVersion = UserDefaults.standard.object(forKey: Keys.neovimReferenceTopicsVersion) as? Int ?? 0
        let legacyDefault = Set([NeovimTerminalCategory.basicMotions.rawValue])
        let migratedNeovimTopics: Set<String> = if topicsVersion < Defaults.neovimReferenceTopicsVersion, sanitizedNeovimTopics == legacyDefault {
            Defaults.neovimReferenceTopics
        } else {
            sanitizedNeovimTopics
        }
        neovimReferenceTopics = migratedNeovimTopics.isEmpty
            ? Defaults.neovimReferenceTopics
            : migratedNeovimTopics
        UserDefaults.standard.set(Defaults.neovimReferenceTopicsVersion, forKey: Keys.neovimReferenceTopicsVersion)

        AppLogger.shared.log(
            "🔧 [PreferencesService] Initialized - Protocol: \(communicationProtocol.rawValue), TCP port: \(tcpServerPort), Verbose logging: \(verboseKanataLogging)"
        )
    }

    // MARK: - Public Interface

    /// Reset all communication settings to defaults
    func resetCommunicationSettings() {
        communicationProtocol = Defaults.communicationProtocol
        tcpServerPort = Defaults.tcpServerPort
        AppLogger.shared.log("🔧 [PreferencesService] All communication settings reset to defaults")
    }

    /// Validate port is in acceptable range
    func isValidPort(_ port: Int) -> Bool {
        port >= 1024 && port <= 65535
    }

    /// Get current communication configuration as string for logging
    var communicationConfigDescription: String {
        "TCP on port \(tcpServerPort) (no authentication required)"
    }
}

// MARK: - Convenience Extensions

extension PreferencesService {
    /// Get the currently preferred communication protocol (always TCP)
    var preferredProtocol: CommunicationProtocol {
        communicationProtocol
    }
}
