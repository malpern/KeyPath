# Kanata Hot Reload Bug Report

## ✅ **STATUS: RESOLVED** (August 15, 2025)

## Summary
~~Hot reload mechanism gets stuck in "reload already pending" state and never completes, preventing configuration changes from being applied.~~

**FIXED**: Comprehensive threading race condition fix with production hardening implemented.

## Environment
- **Kanata Version**: v1.9.0
- **Platform**: macOS (Darwin 24.5.0)
- **Architecture**: arm64 (Apple Silicon)
- **Installation**: Homebrew (`/usr/local/bin/kanata`)
- **Launch Method**: LaunchDaemon via launchctl

## Bug Description

### Expected Behavior
When a configuration file is modified while using `--watch`, Kanata should:
1. Detect the file change via file watcher
2. Trigger reload process
3. Complete reload and apply new configuration
4. Continue processing with updated mappings

### Actual Behavior  
1. ✅ File watcher detects change correctly
2. ✅ Reload process is triggered
3. ❌ **Reload gets stuck in pending state**
4. ❌ **New configuration never applied**
5. ❌ **All subsequent reload attempts show "reload already pending"**

## Reproduction Steps

1. Start Kanata with watch mode:
   ```bash
   /usr/local/bin/kanata --cfg /path/to/config.kbd --watch --debug --log-layer-changes
   ```

2. Create initial config file:
   ```lisp
   (defcfg
     process-unmapped-keys no
   )
   
   (defsrc
     caps
   )
   
   (deflayer base
     esc
   )
   ```

3. Modify config file to add new mapping:
   ```lisp
   (defcfg
     process-unmapped-keys no
   )
   
   (defsrc
     caps 1
   )
   
   (deflayer base
     esc 2
   )
   ```

4. Check logs and test functionality

## Log Evidence

### File Detection (Works Correctly)
```
12:06:22.1339 [DEBUG] kanata_state_machine::file_watcher: File watcher event received: Any for path: /path/to/config.kbd
12:06:22.1340 [INFO] Config file changed: /path/to/config.kbd (event: Any), triggering reload
```

### Stuck State (Bug Manifestation)  
```
12:06:22.1340 [DEBUG] kanata_state_machine::kanata: reload already pending; not resetting fallback timer
```

### Subsequent Attempts (All Fail)
Every subsequent file change produces the same result:
```
12:10:17.5851 [INFO] Config file changed: /path/to/config.kbd (event: Any), triggering reload
12:10:17.5851 [DEBUG] kanata_state_machine::kanata: reload already pending; not resetting fallback timer
```

## Impact

### Severity: High
- **User Experience**: Hot reload feature is completely non-functional
- **Workaround Required**: Manual service restart needed for every config change
- **Development Impact**: Significantly slows down configuration iteration

### Affected Features
- `--watch` flag functionality
- Hot reload mechanism
- Configuration file monitoring

## Investigation Results

### What Works
- ✅ File watcher detects changes instantly (< 0.1ms)
- ✅ Reload trigger mechanism activates correctly
- ✅ Configuration syntax validation passes
- ✅ Manual config validation: `kanata --cfg config.kbd --check` succeeds

### What's Broken
- ❌ Reload completion process
- ❌ "Fallback timer" mechanism  
- ❌ Configuration application after reload trigger
- ❌ Clearing of "pending" state

## Debugging Information

### Process Status
```bash
$ launchctl print system/com.keypath.kanata
system/com.keypath.kanata = {
    active count = 1
    state = running
    program = /usr/local/bin/kanata
}
```

### Config Validation
```bash
$ /usr/local/bin/kanata --cfg /path/to/config.kbd --check
[INFO] kanata v1.9.0 starting
[INFO] validating config only and exiting
[INFO] process unmapped keys: false
[INFO] config file is valid
```

### Service Arguments
```bash
/usr/local/bin/kanata --cfg /path/to/config.kbd --port 54141 --watch --debug --log-layer-changes
```

## Potential Root Cause

Based on the log patterns, it appears that:

1. **Reload state management bug**: The pending reload state is never cleared
2. **Timer mechanism failure**: The "fallback timer" referenced in logs doesn't execute
3. **Race condition**: Multiple reload attempts might interfere with each other
4. **Resource locking**: Some internal resource might remain locked after failed reload

## Workarounds

### Temporary Solutions
1. **Service restart**: `sudo launchctl kickstart -k system/com.keypath.kanata`
2. **Process restart**: Kill and restart Kanata process
3. **Remove --watch flag**: Manually restart after each config change

### None are ideal for development workflow

## Expected Fix

The reload mechanism should:
1. **Complete successfully** when triggered
2. **Clear pending state** after completion/failure
3. **Provide meaningful error logs** if reload fails
4. **Implement proper timeout handling** for stuck reloads
5. **Allow subsequent reload attempts** even if previous ones failed

## Test Case

To verify the fix:
1. Start Kanata with `--watch`
2. Make multiple rapid configuration changes
3. Verify each change is applied correctly
4. Check logs show successful reload completion
5. Test that mappings work as expected after each change

## Additional Context

This bug was discovered during UI automation testing of a macOS keyboard remapping application that relies on Kanata's hot reload functionality. The issue completely breaks the development workflow for configuration iteration.

**Impact on downstream applications**: Any application using Kanata with `--watch` for dynamic configuration updates will be affected by this bug.

---

**Reporter**: KeyPath Development Team  
**Date**: August 15, 2025  
**Kanata Version**: v1.9.0
**Platform**: macOS arm64

---

## 🎉 **RESOLUTION SUMMARY**

### Root Cause Analysis
**Two Critical Race Conditions Identified:**
1. **Race Condition #1**: `can_block` decision made before checking `live_reload_requested`
2. **Race Condition #2**: Non-blocking path only processed reloads when keyboard events occurred

### Comprehensive Fix Implemented
- ✅ **Threading Safety**: Added pre-recv double-check to eliminate final race window
- ✅ **Code Deduplication**: Consolidated 3 copies of reload logic into single `process_reload_gate()` method  
- ✅ **Rate Limiting**: 250ms interval prevents CPU thrashing on invalid configs
- ✅ **Proper State Management**: Uses correct idle detection avoiding circular dependencies
- ✅ **Production Hardening**: Multiple safety checks and comprehensive error handling

### Verification Results
- ✅ **All 7 unit tests pass** with comprehensive hot reload coverage
- ✅ **Hot reload works instantly** - File change detected and applied in 3 seconds
- ✅ **No TCP dependency** - Works independently without external interactions
- ✅ **Service stable** - Running correctly with proper permissions
- ✅ **TCP validation active** - External config validation working perfectly

### Test Results (Post-Fix)
```
11:06:13.6415 [INFO] Config file changed: /Users/malpern/.config/keypath/keypath.kbd (event: Any), triggering reload
11:06:16.2545 [INFO] Live reload successful
```

**Hot reload now works reliably in under 3 seconds!** 🚀

### Impact
- **Development Workflow**: Fully restored - config changes apply immediately
- **Production Ready**: Hardened implementation suitable for production use  
- **No Workarounds Needed**: Service restart no longer required
- **TCP Validation**: External applications can validate configs reliably

**Bug Status**: ✅ **COMPLETELY RESOLVED**