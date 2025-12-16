import Foundation

/// Centralized constants for the KeyPath application.
/// This ensures consistent path usage across the App, Helper, and Daemons.
public enum KeyPathConstants {
    public enum Bundle {
        public static let appName = "KeyPath"
        public static let bundleID = "com.keypath.KeyPath"
        public static let helperID = "com.keypath.KeyPath.Helper"
        public static let daemonID = "com.keypath.kanata"
        // VirtualHID services are based on Karabiner’s DriverKit VirtualHIDDevice.
        // Keep IDs aligned with the generated plists and health checks.
        public static let vhidDaemonID = "com.keypath.karabiner-vhiddaemon"
        public static let vhidManagerID = "com.keypath.karabiner-vhidmanager"
    }

    public enum Config {
        public static let fileName = "keypath.kbd"

        /// The main directory for user configuration: ~/.config/keypath
        public static var directory: String {
            "\(NSHomeDirectory())/.config/keypath"
        }

        /// The main configuration file: ~/.config/keypath/keypath.kbd
        public static var mainConfigPath: String {
            "\(directory)/\(fileName)"
        }
    }

    public enum Logs {
        /// Standard output log for the kanata daemon
        public static let kanataStdout = "/var/tmp/com.keypath.kanata.stdout.log"

        /// Standard error log for the kanata daemon
        public static let kanataStderr = "/var/tmp/com.keypath.kanata.stderr.log"

        /// Log directory for Karabiner (used during setup)
        public static let karabinerDir = "/var/log/karabiner"
    }

    public enum Binaries {
        /// The system-wide install location for kanata (managed by helper)
        public static let systemBinPath = "/Library/KeyPath/bin/kanata"

        /// The bundled kanata binary name
        public static let kanataName = "kanata"
    }

    public enum VirtualHID {
        public static let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
        public static let rootOnlyTmp = "/Library/Application Support/org.pqrs/tmp/rootonly"
        public static let tmpDir = "/Library/Application Support/org.pqrs/tmp"
    }

    public enum System {
        public static let osascript = "/usr/bin/osascript"
        public static let pkill = "/usr/bin/pkill"
        public static let launchctl = "/bin/launchctl"
        public static let securityPrefPane = "/System/Library/PreferencePanes/Security.prefPane"
        public static let launchDaemonsDir = "/Library/LaunchDaemons"
    }

    public enum URLs {
        public static let inputMonitoringPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        public static let accessibilityPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }
}
