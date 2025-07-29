# SMAppService XPC Connection Debugging - Learnings

## The Problem
After migrating from SMJobBless to SMAppService on macOS 13+, the privileged helper daemon would appear to register successfully (`SMAppServiceStatus: enabled`) but XPC connections would fail with:
```
XPC connection error: Couldn't communicate with a helper application.
```

## Root Cause
**SMAppService requires the Info.plist to be embedded in the helper binary for proper validation after notarization.**

Without the embedded Info.plist:
- SMAppService reports successful registration 
- The daemon appears in System Settings → Login Items
- But the daemon never actually starts or accepts XPC connections
- `sudo launchctl list` shows no trace of the service

## The Solution

### 1. Embed Info.plist in Helper Binary
Modify the build process to embed the helper's Info.plist during compilation:

```bash
# Build helper with embedded Info.plist
swift build --configuration release --product KeyPathHelper \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker Sources/KeyPathHelper/Info.plist
```

**Verification**: Check if Info.plist is embedded:
```bash
# Should show Info.plist entries > 0
codesign -dv /path/to/helper/binary

# Should show __info_plist section
otool -l /path/to/helper/binary | grep -A 5 "__info_plist"
```

### 2. Use Absolute Paths in Daemon Plist
The launchd plist must use absolute paths to the helper binary:

```xml
<key>Program</key>
<string>/full/path/to/KeyPath.app/Contents/MacOS/KeyPathHelper</string>
```

Not relative paths like:
```xml
<key>Program</key>
<string>Contents/MacOS/KeyPathHelper</string>  <!-- WRONG -->
```

### 3. Reset Background Task Management
When making changes to SMAppService daemons, always reset the background task cache:

```bash
sudo sfltool resetbtm
# Restart computer
```

This clears corrupted registration states that can persist even after fixing the underlying issues.

## Debugging Steps

### Check SMAppService Status
```swift
let service = SMAppService.daemon(plistName: "com.example.helper.plist")
print("Status: \(service.status)")
// Should be .enabled (1) when working
```

### Check if Daemon is Actually Running
```bash
# Should show the daemon if properly registered
sudo launchctl list | grep your-daemon-identifier
```

### Check XPC Connection Logs
Add detailed XPC logging to identify connection failures:
```swift
connection.invalidationHandler = {
    print("❌ XPC connection invalidated")
}
connection.interruptionHandler = {
    print("⚠️ XPC connection interrupted")
}
```

### Enable System Logging
For deeper diagnosis:
```bash
sudo log stream --debug --info --predicate "process in { 'YourApp', 'smd', 'backgroundtaskmanagementd'} and sender in {'ServiceManagement', 'BackgroundTaskManagement', 'smd', 'backgroundtaskmanagementd'}"
```

## Common Error Codes

| Error Code | Meaning | Solution |
|------------|---------|----------|
| Code 3 + -67028/-67056 | Codesigning failure | Embed Info.plist in helper binary |
| Code 111 | Invalid Program/ProgramArguments | Use absolute paths in daemon plist |
| Code 22 | Invalid argument | Service in broken state, reset with `sfltool resetbtm` |

## Known Issues

### macOS Version Compatibility
- **Ventura 13.0.1 - 13.1**: Known SMAppService bugs, upgrade to 13.5+
- **Ventura 13.6**: Daemon may not disable properly (Apple FB13206906)
- **Sonoma 14.2+**: Generally works well

### Background Item Persistence
After using `sfltool resetbtm`, items may still appear in System Settings → Login Items. This is intentional to preserve user preferences, but the underlying registration is cleared.

### Code Signature Changes
Any change to code signatures requires:
1. `sudo sfltool resetbtm`
2. Restart computer
3. Re-approve background item when prompted

## Prevention

### Build Process Checklist
- [ ] Info.plist embedded in helper binary
- [ ] Helper signed with same certificate as main app
- [ ] Daemon plist uses absolute paths
- [ ] SMPrivilegedExecutables entry matches helper signature
- [ ] App properly notarized and stapled

### Testing Checklist
- [ ] `sudo launchctl list | grep daemon` shows running service
- [ ] XPC connection establishes without errors
- [ ] Background item appears in System Settings
- [ ] Helper responds to XPC calls

