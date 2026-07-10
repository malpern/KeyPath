# ADR-026: System Validation Ordering - Components Before Service Status

**Status:** Accepted; implementation updated by installer pipeline consolidation
**Date:** December 2025

## Context

The wizard displayed all green checkmarks (system healthy) but mappings failed with "Kanata Installation Required" error. The Kanata binary was missing from `/Library/KeyPath/bin/kanata`, yet the system was declared `.active`.

## Root Cause

The former `SystemContextAdapter.adaptSystemState()` checked if
`kanataRunning == true` before verifying components existed.

If `ServiceHealthChecker.isServiceHealthy()` returned a false positive (during the 2-second warmup period after service restart, or due to any health check bug), the system would be declared `.active` without ever checking if the Kanata binary existed.

## Decision

Validation checks MUST follow this order:

```swift
// Correct priority order (enforced by the canonical snapshot projection)
1. Conflicts          // Highest priority - blocks everything
2. Components         // Must exist before anything can run
3. Permissions        // Required for services to work
4. Service status     // Only checked if components exist + permissions granted
5. Daemon health      // Final check
```

## Why This Order?

| Reason | Explanation |
|--------|-------------|
| Health checks can have false positives | Warmup windows, race conditions, bugs |
| Components are prerequisites | A service can't truly be "running" if its binary doesn't exist |
| Fail-fast on missing components | Better to show "missing binary" than "everything's working" |
| Prevents confusion | Users shouldn't see green checkmarks when critical files are missing |

## Current Implementation

`SystemContextAdapter` was deleted in PR #1092. `SystemValidator` now captures
the canonical `SystemSnapshot`; `SystemStateResult+SystemContext.swift` projects
that immutable evidence into `SystemContext`, and `InstallerDecisionPipeline`
classifies and plans from it. The ordering invariant remains: component
prerequisites outrank derived service-health evidence.

## Rules

### What NOT to Do
- ❌ Check service status before verifying components exist
- ❌ Trust health checks unconditionally - validate prerequisites first
- ❌ Reorder these checks without understanding the implications

### When Adding New Checks
- Ask: "Is this a prerequisite for something else?" → Place it earlier
- Ask: "Can this have false positives?" → Validate prerequisites first
- Ask: "What's the user impact if this check is wrong?" → Fail-fast on critical items

## Related
- [ADR-006: Apple API Priority](adr-006-apple-api-priority.md) - Same principle: trust authoritative sources over derivative checks
