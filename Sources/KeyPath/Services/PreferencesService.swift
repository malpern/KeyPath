import Foundation
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
            AppLogger.shared.log("🔧 [PreferencesService] Communication protocol: \(communicationProtocol.rawValue)")
        }
    }

    // MARK: - TCP Server Configuration

    /// TCP server port for Kanata communication
    var tcpServerPort: Int {
        didSet {
            // Validate port range and revert if invalid
            if !isValidPort(tcpServerPort) {
                AppLogger.shared.log(
                    "❌ [PreferencesService] Invalid TCP port \(tcpServerPort), reverting to \(oldValue)")
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
            UserDefaults.standard.set(applyMappingsDuringRecording, forKey: Keys.applyMappingsDuringRecording)
            AppLogger.shared.log("🎛️ [Preferences] applyMappingsDuringRecording = \(applyMappingsDuringRecording)")
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let communicationProtocol = "KeyPath.Communication.Protocol"
        static let tcpServerPort = "KeyPath.TCP.ServerPort"
        static let notificationsEnabled = "KeyPath.Notifications.Enabled"
        static let applyMappingsDuringRecording = "KeyPath.Recording.ApplyMappingsDuringRecording"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let communicationProtocol = CommunicationProtocol.tcp // TCP is only protocol
        static let tcpServerPort = 37001 // Default port for Kanata TCP server
        static let notificationsEnabled = true
        static let applyMappingsDuringRecording = true
    }

    // MARK: - Initialization

    init() {
        // Load stored preferences or use defaults
        let protocolString = UserDefaults.standard.string(forKey: Keys.communicationProtocol) ?? Defaults.communicationProtocol.rawValue
        communicationProtocol = CommunicationProtocol(rawValue: protocolString) ?? Defaults.communicationProtocol

        tcpServerPort =
            UserDefaults.standard.object(forKey: Keys.tcpServerPort) as? Int ?? Defaults.tcpServerPort

        notificationsEnabled =
            UserDefaults.standard.object(forKey: Keys.notificationsEnabled) as? Bool
                ?? Defaults.notificationsEnabled

        // Recording preference
        applyMappingsDuringRecording =
            UserDefaults.standard.object(forKey: Keys.applyMappingsDuringRecording) as? Bool
                ?? Defaults.applyMappingsDuringRecording

        AppLogger.shared.log(
            "🔧 [PreferencesService] Initialized - Protocol: \(communicationProtocol.rawValue), TCP port: \(tcpServerPort)"
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
