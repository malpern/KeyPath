#!/usr/bin/swift

import Foundation

// Create a simple script that uses KeyPath's own restart functionality
let script = """
tell application "System Events"
    -- Force quit the running KeyPath if any
    try
        do shell script "pkill -f KeyPath" with administrator privileges
    end try

    -- Wait a moment
    delay 1

    -- Launch KeyPath and trigger wizard
    do shell script "open /Users/malpern/Dropbox/code/KeyPath/build/KeyPath.app"

    -- Wait for app to load
    delay 3

    -- Send Command+W to open wizard (if that's the shortcut)
    tell application "KeyPath"
        activate
    end tell

    -- Use keystroke to open wizard - this might need adjustment based on KeyPath's UI
    key code 13 using command down -- Command+W

end tell
"""

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", script]

do {
    try task.run()
    task.waitUntilExit()
    print("Attempted to restart KeyPath and open wizard")
} catch {
    print("Error: \(error)")
}
