#!/usr/bin/env swift

import Foundation

// Simulate the exact escaping and command that the wizard uses
func escapeForAppleScript(_ command: String) -> String {
    var escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
    return escaped
}

print("🔍 Debugging wizard fix button behavior...")
print(String(repeating: "=", count: 50))

// Simulate the actual command that executeConsolidatedInstallation would create
let launchDaemonsPath = "/Library/LaunchDaemons"
let kanataTemp = "/tmp/test-kanata.plist"
let vhidDaemonTemp = "/tmp/test-vhid-daemon.plist"
let vhidManagerTemp = "/tmp/test-vhid-manager.plist"
let kanataFinal = "\(launchDaemonsPath)/com.keypath.kanata.plist"
let vhidDaemonFinal = "\(launchDaemonsPath)/com.keypath.karabiner-vhiddaemon.plist"
let vhidManagerFinal = "\(launchDaemonsPath)/com.keypath.karabiner-vhidmanager.plist"
let userConfigDir = NSHomeDirectory() + "/Library/Application Support/KeyPath"
let userConfigPath = "\(userConfigDir)/keypath.kbd"

// Create the exact command that the wizard generates
let command = """
/bin/echo Installing LaunchDaemon services and configuration... && \
/bin/mkdir -p '\(launchDaemonsPath)' && \
/usr/bin/install -m 0644 -o root -g wheel '\(kanataTemp)' '\(kanataFinal)' && \
/usr/bin/install -m 0644 -o root -g wheel '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && \
/usr/bin/install -m 0644 -o root -g wheel '\(vhidManagerTemp)' '\(vhidManagerFinal)' && \
CONSOLE_UID="$(/usr/bin/stat -f %u /dev/console)" && \
CONSOLE_GID="$(/usr/bin/id -g $CONSOLE_UID)" && \
/usr/bin/install -d -m 0755 -o $CONSOLE_UID -g $CONSOLE_GID '\(userConfigDir)' && \
if [ ! -f '\(userConfigPath)' ]; then \
  /usr/bin/printf "%s\\n" ";; Default KeyPath config" "(defcfg process-unmapped-keys no)" "(defsrc)" "(deflayer base)" | /usr/bin/tee '\(userConfigPath)' >/dev/null && \
  /usr/sbin/chown $CONSOLE_UID:$CONSOLE_GID '\(userConfigPath)'; \
fi && \
/bin/launchctl bootstrap system '\(kanataFinal)' 2>/dev/null || /bin/echo Kanata service already loaded && \
/bin/launchctl bootstrap system '\(vhidDaemonFinal)' 2>/dev/null || /bin/echo VHID daemon already loaded && \
/bin/launchctl bootstrap system '\(vhidManagerFinal)' 2>/dev/null || /bin/echo VHID manager already loaded && \
/bin/echo Installation completed successfully
"""

print("Raw command length: \(command.count) characters")
print("\nRaw command:")
print(command)
print()

// Apply escaping
let escapedCommand = escapeForAppleScript(command)
print("Escaped command length: \(escapedCommand.count) characters")
print("\nEscaped command:")
print(escapedCommand)
print()

// Create the full osascript command
let osascriptCommand = """
do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs administrator access to install LaunchDaemon services, create configuration files, and start the keyboard services. This will be a single prompt."
"""

print("Full osascript command length: \(osascriptCommand.count) characters")
print("\nFull osascript command:")
print(osascriptCommand)
print()

// Check if the command is too long - macOS has limits on argument length
if osascriptCommand.count > 262144 {  // 256KB limit
    print("⚠️  WARNING: Command is very long (\(osascriptCommand.count) chars) - this might cause issues")
} else {
    print("✅ Command length is acceptable (\(osascriptCommand.count) chars)")
}

print("\n🧪 Would you like to test this exact command? (y/n)")
print("This will try to show the admin dialog with the real wizard command...")
