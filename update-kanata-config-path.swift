#!/usr/bin/swift

import Foundation

print("🔄 Updating Kanata service to use ~/.config/keypath/keypath.kbd...")

let serviceID = "com.keypath.kanata"
let oldConfigPath = "/usr/local/etc/kanata/keypath.kbd"
let newConfigPath = "/Users/malpern/.config/keypath/keypath.kbd"

// Stop and remove old service, then install new service with correct config path
let script = """
echo "Stopping old Kanata service..." && \
launchctl bootout system/\(serviceID) 2>/dev/null || echo "Service not loaded" && \
rm -f /Library/LaunchDaemons/\(serviceID).plist && \
echo "Creating new plist with ~/.config/ path..." && \
cat > /Library/LaunchDaemons/\(serviceID).plist << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(serviceID)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata</string>
        <string>--cfg</string>
        <string>\(newConfigPath)</string>
        <string>--watch</string>
        <string>--debug</string>
        <string>--log-layer-changes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/kanata.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/kanata.log</string>
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
PLIST_EOF
echo "Setting plist permissions..." && \
chown root:wheel /Library/LaunchDaemons/\(serviceID).plist && \
chmod 644 /Library/LaunchDaemons/\(serviceID).plist && \
echo "Starting new service..." && \
launchctl bootstrap system /Library/LaunchDaemons/\(serviceID).plist && \
echo "Service updated successfully!"
"""

let osascriptCommand = "do shell script \"\(script)\" with administrator privileges with prompt \"KeyPath needs to update the Kanata service to use the new ~/.config/keypath configuration location.\""

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", osascriptCommand]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    if task.terminationStatus == 0 {
        print("✅ Kanata service updated successfully!")
        print("📍 Now using: \(newConfigPath)")
        print("🔍 Output: \(output)")

        // Verify new service is running
        sleep(2)
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/bin/ps")
        checkTask.arguments = ["aux"]

        let checkPipe = Pipe()
        checkTask.standardOutput = checkPipe

        try checkTask.run()
        checkTask.waitUntilExit()

        let checkData = checkPipe.fileHandleForReading.readDataToEndOfFile()
        let checkOutput = String(data: checkData, encoding: .utf8) ?? ""

        let kanataLines = checkOutput.components(separatedBy: .newlines).filter {
            $0.contains("kanata") && !$0.contains("grep") && $0.contains("/usr/local/bin/kanata")
        }

        if !kanataLines.isEmpty {
            print("\n🎯 New Kanata service status:")
            for line in kanataLines {
                print("  \(line)")
                if line.contains(".config/keypath") {
                    print("  ✅ Confirmed: Using new ~/.config/keypath path!")
                }
            }
        }

    } else {
        print("❌ Failed to update service: \(output)")
    }
} catch {
    print("❌ Error: \(error)")
}
