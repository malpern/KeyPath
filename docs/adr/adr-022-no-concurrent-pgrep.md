# ADR-022: No Concurrent pgrep Calls in TaskGroups

**Status:** Accepted
**Date:** November 2024

## Context

Concurrent calls to functions that spawn pgrep subprocesses with retry logic can hang indefinitely.

## The Bug

`SystemValidator.performValidationBody()` runs 5 checks in a `withTaskGroup`:

```swift
withTaskGroup { group in
    group.addTask { await checkComponents() }  // calls detectConnectionHealth()
    group.addTask { await checkHealth() }      // also calls detectConnectionHealth()
    // ...
}
```

Both tasks called `detectConnectionHealth()` → `detectRunning()` → `evaluateDaemonProcess()` which spawns pgrep via `Task.detached`.

When daemon isn't running:
1. Both tasks entered 500ms retry sleeps
2. Concurrent pgrep subprocesses caused contention
3. One task never completed
4. TaskGroup's `for await result in group` loop hung forever

## Root Cause

`Process.waitUntilExit()` inside `Task.detached` with concurrent calls creates contention that can cause hangs.

## Prevention Rules

1. **Never call the same subprocess-spawning function from multiple TaskGroup tasks**
2. **Use launchctl-based checks** (`ServiceHealthChecker`) for concurrent health checking
3. **Reserve pgrep** for single-caller scenarios: diagnostics, orphan detection, post-kill verification
4. **Add ⚠️ CONCURRENCY WARNING comments** to functions with retry/sleep logic

## Code Pattern

```swift
// ❌ BAD - Both tasks call detectConnectionHealth() which has retries
withTaskGroup { group in
    group.addTask { await checkComponents() }  // calls detectConnectionHealth()
    group.addTask { await checkHealth() }      // also calls detectConnectionHealth()
}

// ✅ GOOD - Only one task uses pgrep-based check
withTaskGroup { group in
    group.addTask { /* use ServiceHealthChecker.getServiceStatus() */ }
    group.addTask { await checkHealth() }  // only caller of detectConnectionHealth()
}
```

## Related
- [ADR-020: Process Detection Strategy](adr-020-process-detection.md)
