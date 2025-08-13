import Foundation

/// Manages KeyPath application preferences and settings
@MainActor
class PreferencesService: ObservableObject {
    static let shared = PreferencesService()
    
    // MARK: - TCP Server Configuration
    
    /// Whether TCP server should be enabled for config validation
    @Published var tcpServerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tcpServerEnabled, forKey: Keys.tcpServerEnabled)
            AppLogger.shared.log("🔧 [PreferencesService] TCP server enabled: \(tcpServerEnabled)")
        }
    }
    
    /// TCP server port for Kanata communication
    @Published var tcpServerPort: Int {
        didSet {
            // Validate port range and revert if invalid
            if !isValidTCPPort(tcpServerPort) {
                AppLogger.shared.log("❌ [PreferencesService] Invalid TCP port \(tcpServerPort), reverting to \(oldValue)")
                tcpServerPort = oldValue
                return
            }
            
            UserDefaults.standard.set(tcpServerPort, forKey: Keys.tcpServerPort)
            AppLogger.shared.log("🔧 [PreferencesService] TCP server port: \(tcpServerPort)")
        }
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let tcpServerEnabled = "KeyPath.TCP.ServerEnabled"
        static let tcpServerPort = "KeyPath.TCP.ServerPort"
    }
    
    // MARK: - Defaults
    
    private enum Defaults {
        static let tcpServerEnabled = true  // Enable by default for config validation
        static let tcpServerPort = 37000    // Default port for Kanata TCP server
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load stored preferences or use defaults
        self.tcpServerEnabled = UserDefaults.standard.object(forKey: Keys.tcpServerEnabled) as? Bool ?? Defaults.tcpServerEnabled
        self.tcpServerPort = UserDefaults.standard.object(forKey: Keys.tcpServerPort) as? Int ?? Defaults.tcpServerPort
        
        AppLogger.shared.log("🔧 [PreferencesService] Initialized - TCP enabled: \(tcpServerEnabled), port: \(tcpServerPort)")
    }
    
    // MARK: - Public Interface
    
    /// Reset TCP settings to defaults
    func resetTCPSettings() {
        tcpServerEnabled = Defaults.tcpServerEnabled
        tcpServerPort = Defaults.tcpServerPort
        AppLogger.shared.log("🔧 [PreferencesService] TCP settings reset to defaults")
    }
    
    /// Validate TCP port is in acceptable range
    func isValidTCPPort(_ port: Int) -> Bool {
        return port >= 1024 && port <= 65535
    }
    
    /// Get current TCP configuration as string for logging
    var tcpConfigDescription: String {
        return "TCP \(tcpServerEnabled ? "enabled" : "disabled") on port \(tcpServerPort)"
    }
}

// MARK: - Convenience Extensions

extension PreferencesService {
    /// Get the full TCP endpoint URL if enabled
    var tcpEndpoint: String? {
        guard tcpServerEnabled else { return nil }
        return "127.0.0.1:\(tcpServerPort)"
    }
    
    /// Check if TCP server should be included in Kanata launch arguments
    var shouldUseTCPServer: Bool {
        return tcpServerEnabled && isValidTCPPort(tcpServerPort)
    }
}

// MARK: - Thread-Safe Snapshot API

/// Thread-safe snapshot of TCP configuration for use from non-MainActor contexts
struct TCPConfigSnapshot {
    let enabled: Bool
    let port: Int
    
    /// Check if TCP server should be used based on snapshot values
    var shouldUseTCPServer: Bool {
        return enabled && (1024...65535).contains(port)
    }
}

extension PreferencesService {
    /// Get thread-safe snapshot of TCP configuration
    /// Safe to call from any actor context
    nonisolated static func tcpSnapshot() -> TCPConfigSnapshot {
        let enabled = UserDefaults.standard.object(forKey: "KeyPath.TCP.ServerEnabled") as? Bool ?? true
        let port = UserDefaults.standard.object(forKey: "KeyPath.TCP.ServerPort") as? Int ?? 37000
        
        return TCPConfigSnapshot(enabled: enabled, port: port)
    }
}