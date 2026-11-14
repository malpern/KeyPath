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
/// This ensures consistent path usage across the app, CLI, and session runtime.
public enum KeyPathConstants {
    public enum Bundle {
        public static let appName = "KeyPath"
        public static let bundleID = "com.keypath.KeyPath"

        /// Bundle ID for the "Kanata Engine.app" wrapper around the kanata binary.
        /// TCC uses this for bundle-ID based permission tracking (client_type=0).
        public static let kanataEngineBundleID = "com.keypath.kanata-engine"
    }

    public enum Config {
        public static let fileName = "keypath.kbd"

        /// The main directory for user configuration: ~/.config/keypath.
        /// Under test this redirects to the per-process AppPaths sandbox so
        /// concurrent test processes (parallel CI PRs, or multiple local Claude
        /// sessions) never race the same real keypath.kbd — the second half of
        /// the "could not enable associated rule collection" fix (the first is
        /// RuleCollectionStore). Production resolution is unchanged.
        public static var directory: String {
            if TestEnvironment.isRunningTests {
                return AppPaths.configDirectory.path
            }
            return "\(NSHomeDirectory())/.config/keypath"
        }

        /// The main configuration file: ~/.config/keypath/keypath.kbd
        public static var mainConfigPath: String {
            "\(directory)/\(fileName)"
        }
    }

    public enum Logs {
        /// User-facing debug log: ~/Library/Logs/KeyPath/keypath-debug.log
        public static var userDebugLog: String {
            "\(NSHomeDirectory())/Library/Logs/KeyPath/keypath-debug.log"
        }
    }

    public enum Binaries {
        /// The bundled kanata binary name
        public static let kanataName = "kanata"
    }

    public enum System {
        public static let osascript = "/usr/bin/osascript"
        public static let pkill = "/usr/bin/pkill"
        public static let launchctl = "/bin/launchctl"
        public static let securityPrefPane = "/System/Library/PreferencePanes/Security.prefPane"
    }

    public enum URLs {
        public static let accessibilityPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        public static let kanataTroubleshooting = "https://github.com/malpern-labs/KeyPath/blob/master/docs/troubleshooting/debugging-kanata.md"
        public static let configurationTroubleshooting = "\(kanataTroubleshooting)#configuration-errors"
    }

    public enum Timing {
        public static let tcpConnectionTimeout: TimeInterval = 3.0
        public static let toastDuration: TimeInterval = 3.0
        public static let holdLabelCacheTTL: TimeInterval = 5
        public static let kanataReadinessTimeout: TimeInterval = 20
        public static let kanataReadinessPollInterval: TimeInterval = 0.5
    }
}
