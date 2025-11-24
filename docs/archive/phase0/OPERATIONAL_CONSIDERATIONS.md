# Operational Considerations

> **Modern note (Nov 24, 2025):** Operational tooling is now expected to call `RuntimeCoordinator`/`ProcessCoordinator` so that InstallerEngine stays behind the façade. The historical guidance below references the old direct-call model.

**Status:** ✅ PLANNED - Rollout strategy defined

**Date:** 2025-11-17

---

## Feature Flagging

### Strategy: Simple Environment Variable

**Implementation:**
```swift
// In InstallerEngine or callers:
if ProcessInfo.processInfo.environment["KEYPATH_USE_INSTALLER_ENGINE"] == "1" {
    // Use new façade
    let engine = InstallerEngine()
    let report = await engine.run(intent: .repair, using: broker)
} else {
    // Use existing code
    // ... existing logic ...
}
```

**Usage:**
```bash
# Test with façade
KEYPATH_USE_INSTALLER_ENGINE=1 swift test

# Run app with façade
KEYPATH_USE_INSTALLER_ENGINE=1 ./Scripts/build.sh
```

**Skip:** Build flags, runtime flags, preferences (add later if needed)

---

## Logging Strategy

### Reuse Existing AppLogger

**Implementation:**
```swift
// In InstallerEngine methods:
AppLogger.shared.log("🔍 [InstallerEngine] Starting inspectSystem()")
let context = // ... detection logic ...
AppLogger.shared.log("✅ [InstallerEngine] inspectSystem() complete")
```

**Log Points:**
- Start/end of `inspectSystem()`
- Start/end of `makePlan()`
- Start/end of `execute()`
- Each recipe execution
- Requirement checks
- Errors

**Log Levels:**
- Use existing `AppLogger` levels (no custom levels)
- Log at appropriate existing levels

**Skip:** Custom logging infrastructure, complex tracing (add if needed)

---

## Migration Path

### Incremental Adoption

**Phase 1: Tests (Safest)**
- Migrate functional tests to use façade
- Verify tests still pass
- No user-facing changes

**Phase 2: CLI (Easier to Debug)**
- Migrate CLI scripts to use façade
- Test CLI commands
- Easier to debug than GUI

**Phase 3: GUI (Most Visible)**
- Migrate wizard auto-fix button
- Migrate installation wizard flows
- Most user-visible, test carefully

**Skip:** Side-by-side execution (just switch when ready)

---

## Documentation Updates

### Minimal Updates

**Required:**
- [ ] Add façade section to `ARCHITECTURE.md`
- [ ] Inline code comments for complex logic

**Optional (Add Later):**
- [ ] Migration guide for existing callers
- [ ] Extensive usage examples
- [ ] Video walkthrough

**Files to Update:**
- `docs/ARCHITECTURE.md` - Add InstallerEngine section
- Source code - Add inline comments
- `docs/facade-planning.md` - Mark Phase 0 complete

---

## Performance Considerations

### No Performance Regressions

**Monitor:**
- Detection time (should be similar to existing)
- Plan generation time (should be fast)
- Execution time (should be similar to existing)

**Optimization:**
- Only optimize if performance degrades
- Profile critical paths if needed
- YAGNI: don't optimize prematurely

---

## Error Handling

### Preserve Existing Error Behavior

**Current Behavior:**
- Errors logged via `AppLogger`
- Errors returned in `InstallerReport`
- User sees error messages in UI

**Must Preserve:**
- Same error messages (or better)
- Same error handling flow
- Same logging behavior

---

## Rollback Plan

### If Façade Causes Issues

**Rollback Steps:**
1. Remove environment variable flag
2. Code falls back to existing paths
3. Investigate issue
4. Fix and retry

**No Breaking Changes:**
- Façade is additive (new code)
- Existing code remains unchanged
- Can disable façade without breaking app

---

## Success Metrics

### How We'll Know It's Working

**Functional:**
- [ ] All existing tests pass
- [ ] CLI commands work
- [ ] GUI wizard works
- [ ] No regressions introduced

**Code Quality:**
- [ ] Façade code is readable
- [ ] Types are well-defined
- [ ] Tests provide good coverage
- [ ] Documentation is clear

**Performance:**
- [ ] No performance regressions
- [ ] Detection is fast
- [ ] Execution is reliable

---

## Notes

- Keep it simple: env var flagging, existing logging, incremental migration
- No premature optimization
- Easy rollback if issues arise
- Focus on correctness first, optimization later


