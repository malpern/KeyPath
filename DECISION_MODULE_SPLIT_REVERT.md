# ADR-010: Revert Module Split to Single Executable

**Date:** 2025-10-22  
**Status:** ✅ ACCEPTED  
**Context:** Personal project simplification

## Decision

Revert the Package.swift module split (commits 80d8ee0, ad03007) back to a single executable target.

## Context

### What We Built
Commits 80d8ee0 and ad03007 (Sept 30, 2025) split the project into two modules:
- `KeyPath` target (Core library) - excludes UI/, App.swift
- `KeyPathApp` target (Executable) - excludes Core/, Managers/, Services/

**Motivation:** Swift 6 emit-module stability and strict concurrency isolation

### What Went Wrong
1. **Incomplete implementation** - Types not marked `public`, project doesn't compile
2. **60+ minutes of busywork** - Need to mark ~50-100 types public
3. **Ongoing cognitive overhead** - "Is this in Core or UI?"
4. **No actual benefit realized** - `KeyPathLib` product unused, Swift 6 works fine in single module
5. **Blocking development** - Can't compile to add features

### Cost-Benefit Analysis

**Costs:**
- Initial: 60+ min marking types public
- Ongoing: Every new type needs public API consideration
- Mental: Cognitive load of module boundaries
- **Current: Project doesn't compile**

**Benefits:**
- ~~Reusable library~~ - Not reusing it
- ~~Strict concurrency~~ - Works in single module too
- ~~Clean boundaries~~ - Directory structure provides this
- ~~Build performance~~ - Not a bottleneck (project size ~40K LOC)

**ROI:** Negative for personal project

## Decision

**Single executable module** with directory-based organization:

```swift
.executableTarget(
    name: "KeyPath",
    path: "Sources/KeyPath",
    swiftSettings: [.swiftLanguageMode(.v6)]
)
```

Keep directory structure for organization:
```
Sources/KeyPath/
  Core/              # Business logic (internal)
  Services/          # Reusable services (internal)
  Managers/          # Coordinators (internal)
  UI/               # Views (internal)
  App.swift         # Entry point
```

## Consequences

### Positive
- ✅ **Compiles immediately** - No public API work needed
- ✅ **Faster development** - No module boundary friction
- ✅ **Simpler mental model** - All code is internal by default
- ✅ **Less maintenance** - No public API to maintain

### Negative
- ❌ Can't import `KeyPathLib` separately (not currently needed)
- ❌ No enforced module boundaries (directory structure provides soft boundaries)

### Neutral
- Swift 6 concurrency works identically in single module
- Test isolation unaffected (tests still import KeyPath)

## Lessons Learned

### What to Keep (Genuinely Valuable)
1. **PermissionOracle pattern** - Solved real bugs (ADR-006)
2. **Service extraction** - Makes 4,000-line files maintainable (ADR-009)
3. **SystemValidator** - Defensive assertions caught real issues (ADR-008)
4. **MVVM for SwiftUI** - Standard pattern, not over-engineered

### What to Avoid (Complexity > Value for Personal Project)
1. **Module splits** - Solving problems we don't have
2. **Architecture for scale** - YAGNI applies
3. **Premature abstraction** - Wait for real need

### The Pragmatism Test
Before adding architectural complexity, ask:
- **"Would this exist in a 500-line MVP?"**
- **"Am I solving a problem I actually have?"**
- **"Does this help me ship faster?"**

If the answer is "no" to all three, it's probably over-engineering.

## Why Document This?

This ADR captures:
1. **What we tried** - Module split for Swift 6
2. **Why it didn't work** - Cost > benefit for solo project
3. **What we learned** - Complexity tax is real
4. **How to decide** - Use the pragmatism test

Future us can reflect: "We tried the 'proper' architecture, measured the cost, and chose simplicity."

## Implementation

1. Edit Package.swift to single `.executableTarget`
2. Remove uncommitted `KanataConfigManager.swift` (incomplete Phase 4 work)
3. Revert `.bak` files created during public API attempts
4. Build and verify

## References

- Original split: commits 80d8ee0, ad03007
- Swift 6 prep: commits a634a0c, c661f54
- BUILD_PERFORMANCE_ANALYSIS.md - Context on build issues
