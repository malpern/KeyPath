# Kanata macOS Integration - Complete Debugging Guide

This document contains comprehensive debugging information for Kanata keyboard remapping integration on macOS, based on extensive real-world debugging sessions.

## Table of Contents
- [Quick Reference](#quick-reference)
- [The "Zombie Keyboard Capture" Issue](#the-zombie-keyboard-capture-issue)
- [Thread Safety in Swift Apps](#thread-safety-in-swift-apps)
- [VirtualHID Connection Issues](#virtualhid-connection-issues)
- [Common Problems & Solutions](#common-problems--solutions)
- [Debugging Workflows](#debugging-workflows)
- [Architecture & Best Practices](#architecture--best-practices)

---

## Quick Reference

### Emergency Recovery
If keyboard becomes unresponsive:
1. **Kanata Emergency Sequence**: `Left Ctrl + Space + Esc` (works even when keyboard seems dead)
2. **Kill all processes**: `sudo pkill -f kanata`
3. **Restart VirtualHID daemon**: Kill and restart Karabiner daemon

### Key Diagnostic Commands
```bash
# Check if Kanata is working (look for key events in output)
timeout 5s sudo kanata --cfg /path/to/config.kbd --debug

# Check daemon status
ps aux | grep -i karabiner | grep -v grep

# Monitor real-time logs
tail -f ~/Library/Logs/KeyPath/keypath-debug.log
```

---

## The "Zombie Keyboard Capture" Issue

### Problem Description
**"Zombie Keyboard Capture"** occurs when Kanata successfully captures keyboard input but fails to establish proper output connection, leaving the keyboard unresponsive.

**Symptoms:**
- Keyboard becomes completely unresponsive
- Kanata appears to be running (process exists)
- Logs show `connect_failed asio.system:61` errors
- Emergency sequence (Ctrl+Space+Esc) still works

### Root Cause Analysis
Based on extensive debugging, the issue has multiple components:

1. **VirtualHID Connection Failures**: `connect_failed asio.system:61` 
2. **Karabiner Daemon Permission Issues**: Daemon runs but can't bind properly
3. **Multiple Process Conflicts**: Concurrent Kanata starts causing exclusive access errors

### Critical Discovery
**The `connect_failed asio.system:61` errors are NOT fatal!**

Our testing revealed that Kanata continues to process keyboard events and perform remapping even with these connection errors. The key insight is that these are warnings, not blocking failures.

### The Real Fix
The solution is **not** eliminating the connection errors, but:

1. **Ensuring Karabiner daemon is running** (even with permission warnings)
2. **Preventing multiple concurrent Kanata instances**
3. **Implementing automatic recovery in the app**
4. **Adding proper thread-safety to prevent crashes during recovery**

### Testing Evidence
Manual testing showed:
```bash
# This works despite connection errors:
sudo kanata --cfg config.kbd --debug
# Output shows:
# - connect_failed asio.system:61  ← WARNING, not fatal
# - KeyEvent processing continues   ← ACTUAL FUNCTIONALITY WORKS
# - Key remapping operates correctly ← PROVES IT'S WORKING
```

---

## Thread Safety in Swift Apps

### The Problem
Swift's `@Published` properties are not thread-safe when modified from multiple concurrent contexts, even when using `@MainActor`.

**Common Error:**
```
Unlock of an os_unfair_lock not owned by current thread
```

### Root Cause
Multiple `updateStatus()` calls can create race conditions when:
1. Different tasks call `updateStatus()` simultaneously
2. Individual `MainActor.run` blocks execute concurrently
3. `@Published` properties are modified from different threads

### The Solution
**Centralized State Management Pattern:**

```swift
/// Main actor function to safely update all @Published properties
@MainActor
private func updatePublishedProperties(
    isRunning: Bool,
    lastProcessExitCode: Int32?,
    lastError: String?,
    shouldClearDiagnostics: Bool = false
) {
    self.isRunning = isRunning
    self.lastProcessExitCode = lastProcessExitCode
    self.lastError = lastError
    
    if shouldClearDiagnostics {
        // Atomically clear diagnostics
        let initialCount = diagnostics.count
        diagnostics.removeAll { diagnostic in
            diagnostic.category == .process || 
            diagnostic.category == .permissions ||
            (diagnostic.category == .conflict && diagnostic.title.contains("Exit"))
        }
        // ... logging
    }
}
```

**Replace all scattered `MainActor.run` blocks:**
```swift
// ❌ WRONG - Can cause race conditions
await MainActor.run {
    self.isRunning = false
    self.lastError = error
}
await MainActor.run {
    self.clearProcessDiagnostics()
}

// ✅ CORRECT - Atomic state update
await updatePublishedProperties(
    isRunning: false,
    lastProcessExitCode: exitCode,
    lastError: error,
    shouldClearDiagnostics: true
)
```

### Testing Thread Safety
Signs your fix worked:
- App runs without crashes during state transitions
- No more `os_unfair_lock` errors in crash reports
- UI remains responsive during Kanata start/stop operations

---

## VirtualHID Connection Issues

### Understanding the Error Messages

**Karabiner Daemon Permission Errors:**
```
[client] [error] virtual_hid_device_service_server: bind_failed: Permission denied
```
- **Impact**: Warnings only, not fatal
- **Cause**: Daemon needs elevated permissions to bind properly
- **Solution**: Start daemon with regular user (it will still work)

**Kanata Connection Errors:**
```
connect_failed asio.system:61
```
- **Impact**: Warnings only, remapping still works
- **Cause**: VirtualHID connection handshake issues
- **Solution**: Restart daemon, but functionality continues regardless

### Daemon Management
```bash
# Start daemon (permission warnings are normal)
"/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon" &

# Check daemon is running
ps aux | grep -i karabiner | grep -v grep

# Expected output:
# _driverkit  XXX  ... DriverKit extension (system)
# malpern     XXX  ... VirtualHIDDevice-Daemon (user process)
```

### When VirtualHID Issues Are NOT the Problem
If you see these, the issue is elsewhere:
- Kanata debug output shows key events being processed
- `Attempting to write InputEvent` messages appear
- Emergency sequence (Ctrl+Space+Esc) works normally

---

## Common Problems & Solutions

### 1. Keyboard Becomes Unresponsive
**Symptoms:**
- No key input registers

---

## Lessons from the Hold-Label/Hyper Debugging (Dec 2025)

- **Lock down emitters first**: Verify Kanata + simulator outputs (canonical key names, no glyphs) with unit tests before touching the overlay; prevents UI hacks chasing upstream drift.
- **Instrument early, narrowly**: Add small, always-on log breadcrumbs at each hop (`KeyInput → HoldActivated → ViewModel state → Overlay render`) to see where labels drop.
- **Tunable jitter handling**: Keep debounce/grace periods as named constants with comments on the trade-off (flicker vs. linger); makes rapid iteration safe.
- **Separate behavior vs. presentation**: Handle tap/hold decisions upstream; keep overlay changes purely visual (e.g., label size/weight), reducing regression risk.
- **Cache with intent and expiry**: Short TTL caches for simulator-resolved labels avoid redundant work while keeping stale values out.
- **Simulator fidelity is critical**: Tests should assert simulator emits Kanata names (not glyphs) and expected action strings; a small mismatch caused the star label regression.
- **Have a repeatable pipeline checklist**: A written “input to overlay” flow saves time when timing bugs appear again.
- Kanata process running
- Logs show connection errors

**Debugging:**
```bash
# Test if Kanata is actually processing events
timeout 5s sudo kanata --cfg /path/to/config.kbd --debug
# Look for: KeyEvent messages, InputEvent writes
```

**Solutions (in order):**
1. Use emergency sequence: `Left Ctrl + Space + Esc`
2. Kill Kanata: `sudo pkill -f kanata`
3. Restart daemon: Kill and restart Karabiner daemon
4. Check for multiple instances: `ps aux | grep kanata`

### 2. Multiple Kanata Instances
**Error Pattern:**
```
entering the processing loop
entering the event loop
IOHIDDeviceOpen error: (iokit/common) exclusive access and device already open
[ERROR] failed to open keyboard device(s): Couldn't register any device
```

**Common Cause: karabiner_grabber Running**
This error often occurs because `karabiner_grabber` is already capturing keyboard input. Karabiner uses both system-level LaunchDaemons and user-level LaunchAgents:

```bash
# Check if karabiner_grabber is running
ps aux | grep karabiner_grabber | grep -v grep

# Check system-level services
sudo launchctl list | grep karabiner_grabber

# Check user-level services  
launchctl list | grep karabiner_grabber

# Comprehensive removal (requires admin privileges)
# Stop system LaunchDaemon
sudo launchctl bootout system "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Privileged Daemons.app/Contents/Library/LaunchDaemons/org.pqrs.service.daemon.karabiner_grabber.plist" 2>/dev/null

# Stop user LaunchAgent  
launchctl bootout gui/$(id -u) "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents.app/Contents/Library/LaunchAgents/org.pqrs.service.agent.karabiner_grabber.plist" 2>/dev/null

# Kill any remaining processes
sudo pkill -f karabiner_grabber
sudo pkill -9 -f karabiner_grabber  # Force kill stubborn processes
```

**Prevention in Code:**
```swift
// Always check before starting
if isRunning {
    AppLogger.shared.log("✅ [Init] Kanata already running - skipping")
    return
}

// Use actor-based synchronization
await KanataManager.startupActor.synchronize {
    await self.performStartKanata()
}
```

### 3. Thread Safety Crashes
**Error:**
```
Unlock of an os_unfair_lock not owned by current thread
```

**Fix:**
- Implement centralized state management
- Use single `@MainActor` function for all `@Published` property updates
- Remove scattered `MainActor.run` blocks

### 4. Permission Issues
**Kanata won't start:**
```bash
# Test basic permissions
sudo kanata --version

# Check sudoers configuration
sudo -l | grep kanata
```

**macOS Specific Permission Requirements:**
1. **Input Monitoring**: System Settings > Privacy & Security > Input Monitoring
   - Add `/usr/local/bin/kanata` (or `/opt/homebrew/bin/kanata` on ARM Macs)
   - Add Terminal.app or your terminal (e.g., Ghostty)
   - Add KeyPath.app if using the GUI

2. **Karabiner Driver Extension**: System Settings > Privacy & Security > Driver Extensions
   - Enable `Karabiner-VirtualHIDDevice-Manager.app`

3. **Login Items & Extensions**: System Settings > General > Login Items & Extensions
   - Enable "Karabiner-Elements Non-Privileged Agents"
   - Enable "Karabiner-Elements Privileged Daemons"

**Required sudoers entries:**
```bash
# Add to /etc/sudoers via sudo visudo
username ALL=(ALL) NOPASSWD: /usr/local/bin/kanata
username ALL=(ALL) NOPASSWD: /usr/bin/pkill -f kanata
```

### 5. Configuration Errors
**Always validate before starting:**
```bash
sudo kanata --cfg /path/to/config.kbd --check
```

**Safe config template:**
```lisp
;; Safe configuration template
(defcfg
  process-unmapped-keys no  ;; IMPORTANT: Only process mapped keys
)

(defsrc
  caps
)

(deflayer base
  esc
)
```

---

## Debugging Workflows

### Initial Problem Assessment
1. **Check if Kanata is running**: `ps aux | grep kanata`
2. **Test configuration**: `sudo kanata --cfg config.kbd --check`
3. **Review recent logs**: `tail -50 ~/Library/Logs/KeyPath/keypath-debug.log`
4. **Check daemon status**: `ps aux | grep karabiner`

### Deep Debugging Session
```bash
# 1. Clean slate
sudo pkill -f kanata
pkill -f "Karabiner-VirtualHIDDevice-Daemon"

# 2. Start daemon
"/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon" > /tmp/karabiner-daemon.log 2>&1 &

# 3. Test Kanata manually with debug output
timeout 10s sudo kanata --cfg /path/to/config.kbd --debug --log-layer-changes

# 4. Look for key processing evidence
# - KeyEvent messages
# - InputEvent writes  
# - Layer changes
# - Emergency sequence recognition
```

### App Integration Testing
```bash
# 1. Monitor app logs in real-time
tail -f ~/Library/Logs/KeyPath/keypath-debug.log

# 2. Start app and observe initialization
open -a KeyPath

# 3. Watch for thread safety issues
# - No os_unfair_lock crashes
# - Clean state transitions
# - Proper error handling

# 4. Test recovery systems
# - Use emergency sequence if keyboard becomes unresponsive
# - Check automatic recovery attempts in logs
```

### Log Analysis Patterns
```bash
# Find Kanata process lifecycle
grep -E "(Starting Kanata|Successfully started|process exited)" debug.log

# Check for thread safety issues
grep -E "(MainActor|updateStatus|clearProcessDiagnostics)" debug.log

# Look for VirtualHID connection issues
grep -E "(connect_failed|asio\.system:61)" debug.log

# Track automatic recovery attempts
grep -E "(Recovery|attemptKeyboardRecovery|zombie)" debug.log
```

---

## Architecture & Best Practices

### Process Management
```swift
// Proper sudo-based Kanata execution
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
task.arguments = ["/usr/local/bin/kanata", "--cfg", configPath, "--debug"]

// Monitor output in real-time
let outputPipe = Pipe()
let errorPipe = Pipe()
task.standardOutput = outputPipe
task.standardError = errorPipe

// Termination works through sudo wrapper
if let process = kanataProcess, process.isRunning {
    process.terminate()  // Properly kills both sudo and kanata
}
```

### Configuration Management
```swift
// Always validate before starting
func validateConfigFile() -> (isValid: Bool, errors: [String]) {
    guard FileManager.default.fileExists(atPath: configPath) else {
        return (false, ["Config file does not exist"])
    }
    
    // Use --check flag for validation
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    task.arguments = ["/usr/local/bin/kanata", "--cfg", configPath, "--check"]
    
    // ... execute and parse result
}
```

### Error Recovery
```swift
// Automatic recovery for VirtualHID connection failures
private func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
    switch exitCode {
    case 6:
        if output.contains("connect_failed asio.system:61") {
            // This is "zombie keyboard capture" - attempt recovery
            diagnostics.append(KanataDiagnostic(
                title: "VirtualHID Connection Failed",
                description: "Kanata captured keyboard but failed VirtualHID connection",
                canAutoFix: true
            ))
            
            Task {
                await attemptKeyboardRecovery()
            }
        }
    }
}

private func attemptKeyboardRecovery() async {
    AppLogger.shared.log("🚨 [Recovery] Attempting keyboard recovery")
    
    // Step 1: Kill all Kanata processes
    await killAllKanataProcesses()
    
    // Step 2: Wait for keyboard release
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    
    // Step 3: Restart VirtualHID daemon
    await restartKarabinerDaemon()
    
    // Step 4: Retry Kanata start
    await startKanata()
}
```

### Thread Safety Pattern
```swift
// Centralized state management
@MainActor
private func updatePublishedProperties(
    isRunning: Bool,
    lastProcessExitCode: Int32?,
    lastError: String?,
    shouldClearDiagnostics: Bool = false
) {
    // All @Published property modifications happen atomically here
    self.isRunning = isRunning
    self.lastProcessExitCode = lastProcessExitCode
    self.lastError = lastError
    
    if shouldClearDiagnostics {
        // Integrated diagnostics clearing prevents race conditions
        let initialCount = diagnostics.count
        diagnostics.removeAll { diagnostic in
            diagnostic.category == .process || 
            diagnostic.category == .permissions ||
            (diagnostic.category == .conflict && diagnostic.title.contains("Exit"))
        }
        
        let removedCount = initialCount - diagnostics.count
        if removedCount > 0 {
            AppLogger.shared.log("🔄 [Diagnostics] Cleared \(removedCount) stale diagnostics")
        }
    }
}

// Usage throughout the app
await updatePublishedProperties(
    isRunning: false,
    lastProcessExitCode: exitCode,
    lastError: errorMessage,
    shouldClearDiagnostics: true
)
```

---

## Manual Kanata Setup Without KeyPath

### Prerequisites
Before running Kanata manually, ensure all Karabiner-Elements components are properly configured:

1. **Install Karabiner-Elements** (if not already installed)
2. **Enable Driver Extension** (System Settings > Privacy & Security > Driver Extensions)
3. **Enable Background Services** (System Settings > General > Login Items & Extensions)
   - Karabiner-Elements Non-Privileged Agents ✓
   - Karabiner-Elements Privileged Daemons ✓
4. **Grant Input Monitoring** to kanata binary and terminal
5. **Disable karabiner_grabber** to prevent conflicts

### Manual Startup Procedure
```bash
# 1. Comprehensive Karabiner grabber cleanup
# Stop system LaunchDaemon
sudo launchctl bootout system "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Privileged Daemons.app/Contents/Library/LaunchDaemons/org.pqrs.service.daemon.karabiner_grabber.plist" 2>/dev/null

# Stop user LaunchAgent  
launchctl bootout gui/$(id -u) "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents.app/Contents/Library/LaunchAgents/org.pqrs.service.agent.karabiner_grabber.plist" 2>/dev/null

# Kill any remaining processes
sudo pkill -f karabiner_grabber
sudo pkill -f kanata

# 2. Start Karabiner VirtualHID daemon (if not running)
"/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon" &

# 3. Start Kanata with your config
sudo kanata --cfg "/path/to/your/config.kbd"
```

### Important Notes
- **Permission errors are normal**: VirtualHID daemon shows `bind_failed: Permission denied` but still works
- **Connection warnings are not fatal**: `connect_failed asio.system:61` messages don't prevent functionality
- **Keyboard may briefly freeze**: Use emergency sequence (Ctrl+Space+Esc) if needed

## KeyPath Installation Wizard - Comprehensive System Checks

### What the Wizard CHECKS (Updated 2025)
✅ **Kanata binary installation** - Verifies kanata executable exists  
✅ **Karabiner driver files exist** - Checks `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice`  
✅ **VirtualHIDDevice-Daemon running** - Verifies daemon process is active  
✅ **Driver Extension actually enabled** - Uses `systemextensionsctl` to verify `[activated enabled]` status  
✅ **Background services enabled** - Checks if Login Items & Extensions services are running  
✅ **karabiner_grabber conflicts** - Detects conflicting grabber processes  
✅ **Input Monitoring permissions** - KeyPath.app and kanata binary TCC database checks  
✅ **Accessibility permissions** - KeyPath.app system access verification  
✅ **Service running status** - Separate check for whether Kanata is actually running

### Automatic Conflict Resolution
The wizard can now **auto-fix** several issues:
- 🔧 **Kill conflicting karabiner_grabber** automatically (comprehensive system+user service removal)
- 🔧 **Restart VirtualHID daemon** if needed
- 🔧 **Install/uninstall LaunchDaemon** services
- 🔧 **Create config directories and files**

### Karabiner Grabber Conflict Resolution (Advanced)
**Problem**: Karabiner Elements runs grabber services at both system and user levels that auto-restart when killed.

**KeyPath Solution**: Comprehensive service shutdown that prevents restarts:
1. **Stop system LaunchDaemon**: `org.pqrs.service.daemon.karabiner_grabber` 
2. **Stop user LaunchAgent**: `org.pqrs.service.agent.karabiner_grabber`
3. **Kill remaining processes**: Force-kill any stubborn grabber processes
4. **Verify success**: Check that no grabber processes remain running
5. **Preserve VirtualHID**: Keep the HID driver daemon that Kanata needs

**Important**: This only stops the keyboard **grabber** service, not the **VirtualHID driver** that both Karabiner and Kanata require for proper operation.

### Manual Action Still Required
❌ **Enable Driver Extension** - Must be done in System Settings > Privacy & Security > Driver Extensions  
❌ **Enable Login Items & Extensions** - Must add Karabiner services manually (see detailed steps below)  
❌ **Grant Input Monitoring** - Must add binaries in System Settings > Privacy & Security  
❌ **Grant Accessibility** - Must enable for KeyPath.app in System Settings

### Enabling Karabiner Background Services (Critical Step)

**Problem**: Karabiner background services may not appear in System Settings > General > Login Items & Extensions by default.

**Solution**: Manually add them as Login Items:

1. **Open System Settings > General > Login Items & Extensions**
2. **Click the "Open at Login" section in the left sidebar**
3. **Click the "+" button to add new items**
4. **Navigate to**: `/Library/Application Support/org.pqrs/Karabiner-Elements/`
5. **Add these two applications** (drag & drop or use + button):
   - `Karabiner-Elements Non-Privileged Agents.app`
   - `Karabiner-Elements Privileged Daemons.app`
6. **Restart your Mac** or log out/log in for changes to take effect

**KeyPath Detection Fix (Updated 2025)**:
- KeyPath now has a **dedicated Background Services wizard page** with its own icon
- Fixed detection pattern: now correctly identifies `org.pqrs.service.agent.karabiner_*` services
- Background Services issues are separated from Input Monitoring permissions

**KeyPath Automation Tools**:
- 🔧 **"Help" button** - Shows detailed step-by-step instructions with helpful tools
- 📁 **"Open Karabiner Folder"** - Opens Finder directly to the Karabiner apps location
- 📋 **"Copy File Paths"** - Copies full paths to clipboard for easy navigation
- ⚙️ **One-click setup** - Background Services cards automatically open both System Settings and Finder

**Verification**: After restart, check that services are running:
```bash
launchctl list | grep -i karabiner
# Expected: Multiple karabiner services with PIDs (not "-")
# Example output:
# 10916	0	org.pqrs.service.agent.Karabiner-Menu
# 10919	0	org.pqrs.service.agent.Karabiner-NotificationWindow
# 10221	0	org.pqrs.service.agent.karabiner_console_user_server
# 10223	0	org.pqrs.service.agent.karabiner_session_monitor
```

**Common Issues**:
- **Services don't appear in "By Category" view**: They will show up in "Open at Login" after manual addition
- **KeyPath shows "Background Services Disabled"**: This was a detection bug fixed in 2025 - the wizard now correctly detects running services
- **Services show as disabled despite manual addition**: Make sure you added the `.app` files (not the `.plist` files) to Login Items

### Wizard UI States

**🟢 All Active (Green):**
- All components installed AND Kanata service running
- Shows green check icon with "Close Setup" button (no status text)

**🟠 Ready but Not Running (Orange):**
- All components installed but Kanata service not running
- Shows "Service Not Running" with "Start Kanata Service" button
- Prevents misleading "all green" when service is actually stopped

**🔴 Setup Issues (Red/Gray):**
- Missing components or conflicts detected
- Shows specific issues and required actions

### Advanced Verification Commands
For debugging when the comprehensive wizard checks still miss issues:

```bash
# 1. Verify driver extension system status
systemextensionsctl list | grep -i karabiner
# Expected: [activated enabled]

# 2. Check system-level Karabiner services
sudo launchctl list | grep -i karabiner
# Expected: system-level daemon entries

# 3. Verify user-level background services  
launchctl list | grep -i karabiner
# Expected: user-level service entries

# 4. Check for any grabber conflicts
ps aux | grep karabiner_grabber | grep -v grep
# Expected: empty (no conflicts)

# 5. Test kanata can access HID devices
sudo kanata --cfg /path/to/config.kbd --check
# Expected: no errors, clean validation

# 6. Verify TCC permissions database
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, allowed FROM access WHERE service='kTCCServiceListenEvent';"
# Expected: KeyPath and kanata entries with allowed=1
```

## Key Lessons Learned

### 1. Connection Errors Are Not Fatal
The biggest breakthrough was realizing that `connect_failed asio.system:61` errors don't prevent Kanata from working. Manual testing proved that keyboard remapping continues to function despite these warnings.

### 2. Thread Safety Requires Centralization
Scattered `MainActor.run` blocks create race conditions. The solution is centralized state management with a single `@MainActor` function handling all `@Published` property updates.

### 3. VirtualHID Daemon Permissions Are Complex
The daemon will run and provide basic functionality even with permission warnings. Don't let permission errors in logs mislead you into thinking the system isn't working.

### 4. Emergency Recovery Is Critical
Always implement and document the Kanata emergency sequence (`Left Ctrl + Space + Esc`). This works even when the keyboard appears completely unresponsive.

### 5. Manual Testing Reveals Truth
When app integration fails, test Kanata manually to isolate whether the issue is with Kanata itself or the app's process management.

### 6. Automatic Recovery Must Be Thread-Safe
Recovery systems that attempt to restart processes must handle concurrent access properly, or they'll crash during the very scenarios they're designed to fix.

---

## References

- [Kanata GitHub](https://github.com/jtroo/kanata) - Main keyboard remapper project
- [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) - macOS HID driver
- [IOHIDFamily Documentation](https://developer.apple.com/documentation/iokit/iohidfamily) - Apple's HID framework
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html) - Thread safety with async/await

---

## Troubleshooting Checklist

When debugging Kanata issues:

- [ ] Is Kanata actually processing key events? (Check debug output)
- [ ] Are there multiple Kanata instances? (`ps aux | grep kanata`)
- [ ] Is karabiner_grabber running? (`ps aux | grep karabiner_grabber`)
- [ ] Are both system and user grabber services stopped? (`sudo launchctl list | grep karabiner_grabber` and `launchctl list | grep karabiner_grabber`)
- [ ] Is Karabiner daemon running? (`ps aux | grep karabiner`)
- [ ] Does config validate? (`sudo kanata --cfg config.kbd --check`)
- [ ] Are there thread safety crashes? (Check crash reports)
- [ ] Can you use emergency sequence? (`Left Ctrl + Space + Esc`)
- [ ] Are VirtualHID connection errors blocking functionality? (Usually no!)
- [ ] Is the app's automatic recovery working? (Check logs)
- [ ] Driver Extension enabled? (`systemextensionsctl list | grep karabiner`)
- [ ] Background services enabled? (Check Login Items & Extensions - manually add if missing)
- [ ] Karabiner Login Items manually added? (`Karabiner-Elements Non-Privileged Agents.app` and `Karabiner-Elements Privileged Daemons.app`)
- [ ] Input Monitoring granted? (Check System Settings)

Remember: Many "errors" in logs are actually warnings. Focus on whether the core functionality (key remapping) is working, not whether all log messages are clean.
