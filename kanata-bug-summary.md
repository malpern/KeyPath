# Hot Reload Stuck in Pending State (v1.9.0, macOS)

## Issue
Hot reload with `--watch` gets stuck and never applies configuration changes.

## Environment  
- Kanata v1.9.0
- macOS arm64 (Apple Silicon)
- Launched via LaunchDaemon

## Symptoms
```bash
# Every config change shows:
[INFO] Config file changed: config.kbd (event: Any), triggering reload
[DEBUG] reload already pending; not resetting fallback timer

# But reload never completes and new mappings don't work
```

## Reproduction
1. Start: `kanata --cfg config.kbd --watch --debug`
2. Modify config file (add/remove mappings)
3. Check logs: Shows "reload already pending" 
4. Test mappings: Old config still active

## Expected vs Actual
- **Expected**: Config reloads and new mappings work
- **Actual**: Reload gets stuck, requires manual restart

## Impact
- Hot reload completely broken
- Must manually restart service for every config change
- Significantly impacts development workflow

## Workaround
```bash
sudo launchctl kickstart -k system/com.keypath.kanata
```

## Additional Info
- Config syntax is valid (`kanata --cfg config.kbd --check` passes)
- File watcher detects changes correctly
- Issue persists across multiple reload attempts
- "Fallback timer" mechanism appears to be broken

---
*Discovered during automated testing of KeyPath (macOS keyboard remapping app)*