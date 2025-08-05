# WATCHBUG.md - Kanata --watch Flag Issue

**Reporter:** KeyPath Project  
**Date:** August 2, 2025  
**Kanata Version:** v1.9.0  
**Platform:** macOS (Darwin 25.0.0)  
**Related PR:** https://github.com/jtroo/kanata/pull/1713

## Issue Summary

The `--watch` flag in kanata is not detecting configuration file changes on macOS, causing keyboard mappings to not update until manual service restart. This affects the real-time configuration update experience in GUI applications like KeyPath.

## Environment Details

**System:**
- macOS: Darwin 25.0.0 (macOS 15.x)
- Architecture: ARM64 (Apple Silicon)
- Kanata: v1.9.0 (installed via Homebrew)
- Installation Path: `/usr/local/bin/kanata`

**Kanata Command Line:**
```bash
/usr/local/bin/kanata --cfg "/Users/[user]/Library/Application Support/KeyPath/keypath.kbd" --watch --debug --log-layer-changes
```

**Config File Location:**
```
/Users/[user]/Library/Application Support/KeyPath/keypath.kbd
```

**Permissions:**
- Config file: `rw-r--r--` (644)
- Directory: `rwxr-xr-x` (755)
- Parent directories: Properly accessible
- Process runs as root via sudo

## Problem Description

### Expected Behavior
When config file is modified, kanata should automatically reload the configuration and apply new key mappings without requiring service restart.

### Actual Behavior
- Kanata starts successfully with `--watch` flag
- Logs show: "Watching config file for changes: [path]"
- Config file modifications are NOT detected
- New mappings don't take effect until manual process restart
- No reload events appear in debug logs

### Verification of Issue

**Config file validation passes:**
```bash
$ kanata --cfg "/path/to/keypath.kbd" --check
INFO: kanata v1.9.0 starting
INFO: validating config only and exiting
INFO: process unmapped keys: false
INFO: config file is valid
```

**Watch flag appears in startup logs:**
```
INFO: Watching config file for changes: /Users/[user]/Library/Application Support/KeyPath/keypath.kbd
```

## Reproduction Steps

### Step 1: Initial Setup
1. Create valid kanata config file:
```lisp
;; keypath.kbd
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

2. Start kanata with watch flag:
```bash
sudo /usr/local/bin/kanata --cfg "/path/to/keypath.kbd" --watch --debug --log-layer-changes > /var/log/kanata.log 2>&1 &
```

3. Verify initial mapping works (caps → esc)

### Step 2: Modify Configuration
1. Update config file to add new mapping:
```lisp
;; keypath.kbd
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

2. Save file (ensuring proper write/sync)
3. Wait 5-10 seconds for potential reload
4. Test new mapping (1 → 2)

### Step 3: Verify Issue
- **Expected:** New mapping (1 → 2) works immediately
- **Actual:** New mapping doesn't work, old mapping (caps → esc) continues working
- **Debug logs:** No reload events visible in logs

### Step 4: Confirm Fix with Restart
1. Kill kanata process: `sudo kill -TERM [PID]`
2. Restart with same command
3. Test mapping: 1 → 2 now works correctly

## Detailed Testing Results

### Test Case 1: 1 → 2 Mapping
- **Config change:** Added `1` to defsrc, `2` to deflayer
- **Watch result:** ❌ Not detected, mapping doesn't work
- **Manual restart:** ✅ Works immediately after restart

### Test Case 2: 3 → 4 Mapping  
- **Config change:** Added `3` to defsrc, `4` to deflayer
- **Watch result:** ❌ Not detected, mapping doesn't work
- **Manual restart:** ✅ Works immediately after restart

### Consistency
- Issue reproduced 100% of the time across multiple tests
- Manual restart always resolves the issue immediately
- No file corruption or validation errors observed

## Log Analysis

**Startup logs show watch initialization:**
```
22:59:08.4580 INFO: kanata v1.9.0 starting
22:59:08.4584 INFO: process unmapped keys: false
22:59:08.4586 INFO: config file is valid
22:59:10.4666 INFO: Watching config file for changes: /Users/[user]/Library/Application Support/KeyPath/keypath.kbd
22:59:10.4667 INFO: entering the event loop
```

**No reload events in logs after config changes:**
- Expected: Reload messages when file is modified
- Actual: No additional watch-related log entries
- Key events continue to be processed normally with old config

## File System Details

**File operations during config update:**
```bash
# Before change
$ ls -la keypath.kbd
-rw-r--r--  1 user  staff  145 Aug  2 22:45 keypath.kbd

# File modification (typical editor save)
$ echo "new content" > keypath.kbd

# After change  
$ ls -la keypath.kbd
-rw-r--r--  1 user  staff  185 Aug  2 22:50 keypath.kbd
```

**File system events (fs_usage output):**
- File modification events are occurring at OS level
- Standard editor save operations (create temp → rename)
- No obvious permission or access issues

## Potential Root Causes

### 1. File Watching Implementation
- Issue with file system event detection on macOS
- Problems with temp file → rename operations (common editor pattern)
- Path canonicalization issues

### 2. macOS-Specific Issues
- Security restrictions on file system monitoring
- Sandboxing or permission limitations
- Different behavior between Intel/ARM Macs

### 3. Race Conditions
- File watching setup timing
- Event processing during file modification
- Buffer/sync issues with file I/O

### 4. Path Resolution
- Absolute vs relative path handling
- Symlink resolution in watched paths
- Case sensitivity or encoding issues

## Suggested Investigation Areas

### Code Review Focus
1. **File watching initialization** in the --watch implementation
2. **Event loop integration** for file system events
3. **Error handling** for failed watch operations
4. **macOS-specific file system APIs** being used

### Debug Enhancement Suggestions
1. **Add verbose file watching logs** showing:
   - Watch setup success/failure
   - File system events received
   - Reload attempt triggers
   - Any errors during reload

2. **Test with different file modification patterns:**
   - Direct write vs temp-file-rename
   - Different editors (vim, nano, GUI editors)
   - Programmatic modifications

### Minimal Test Case
```bash
# Terminal 1: Start kanata with verbose file watching
sudo kanata --cfg test.kbd --watch --debug

# Terminal 2: Modify file and observe
echo "(deflayer base a)" >> test.kbd
# Check if reload occurs in Terminal 1 logs
```

## Workaround for Users

Until fixed, GUI applications should implement automatic service restart after config changes:
```bash
sudo kill -TERM [kanata_pid]
sudo kanata --cfg [config_path] --watch --debug &
```

## Additional Context

This issue significantly impacts user experience in GUI applications that expect real-time config updates. The --watch feature is crucial for applications like KeyPath that provide visual config editing interfaces.

The bug appears to be platform-specific to macOS, as the feature design suggests it should work. Investigation of the file watching implementation in the referenced PR may reveal macOS-specific issues or missing event handling.