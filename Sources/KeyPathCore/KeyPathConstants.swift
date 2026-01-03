import Foundation

/*
 +---+---+---+---+---+---+---+---+
 | K | E | Y | P | A | T | H | :)|
 +---+---+---+---+---+---+---+---+
 */

/*
    _  __          ____      __  __
   | |/ /___  ____/ / /___ _/ /_/ /_
   |   / __ \/ __  / / __ `/ __/ __/
  /   / /_/ / /_/ / / /_/ / /_/ /_
 /_/|_\____/\__,_/_/\__,_/\__/\__/
 */

/// Centralized constants for the KeyPath application.
/// This ensures consistent path usage across the App, Helper, and Daemons.
public enum KeyPathConstants {
    public enum Bundle {
        public static let appName = "KeyPath"
        public static let bundleID = "com.keypath.KeyPath"
        public static let helperID = "com.keypath.KeyPath.Helper"
        public static let daemonID = "com.keypath.kanata"
        public static let vhidDaemonID = "com.keypath.vhid-daemon"
        public static let vhidManagerID = "com.keypath.vhid-manager"
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
        public static let kanataStdout = "/var/log/com.keypath.kanata.stdout.log"

        /// Standard error log for the kanata daemon
        public static let kanataStderr = "/var/log/com.keypath.kanata.stderr.log"

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
