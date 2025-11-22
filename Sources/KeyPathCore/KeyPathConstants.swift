import Foundation

/// Centralized constants for the KeyPath application.
/// This ensures consistent path usage across the App, Helper, and Daemons.
public enum KeyPathConstants {
    public enum Bundle {
        public static let appName = "KeyPath"
        public static let bundleID = "com.keypath.KeyPath"
        public static let helperID = "com.keypath.KeyPath.Helper"
        public static let daemonID = "com.keypath.kanata"
    }

    public enum Config {
        /// The main directory for user configuration: ~/.config/keypath
        public static var directory: String {
            "\(NSHomeDirectory())/.config/keypath"
        }

        /// The main configuration file: ~/.config/keypath/keypath.kbd
        public static var mainConfigPath: String {
            "\(directory)/keypath.kbd"
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
    }
}
