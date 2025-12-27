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
let status = PermissionOracle.shared.checkInputMonitoring()

// ❌ WRONG - bypassing Oracle
let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
```

## Related
- [ADR-006: Apple API Priority](adr-006-apple-api-priority.md)