## References
- [Peter Steinberger's SMAppService Article](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears) - Critical reference for Info.plist embedding
- [Apple SMAppService Documentation](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple Developer Forums - Service Management](https://developer.apple.com/forums/tags/servicemanagement)

## Emergency Recovery
If SMAppService gets completely stuck:
1. `sudo sfltool resetbtm`
2. Remove app from `/Applications`
3. Restart computer
4. Reinstall app with proper configuration

This usually resolves any persistent registration issues.

---

# Kanata macOS Integration - Learnings

## The Problem
KeyPath transitioned from SMAppService privileged helpers to using Kanata directly as a keyboard remapper. However, Kanata was failing to start with the error:
```
IOHIDDeviceOpen error: (iokit/common) privilege violation
failed to open keyboard device(s): Couldn't register any device
```

## Root Cause
**Kanata requires root privileges on macOS to access IOHIDDevice for keyboard input/output.**

Unlike on Linux where Kanata can run as a regular user with proper udev rules, macOS requires root access for:
- Opening HID devices for input capture
- Creating virtual HID devices for output
- Bypassing System Integrity Protection for low-level keyboard access

## The Solution

### 1. Configure Passwordless Sudo for Kanata
Add entries to `/etc/sudoers` (use `sudo visudo`):
```bash
# Allow user to run kanata as root without password
username ALL=(ALL) NOPASSWD: /usr/local/bin/kanata
username ALL=(ALL) NOPASSWD: /usr/bin/pkill -f kanata
```

### 2. Modify Process Execution in Swift
Update the KanataManager to use sudo when launching Kanata:

```swift
// ❌ WRONG - Runs as user, fails with privilege violation
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/local/bin/kanata")
task.arguments = ["--cfg", configPath, "--watch"]

// ✅ CORRECT - Runs as root via sudo
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
task.arguments = ["/usr/local/bin/kanata", "--cfg", configPath, "--watch"]
```

### 3. Ensure Karabiner-VirtualHIDDevice-Daemon is Running
Kanata integrates with Karabiner's virtual HID driver for better compatibility:

```bash
# Check if daemon is running
ps aux | grep -i karabiner | grep -v grep

# Start daemon manually if needed (requires admin)
sudo /Library/Application\ Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon
```

## Debugging Steps

### Verify Kanata Can Run as Root
```bash
# Test config validation
sudo kanata --cfg /path/to/config.kbd --check

# Test actual execution (with timeout)
timeout 10s sudo kanata --cfg /path/to/config.kbd
```

Expected successful output:
```
kanata v1.9.0 starting
process unmapped keys: false
config file is valid
Sleeping for 2s...
entering the processing loop
entering the event loop
connected
driver_activated 1
driver_connected 1
Starting kanata proper
```

### Check for Multiple Instances
Kanata fails if multiple instances try to access the same HID device:
```bash
# Kill all kanata processes
sudo pkill -f kanata

# Verify cleanup
ps aux | grep kanata | grep -v grep
```

### Verify Sudoers Configuration
```bash
# Test passwordless sudo
sudo -n /usr/local/bin/kanata --version

# Should NOT prompt for password if configured correctly
```

## Common Issues

### 1. "IOHIDDeviceOpen error: privilege violation"
**Cause**: Kanata running as regular user  
**Solution**: Use sudo to run as root

### 2. "Couldn't register any device" + "exclusive access"
**Cause**: Multiple Kanata instances running  
**Solution**: Kill all instances before starting new one

### 3. "Password required" when using sudo
**Cause**: Sudoers not configured for passwordless access  
**Solution**: Add NOPASSWD entries to sudoers file

### 4. Driver connection failures
**Cause**: Karabiner daemon not running  
**Solution**: Start Karabiner-VirtualHIDDevice-Daemon as admin

## Architecture Notes

### File-based Configuration
Kanata uses file watching (`--watch` flag) to reload configs automatically:
- Config path: `/usr/local/etc/kanata/keypath.kbd` (system-wide)
- Alternative: `~/Library/Application Support/KeyPath/keypath.kbd` (user-specific)

### Permission Requirements
- **App**: Accessibility permission (to detect when to show UI)
- **Kanata binary**: Input Monitoring permission + root privileges
- **User**: Sudoers entry for passwordless kanata execution

### Process Management
Swift Process API works well with sudo:
```swift
// Termination still works through the sudo wrapper
if let process = kanataProcess, process.isRunning {
    process.terminate()  // Properly kills sudo and kanata
}
```

## References
- [Kanata GitHub](https://github.com/jtroo/kanata) - Main keyboard remapper project
- [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) - macOS HID driver
- [IOHIDFamily Documentation](https://developer.apple.com/documentation/iokit/iohidfamily) - Apple's HID framework