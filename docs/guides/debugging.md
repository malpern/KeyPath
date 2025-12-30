---
layout: default
title: Debugging Guide
description: Advanced troubleshooting and debugging for KeyPath
---

# Debugging Guide

This guide covers advanced troubleshooting and debugging techniques for KeyPath.

## Quick Reference

### Emergency Recovery

If your keyboard becomes unresponsive:

1. **Emergency Stop**: Press `Ctrl + Space + Esc` simultaneously
2. **Kill Kanata processes**: `sudo pkill -f kanata`
3. **Restart VirtualHID daemon**: Restart Karabiner daemon if needed

### Key Diagnostic Commands

```bash
# Check if Kanata is running
ps aux | grep kanata | grep -v grep

# Monitor real-time logs
tail -f /var/log/com.keypath.kanata.stdout.log

# Check service status
launchctl list | grep keypath

# View system logs
log show --predicate 'process == "kanata"' --last 5m
```

## Common Issues

### Keys Not Remapping

**Symptoms:**
- KeyPath shows green checkmarks
- Permissions are granted
- But keys don't remap

**Diagnosis:**
1. Check Kanata is running: `ps aux | grep kanata`
2. Verify config is valid: Check logs for syntax errors
3. Test with minimal config: Create a simple remapping to isolate the issue

**Solutions:**
- Run the setup wizard's "Fix Issues" button
- Restart KeyPath
- Check for conflicts with other remappers

### Service Keeps Crashing

**Symptoms:**
- Service starts then immediately stops
- Logs show crash messages

**Diagnosis:**
1. Check logs: `tail -f /var/log/com.keypath.kanata.stdout.log`
2. Verify config syntax is valid
3. Check for permission issues

**Solutions:**
- Validate config file syntax
- Check permissions are granted
- Use the wizard's "Fix Issues" button
- Try with a minimal config

### Permission Issues

**Symptoms:**
- Wizard shows permission errors
- Keys don't work even after granting permissions

**Diagnosis:**
1. Check System Settings → Privacy & Security
2. Verify both Input Monitoring and Accessibility are granted
3. Check TCC database: `sudo sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT * FROM access WHERE client LIKE '%keypath%';"`

**Solutions:**
- Manually grant permissions in System Settings
- Restart KeyPath after granting permissions
- Run the setup wizard again

### Config Not Loading

**Symptoms:**
- Changes to config file don't apply
- Hot reload not working

**Diagnosis:**
1. Check TCP is enabled in config
2. Verify config file path is correct
3. Check for syntax errors in logs

**Solutions:**
- Ensure TCP is enabled: `(defcfg ... tcp-server-port 37001)`
- Verify config path: `~/.config/keypath/keypath.kbd`
- Check config syntax is valid

## Log Files

### KeyPath Logs

**Location:** `~/Library/Logs/KeyPath/`

- `keypath-debug.log` - Main application logs
- `keypath-error.log` - Error logs

### Kanata Logs

**Location:** `/var/log/`

- `com.keypath.kanata.stdout.log` - Standard output
- `com.keypath.kanata.stderr.log` - Standard error

### Viewing Logs

```bash
# Real-time monitoring
tail -f /var/log/com.keypath.kanata.stdout.log

# Last 100 lines
tail -n 100 /var/log/com.keypath.kanata.stdout.log

# Search for errors
grep -i error /var/log/com.keypath.kanata.stdout.log
```

## Debug Mode

### Enable Debug Logging

KeyPath logs debug information by default. To increase verbosity:

1. Open KeyPath
2. Go to Preferences → Advanced
3. Enable "Debug Logging"

### Manual Kanata Testing

Test Kanata directly with your config:

```bash
# Test config syntax
kanata --cfg ~/.config/keypath/keypath.kbd --check

# Run with debug output
kanata --cfg ~/.config/keypath/keypath.kbd --debug

# Test with timeout (safely exit after 5 seconds)
timeout 5s kanata --cfg ~/.config/keypath/keypath.kbd --debug
```

## Architecture Debugging

### Service Status

Check LaunchDaemon service status:

```bash
# List all KeyPath services
launchctl list | grep keypath

# Check specific service
launchctl list com.keypath.kanata

# View service logs
log show --predicate 'subsystem == "com.keypath.kanata"' --last 10m
```

### Process Detection

Check for conflicting processes:

```bash
# Find all Kanata processes
pgrep -fl kanata

# Find Karabiner processes
pgrep -fl karabiner

# Check for conflicts
ps aux | grep -E "(kanata|karabiner)" | grep -v grep
```

## Advanced Troubleshooting

### TCP Connection Issues

If TCP isn't working:

1. **Check port is available:**
   ```bash
   lsof -i :37001
   ```

2. **Verify TCP is enabled in config:**
   ```lisp
   (defcfg
     tcp-server-port 37001
   )
   ```

3. **Test TCP connection:**
   ```bash
   nc localhost 37001
   ```

### Config Validation

Validate your config file:

```bash
# Using Kanata directly
kanata --cfg ~/.config/keypath/keypath.kbd --check

# Check for common issues
grep -n "(defcfg\|defsrc\|deflayer)" ~/.config/keypath/keypath.kbd
```

### Permission Debugging

Check TCC database entries:

```bash
# Requires Full Disk Access
sudo sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, allowed FROM access WHERE client LIKE '%keypath%' OR client LIKE '%kanata%';"
```

## Getting Help

If you're still stuck:

1. **Collect diagnostic information:**
   - Log files
   - Config file (remove sensitive info)
   - System information

2. **Create a GitHub issue:**
   - Include error messages
   - Describe what you tried
   - Attach relevant logs

3. **Check existing issues:**
   - Search GitHub issues for similar problems
   - Check closed issues for solutions

## Best Practices

1. **Always backup your config** before making changes
2. **Test with minimal configs** when debugging
3. **Check logs first** before asking for help
4. **Use the setup wizard** for automated fixes
5. **Keep KeyPath updated** to latest version
