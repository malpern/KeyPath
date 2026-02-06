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

/// Manages KeyPath application preferences and settings
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

    // MARK: - Activity Logging

    /// Whether activity logging is enabled (requires double opt-in)
    var activityLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(activityLoggingEnabled, forKey: Keys.activityLoggingEnabled)
            AppLogger.shared.log("📊 [Preferences] activityLoggingEnabled = \(activityLoggingEnabled)")
            // Post notification for ActivityLogger to start/stop
            NotificationCenter.default.post(name: .activityLoggingChanged, object: nil)
        }
    }

    /// Timestamp when user gave consent to activity logging (nil if never consented)
    var activityLoggingConsentDate: Date? {
        didSet {
            if let date = activityLoggingConsentDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.activityLoggingConsentDate)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.activityLoggingConsentDate)
            }
            AppLogger.shared.log("📊 [Preferences] activityLoggingConsentDate = \(activityLoggingConsentDate?.description ?? "nil")")
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

    // MARK: - Keys

    private enum Keys {
        static let communicationProtocol = "KeyPath.Communication.Protocol"
        static let tcpServerPort = "KeyPath.TCP.ServerPort"
        static let notificationsEnabled = "KeyPath.Notifications.Enabled"
        static let applyMappingsDuringRecording = "KeyPath.Recording.ApplyMappingsDuringRecording"
        static let isSequenceMode = "KeyPath.Recording.IsSequenceMode"
        static let verboseKanataLogging = "KeyPath.Diagnostics.VerboseKanataLogging"
        static let activityLoggingEnabled = "KeyPath.ActivityLogging.Enabled"
        static let activityLoggingConsentDate = "KeyPath.ActivityLogging.ConsentDate"
        static let leaderKeyPreference = "KeyPath.LeaderKey.Preference"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let communicationProtocol = CommunicationProtocol.tcp // TCP is only protocol
        static let tcpServerPort = 37001 // Default port for Kanata TCP server
        static let notificationsEnabled = true
        static let applyMappingsDuringRecording = true
        static let isSequenceMode = true
        static let verboseKanataLogging = false // Off by default to avoid log spam
        static let activityLoggingEnabled = false // Requires explicit opt-in
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

        // Activity logging preferences
        activityLoggingEnabled =
            UserDefaults.standard.object(forKey: Keys.activityLoggingEnabled) as? Bool
                ?? Defaults.activityLoggingEnabled

        if let consentTimestamp = UserDefaults.standard.object(forKey: Keys.activityLoggingConsentDate) as? TimeInterval {
            activityLoggingConsentDate = Date(timeIntervalSince1970: consentTimestamp)
        } else {
            activityLoggingConsentDate = nil
        }

        // Leader key preference
        if let data = UserDefaults.standard.data(forKey: Keys.leaderKeyPreference),
           let stored = try? JSONDecoder().decode(LeaderKeyPreference.self, from: data)
        {
            leaderKeyPreference = stored
        } else {
            leaderKeyPreference = .default
        }

        AppLogger.shared.log(
            "🔧 [PreferencesService] Initialized - Protocol: \(communicationProtocol.rawValue), TCP port: \(tcpServerPort), Verbose logging: \(verboseKanataLogging), Activity logging: \(activityLoggingEnabled)"
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
