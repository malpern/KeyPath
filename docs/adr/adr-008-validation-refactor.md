# ADR-008: Stateless Validation via SystemValidator

**Status:** Accepted
**Date:** 2024

## Context

System validation was reactive and scattered, causing "validation spam" and inconsistent state.

## Decision

Validation is now **pull-based** via `InstallerEngine.inspectSystem()`:
- `inspectSystem()` returns a `SystemContext` snapshot (pure value struct)
- `SystemValidator` is the internal engine used by `inspectSystem()`
- No reactive spam: We explicitly request context when needed

## Implementation

```swift
let engine = InstallerEngine()
let context = await engine.inspectSystem() // Returns pure value struct
if context.permissions.inputMonitoring != .granted { ... }
```

## When to Request Context
- App launch
- Wizard open/close
- User clicks "Refresh"
- After install/repair operations

## Related
- [ADR-015: InstallerEngine Façade](adr-015-installer-engine.md)
