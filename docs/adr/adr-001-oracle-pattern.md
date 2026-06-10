# ADR-001: Oracle Pattern for Permission Detection

**Status:** Accepted
**Date:** 2024

## Context

KeyPath needs to check various macOS permissions (Accessibility, Input Monitoring) to function correctly. Permission checking was scattered across multiple components with inconsistent logic.

## Decision

Create `PermissionOracle` as the **single source of truth** for all permission detection.

## Consequences

### Positive
- Centralized permission logic
- Consistent behavior across all components
- Easier to test and debug
- Clear ownership of permission-related code

### Negative
- All components must use the Oracle (no shortcuts)

## Implementation

```swift
// ✅ CORRECT
let snapshot = await PermissionOracle.shared.currentSnapshot()
let status = snapshot.keyPath.inputMonitoring

// ❌ WRONG - bypassing Oracle
let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
```

Permission request flows are the only exception to the "no direct permission API"
rule. `PermissionRequestService` may call prompt-triggering system APIs such as
`IOHIDRequestAccess` and `AXIsProcessTrustedWithOptions`, but those calls are
write/prompt side effects only. Any "already granted" decisions and any state
returned to callers must come from `PermissionOracle`, with a forced refresh
immediately after a prompt attempt.

## Related
- [ADR-006: Apple API Priority](adr-006-apple-api-priority.md)
