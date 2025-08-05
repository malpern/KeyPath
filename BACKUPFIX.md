# BACKUPFIX.md - KeyPath Issue Documentation

## Kanata Configuration Reload Issue

**Date:** August 2, 2025  
**Status:** RESOLVED (workaround identified)  
**Severity:** High - Affects core functionality

### Problem Description

Kanata's `--watch` flag is not reliably detecting configuration file changes, causing new keyboard mappings to not take effect until manual service restart.

### Symptoms

- KeyPath saves configuration changes correctly to `~/Library/Application Support/KeyPath/keypath.kbd`
- Kanata runs with `--watch --debug --log-layer-changes` flags
- New mappings don't work immediately after being added via KeyPath UI
- Manual Kanata service restart always fixes the issue

### Root Cause Analysis

**Confirmed through testing:**
1. **Test 1 (1→2 mapping)**: 
   - Added mapping via KeyPath ❌ Not working
   - Manual restart → ✅ Working immediately
2. **Test 2 (3→4 mapping)**: 
   - Added mapping via KeyPath ❌ Not working  
   - Manual restart → ✅ Working immediately

**Technical Details:**
- Kanata process runs with correct flags: `--cfg "path" --watch --debug --log-layer-changes`
- Config file validation passes: `kanata --cfg "path" --check` returns "config file is valid"
- File system change detection appears to be failing
- VirtualHID connection health is perfect (no errors in logs)
- All permissions and services are correctly configured

### Workaround Solution

**Manual Service Restart Command:**
```bash
osascript -e 'do shell script "kill -TERM [PID] && sleep 2 && /usr/local/bin/kanata --cfg \"/Users/[user]/Library/Application Support/KeyPath/keypath.kbd\" --watch --debug --log-layer-changes > /var/log/kanata.log 2>&1 &" with administrator privileges with prompt "KeyPath needs to restart Kanata to reload configuration."'
```

**Steps to restart service:**
1. Get current Kanata PID: `ps aux | grep kanata | grep -v grep`
2. Kill process and restart with admin privileges
3. Verify new process is running and config loads correctly

### Recommended Long-term Fix

**For KeyPath Application:**
1. **Remove dependency on `--watch` flag** - it's unreliable
2. **Implement automatic service restart** after every configuration save
3. **Add "Reload Service" button** in UI for manual restarts
4. **Show loading state** during service restart (2-3 seconds)
5. **Verify mappings work** after restart before showing success

**Implementation Options:**
- Add `restartKanataService()` method to `KanataManager`
- Call automatically in `saveConfiguration()` 
- Show toast notification: "Restarting service to apply changes..."

### System Information

**Environment:**
- macOS: Darwin 25.0.0
- Kanata: v1.9.0
- KeyPath: Latest (August 2025)
- Installation: via Homebrew (`/usr/local/bin/kanata`)

**Services Status:**
- VirtualHID Manager: ✅ Installed & Activated
- VirtualHID Daemon: ✅ Running (PID varies)
- LaunchDaemon Services: ✅ All installed
- Permissions: ✅ All granted (Input Monitoring, Accessibility)
- Conflicts: ✅ None detected

### Notes

- This issue doesn't affect initial setup or existing mappings
- Only impacts new configuration changes
- System diagnostics show "everything working" because service is running with old config
- File watching issues could be related to:
  - File system permissions
  - Rapid file modification timing
  - macOS security restrictions on file system events
  - Kanata's file watching implementation on macOS

### Testing Verification

Both mappings confirmed working after service restart:
- `caps` → `esc` ✅
- `1` → `2` ✅  
- `3` → `4` ✅

**Conclusion:** System is fully functional but requires manual intervention for configuration updates. Automatic restart implementation will resolve user experience issues.