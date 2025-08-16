# Dual-Process Hot Reload Conflict Analysis

## Root Cause Discovered ✅

**Issue**: Hot reload failing due to **two conflicting Kanata processes running simultaneously**

## Process Conflict Details

### Two Kanata Instances Found:
1. **System Service** (Root): PID 22579 - LaunchDaemon managed by macOS
2. **User Process** (Previous): PID 22205 - Launched directly by KeyPath app ❌

### Evidence of Dual Launch Mechanism

**KeyPath's KanataManager.swift** contains code that launches Kanata as a user process:

```swift
// Lines 999-1001 in KanataManager.swift
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
task.arguments = ["-n"] + buildKanataArguments(configPath: configPath)
```

**LaunchDaemon** also runs Kanata as system service:
```bash
# Current running service (PID 22579)
root  22579  /usr/local/bin/kanata --cfg /Users/malpern/.config/keypath/keypath.kbd --port 54141 --watch --debug --log-layer-changes
```

## How This Breaks Hot Reload

### The Conflict:
1. **System service** (root) detects file changes via `--watch`
2. **User process** (malpern) also monitors the same config file  
3. **Both processes** try to reload simultaneously
4. **File locking conflicts** prevent successful reload completion
5. **"Live reload successful" never happens** - reload gets stuck

### Log Evidence:
```
16:30:36.7046 [INFO] Config file changed: /Users/malpern/.config/keypath/keypath.kbd (event: Any), triggering reload
16:30:36.7047 [INFO] Requested live reload of file: /Users/malpern/.config/keypath/keypath.kbd
[NO SUCCESS MESSAGE - RELOAD STUCK]
```

## Architecture Problem

### Current (Broken) Setup:
```
KeyPath App → KanataManager.startKanata() → User Process (sudo kanata)
     +
macOS LaunchDaemon → System Service → Root Process (kanata)
     ↓
Two processes monitoring same config file = CONFLICT
```

### Correct Setup (Should Be):
```
KeyPath App → launchctl commands → LaunchDaemon → Single Root Process
     ↓
One process monitoring config file = Working hot reload
```

## KeyPath Code Analysis

**Problem Code** in `KanataManager.swift`:
- `startKanata()` method launches user processes with `Process()` + `sudo`
- This conflicts with existing LaunchDaemon system service
- Creates race conditions during file watching and hot reload

**KeyPath Debug Logs Show**:
```
[2025-08-15 10:07:16.998] 🚀 [Start] ========== KANATA START ATTEMPT ==========
[2025-08-15 10:07:16.998] ⚠️ [Start] Kanata is already running or starting - skipping start
[2025-08-15 10:07:16.998] ⚠️ [Start] Current state: isRunning=true, isStartingKanata=false, PID=-1
```

**The PID=-1 indicates KeyPath doesn't know about the LaunchDaemon process!**

## Solution for KeyPath Team

### 1. Remove Direct Process Launch
KeyPath should **never** launch Kanata directly via `Process()`. Instead:
- Use `launchctl` commands only
- Manage the LaunchDaemon service exclusively
- Remove `kanataProcess: Process?` property

### 2. Single Process Architecture
```swift
// Instead of Process() launch:
func startKanata() async {
    // Use launchctl to manage system service
    await runCommand("sudo", ["launchctl", "kickstart", "-k", "system/com.keypath.kanata"])
}
```

### 3. Process Detection Fix
KeyPath's process detection should find LaunchDaemon processes:
```swift
// Fix PID=-1 issue by detecting system service
func detectKanataProcess() -> Int? {
    // Check launchctl print output instead of local Process object
}
```

## Immediate Workaround

**For Users Experiencing This Issue:**
```bash
# Kill any user processes
pkill -f "kanata.*malpern"

# Restart only the system service  
sudo launchctl kickstart -k system/com.keypath.kanata

# Verify single process
ps aux | grep kanata
```

## Verification Test

After fix, hot reload should work with:
1. **Single root process** visible in `ps aux | grep kanata`
2. **Config changes** trigger file watcher
3. **"Live reload successful"** appears in logs
4. **Mappings update** immediately without manual restart

## Impact Assessment

### Current State:
- ❌ Hot reload completely broken
- ❌ Manual service restarts required
- ❌ Development workflow severely impacted
- ❌ Two conflicting processes fighting for file access

### After Fix:
- ✅ Hot reload works reliably
- ✅ Single process architecture
- ✅ Clean file watching without conflicts
- ✅ Proper service management

---

**Root Cause**: KeyPath launches user Kanata processes that conflict with LaunchDaemon system service, breaking hot reload file watching.

**Solution**: Remove direct process launching from KeyPath, use launchctl exclusively.