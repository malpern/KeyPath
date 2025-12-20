# TCP Broken Pipe Diagnostic Instrumentation

## Overview

This document describes the diagnostic instrumentation added to investigate broken pipe errors when Kanata tries to write ReloadResult responses.

## Hypothesis

**Problem:** Two separate task groups in `reloadConfig()` cause connection state issues, leading to broken pipe when Kanata writes the second line.

**Expected Evidence:**
- Connection being reused between first and second read
- Connection state changes between task groups
- Timing issues where second read starts too late

## Instrumentation Added

### 1. Connection Lifecycle Logging

**Location:** `KanataTCPClient.ensureConnectionCore()`

**What it logs:**
- `🔌 Reusing existing connection (state=...)` - Connection reuse detected
- `🔌 Existing connection not ready (state=...)` - Stale connection found
- `🔌 No existing connection` - Creating first connection
- `🔌 Creating new connection to host:port` - New connection being established
- `🔌 Connection state changed: ...` - All NWConnection state transitions
- `🔌 Connection established successfully` - Connection ready

### 2. Connection Close Tracking

**Location:** `KanataTCPClient.closeConnection()`

**What it logs:**
- `🔌 closeConnection() called (current state=...)` - When/why close is called
- Stack trace (first 5 frames) - What triggered the close

### 3. Reload Timing Markers

**Location:** `KanataTCPClient.reloadConfig()`

**What it logs:**
- `⏱️ t=0ms: Starting reload` - Reload begins
- `⏱️ t=Xms: Sending reload request` - Request sent
- `⏱️ t=Xms: First line received, connection state=...` - First line read complete
- `⏱️ t=Xms: About to get connection for second line read` - Before ensureConnectionCore()
- `⏱️ t=Xms: Starting second line read, connection state=...` - Second read begins
- `⏱️ t=Xms: Second line received, connection state=...` - Second line read complete
- `⏱️ t=Xms: Reload completed successfully` - Full success
- `❌ t=Xms: Reload error, connection state=...` - Error path with state

### 4. Connection State Validation

**Location:** `KanataTCPClient.readUntilNewline()`

**What it does:**
- Validates connection is `.ready` before attempting read
- Throws error if connection not ready
- Logs invalid connection state

## How to Use

### 1. Normal Usage - Collect Data

Just use KeyPath normally. Make config changes and save them (triggers reload).

### 2. Analyze Logs with Correlation Script

```bash
# Show recent activity
./Scripts/correlate-logs.sh

# Analyze specific broken pipe occurrence
./Scripts/correlate-logs.sh "22:05:25"
```

### 3. Look for These Patterns

#### Pattern A: Connection Reuse Between Reads
```
⏱️ t=5ms: First line received, connection state=ready
🔌 Reusing existing connection (state=ready)
⏱️ t=10ms: Starting second line read, connection state=ready
```
**Question:** Is the connection still valid? Did state change?

#### Pattern B: Connection Closed Between Reads
```
⏱️ t=5ms: First line received, connection state=ready
🔌 closeConnection() called (current state=ready)
  stack trace...
⏱️ t=10ms: About to get connection for second line read
🔌 Creating new connection
```
**Question:** Why was connection closed? Check stack trace.

#### Pattern C: Connection State Transition
```
⏱️ t=5ms: First line received, connection state=ready
🔌 Connection state changed: waiting
⏱️ t=10ms: Starting second line read, connection state=waiting
❌ readUntilNewline called on non-ready connection
```
**Question:** What caused state to change from ready to waiting?

#### Pattern D: Timing Issue
```
⏱️ t=5ms: First line received
⏱️ t=15ms: About to get connection (10ms gap!)
⏱️ t=520ms: Second line received

Kanata log shows: t=518ms: Sending ReloadResult response
```
**Question:** Did Kanata write while we weren't reading?

### 4. Correlate with Kanata Logs

Check Kanata's perspective:
```bash
grep "Reload:" /var/log/com.keypath.kanata.stdout.log | tail -20
```

Look for:
- `Reload: Starting wait loop (timeout=5000ms)`
- `Reload: wait loop detected ready=true after Xms`
- `Reload: Sending ReloadResult response`
- `ReloadResult sent successfully` (success) vs `Error writing ReloadResult response: Broken pipe` (failure)

### 5. Statistics

The correlation script shows:
- Total broken pipe errors (historical)
- Successful ReloadResult sends
- Connection state changes
- Connection reuses vs new connections

## What We're Looking For

### To Confirm Hypothesis

1. **Connection reuse:** Do we see "Reusing existing connection" before second read?
2. **State consistency:** Is connection state `.ready` for both reads?
3. **Timing gaps:** How long between first line received and second line started?
4. **Unexpected closes:** Are there `closeConnection()` calls we don't expect?

### Alternative Explanations

1. **NWConnection bug:** State reports `.ready` but connection is broken
2. **Timeout issue:** KeyPath timeout firing before Kanata finishes
3. **Task cancellation:** `group.cancelAll()` affecting connection state
4. **Concurrent access:** Multiple threads accessing same connection

## Next Steps Based on Findings

### If connection reuse is the problem:
→ Don't reuse connection for multi-line protocol, create fresh connection for each reload

### If timing gap is the problem:
→ Keep connection open longer, increase buffer time

### If task group cancellation is the problem:
→ Use single task group for both reads (proposed fix)

### If state transitions are the problem:
→ Add state monitoring, handle transitions explicitly

## Running Stress Test

To try reproducing the issue:

```swift
// Add to KeyPath UI temporarily
Task {
  for i in 1...50 {
    print("🧪 Test reload #\(i)")
    // Make a config change and save
    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms between
  }
}
```

Or from command line:
```bash
for i in {1..50}; do
  # Trigger reload via config change
  touch ~/Library/Application\ Support/KeyPath/keypath.kbd
  sleep 0.2
done
```

## Log Locations

- **KeyPath:** `~/Library/Logs/KeyPath/keypath-debug.log`
- **Kanata stdout:** `/var/log/com.keypath.kanata.stdout.log`
- **Kanata stderr:** `/var/log/com.keypath.kanata.stderr.log`

## Config Validation Debugging

If config validation fails with a parse error and you need the exact generated config:

- Set `KEYPATH_KEEP_FAILED_CONFIG=1` and retry the save.
- The temp validation config path will be logged in `keypath-debug.log`.

## Clean Logs (Optional)

To start fresh:
```bash
rm ~/Library/Logs/KeyPath/keypath-debug.log
sudo rm /var/log/com.keypath.kanata.*.log
sudo launchctl kickstart -k system/com.keypath.kanata
```
