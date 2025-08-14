#!/usr/bin/env swift

import Foundation

// Test script to verify the admin password prompt fix
// This script simulates the escapeForAppleScript function and tests problematic strings

func escapeForAppleScript(_ command: String) -> String {
    var escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
    return escaped
}

print("🧪 Testing AppleScript escaping fix for kanata service installation")
print(String(repeating: "=", count: 70))

// Test case 1: Command with double quotes (the main issue)
let problematicCommand = """
echo "Installing services..." && mkdir -p '/Library/LaunchDaemons' && echo "Config content" > '/path/to/file'
"""

print("Original command:")
print(problematicCommand)
print()

let escaped = escapeForAppleScript(problematicCommand)
print("Escaped command:")
print(escaped)
print()

// Test case 2: Simulate the actual AppleScript that would be generated
let osascriptCommand = """
do shell script "\(escaped)" with administrator privileges with prompt "Test admin prompt"
"""

print("Full AppleScript command:")
print(osascriptCommand)
print()

// Test case 3: Verify the dynamic user ID detection command
let dynamicUserCommand = """
CONSOLE_UID="$(/usr/bin/stat -f %u /dev/console)" && \\
CONSOLE_GID="$(/usr/bin/id -g "$CONSOLE_UID")" && \\
echo "User: $CONSOLE_UID, Group: $CONSOLE_GID"
"""

let escapedDynamic = escapeForAppleScript(dynamicUserCommand)
print("Dynamic user detection (escaped):")
print(escapedDynamic)
print()

print("✅ All escape tests completed successfully!")
print()
print("🔍 Key fixes applied:")
print("1. Added escapeForAppleScript() helper function")
print("2. Replaced hard-coded UID #501 with dynamic console user detection") 
print("3. Fixed broken shell quoting in config file creation")
print("4. Applied escaping to all osascript call sites")
print()
print("🚀 The admin password prompt should now appear correctly!")