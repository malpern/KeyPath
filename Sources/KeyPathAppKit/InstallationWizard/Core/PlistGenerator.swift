import Foundation
import KeyPathCore

/// Generates launchd plist XML content for KeyPath services.
/// Pure functions with no side effects - just string generation.
/// These plists are used to configure macOS launchd services for Kanata and VHID components.
struct PlistGenerator {
    // MARK: - Service Identifiers

    /// Service identifier for the main Kanata keyboard remapping daemon
    static let kanataServiceID = "com.keypath.kanata"

    /// Service identifier for the Karabiner Virtual HID Device daemon
    static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"

    /// Service identifier for the Karabiner Virtual HID Device manager
    static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    /// Service identifier for the log rotation service
    static let logRotationServiceID = "com.keypath.logrotate"

    // MARK: - Executable Paths

    /// Path to the Karabiner Virtual HID Device daemon executable
    static let vhidDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

    /// Path to the Karabiner Virtual HID Device manager executable
    static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    // MARK: - Kanata Plist Generation

    /// Build Kanata program arguments array for launchd plist.
    ///
    /// - Parameters:
    ///   - binaryPath: Path to the Kanata binary executable
    ///   - configPath: Path to the Kanata configuration file (.kbd)
    ///   - tcpPort: TCP port for Kanata's communication server (default: 37001)
    ///   - verboseLogging: If true, uses --trace mode; otherwise uses --debug mode
    /// - Returns: Array of command-line arguments for the Kanata process
    static func buildKanataPlistArguments(
        binaryPath: String,
        configPath: String,
        tcpPort: Int = 37001,
        verboseLogging: Bool = false
    ) -> [String] {
        var arguments = [binaryPath, "--cfg", configPath]

        // Add TCP port for communication server
        arguments.append(contentsOf: ["--port", "\(tcpPort)"])

        // Add logging flags based on verboseLogging preference
        if verboseLogging {
            // Trace mode: comprehensive logging with event timing
            arguments.append("--trace")
        } else {
            // Standard debug mode
            arguments.append("--debug")
        }
        arguments.append("--log-layer-changes")

        return arguments
    }

    /// Generate the Kanata service launchd plist XML content.
    ///
    /// Creates a plist that runs Kanata as a root daemon with:
    /// - TCP server on the specified port for inter-process communication
    /// - Automatic restart on load (RunAtLoad)
    /// - Logging to /var/log/kanata.log
    /// - File descriptor limits for stable operation
    /// - Association with the KeyPath app bundle
    ///
    /// - Parameters:
    ///   - binaryPath: Path to the Kanata binary executable
    ///   - configPath: Path to the Kanata configuration file (.kbd)
    ///   - tcpPort: TCP port for Kanata's communication server (default: 37001)
    ///   - verboseLogging: If true, uses --trace mode; otherwise uses --debug mode
    /// - Returns: Complete plist XML string ready to write to disk
    static func generateKanataPlist(
        binaryPath: String,
        configPath: String,
        tcpPort: Int = 37001,
        verboseLogging: Bool = false
    ) -> String {
        let arguments = buildKanataPlistArguments(
            binaryPath: binaryPath,
            configPath: configPath,
            tcpPort: tcpPort,
            verboseLogging: verboseLogging
        )

        // TCP mode: No environment variables needed (auth token stored in Keychain)
        let environmentXML = ""

        var argumentsXML = ""
        for arg in arguments {
            argumentsXML += "                <string>\(arg)</string>\n"
        }
        // Ensure proper indentation for the XML
        argumentsXML = argumentsXML.trimmingCharacters(in: .newlines)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(kanataServiceID)</string>
            <key>ProgramArguments</key>
            <array>
            \(argumentsXML)
            </array>\(environmentXML)
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/var/log/kanata.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/kanata.log</string>
            <key>SoftResourceLimits</key>
            <dict>
                <key>NumberOfFiles</key>
                <integer>256</integer>
            </dict>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
            <key>ThrottleInterval</key>
            <integer>10</integer>
            <key>AssociatedBundleIdentifiers</key>
            <array>
                <string>com.keypath.KeyPath</string>
            </array>
        </dict>
        </plist>
        """
    }

    // MARK: - VHID Daemon Plist Generation

    /// Generate the Virtual HID Device Daemon launchd plist XML content.
    ///
    /// Creates a plist that runs the Karabiner Virtual HID Device Daemon as a
    /// root daemon with:
    /// - Automatic restart (KeepAlive)
    /// - Logging to /var/log/karabiner-vhid-daemon.log
    /// - Throttle protection to prevent rapid restart loops
    ///
    /// This daemon is required for Kanata to access the virtual keyboard device.
    ///
    /// - Returns: Complete plist XML string ready to write to disk
    static func generateVHIDDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(vhidDaemonServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(vhidDaemonPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/karabiner-vhid-daemon.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/karabiner-vhid-daemon.log</string>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
            <key>ThrottleInterval</key>
            <integer>10</integer>
        </dict>
        </plist>
        """
    }

    // MARK: - VHID Manager Plist Generation

    /// Generate the Virtual HID Device Manager launchd plist XML content.
    ///
    /// Creates a plist that runs the Karabiner Virtual HID Device Manager as a
    /// root daemon with:
    /// - "activate" command to enable the virtual HID device
    /// - Run once at load (no KeepAlive)
    /// - Logging to /var/log/karabiner-vhid-manager.log
    ///
    /// This manager activates the DriverKit extension that provides the virtual keyboard.
    ///
    /// - Returns: Complete plist XML string ready to write to disk
    static func generateVHIDManagerPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(vhidManagerServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(vhidManagerPath)</string>
                <string>activate</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/var/log/karabiner-vhid-manager.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/karabiner-vhid-manager.log</string>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
        </dict>
        </plist>
        """
    }

    // MARK: - Log Rotation Plist Generation

    /// Generate the log rotation service launchd plist XML content.
    ///
    /// Creates a plist that runs a log rotation script hourly (at minute 0)
    /// to keep log files under control. The script is responsible for:
    /// - Rotating kanata.log and other KeyPath service logs
    /// - Keeping total log size under 10MB
    ///
    /// - Parameter scriptPath: Path to the log rotation shell script
    /// - Returns: Complete plist XML string ready to write to disk
    static func generateLogRotationPlist(scriptPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(logRotationServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(scriptPath)</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Minute</key>
                <integer>0</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>/var/log/keypath-logrotate.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/keypath-logrotate.log</string>
            <key>UserName</key>
            <string>root</string>
        </dict>
        </plist>
        """
    }
}
