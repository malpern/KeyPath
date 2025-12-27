# ADR-006: Apple API Priority in Permission Checks

**Status:** Accepted
**Date:** 2024

## Context

KeyPath can check permissions via:
1. Apple APIs (`IOHIDCheckAccess` from GUI context)
2. TCC database queries
3. Functional verification (try to use the API)

These sometimes give conflicting results.

## Decision

**Apple APIs ALWAYS take precedence over TCC database.**

### Priority Order

1. **APPLE APIs** (IOHIDCheckAccess from GUI context) → **AUTHORITATIVE**
   - `.granted` / `.denied` → TRUST THIS RESULT
   - `.unknown` → Proceed to TCC fallback

2. **TCC DATABASE** → **NECESSARY FALLBACK** for `.unknown` cases
   - Required for chicken-and-egg wizard scenarios

3. **FUNCTIONAL VERIFICATION** → Disabled in TCP-only mode

## Consequences

### Rules
- Trust Apple API results unconditionally
- Only use TCC database when Apple API returns `.unknown`
- Log source clearly: "gui-check" vs "tcc-fallback"

### Why TCC Can Be Wrong
- TCC database is a cache that can be stale
- Apple API reflects actual system state
- Root processes get unreliable results from TCC

## Related
- [ADR-001: Oracle Pattern](adr-001-oracle-pattern.md)
- [ADR-016: TCC Database Reading](adr-016-tcc-database-reading.md)
