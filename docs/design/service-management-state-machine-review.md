# Design Review: Service Management State Machine

## Overall Assessment

**Rating: 7/10** - Good foundation, but needs refinement in several areas.

## Strengths ✅

1. **Single Source of Truth**: Centralizing state determination is the right approach
2. **Explicit States**: Clear enum makes states visible and debuggable
3. **Priority Order**: Legacy plist first is correct (most reliable indicator)
4. **Addresses Core Problem**: Prevents accidental fallback to legacy

## Critical Issues ⚠️

### 1. **Inconsistency Between Doc and Implementation**

**Problem**: The doc mentions `.migrated` state but the actual implementation doesn't have it. The implementation has:
- `.legacyActive`
- `.smappserviceActive` 
- `.smappservicePending`
- `.uninstalled`
- `.conflicted`
- `.unknown`

**Impact**: Confusion, potential bugs if someone implements based on doc

**Recommendation**: Remove `.migrated` from doc OR add it to implementation (but it's probably redundant - `.smappserviceActive` after migration is the same thing)

### 2. **Fundamental Design Mismatch**

**Problem**: The doc's example `createKanataLaunchDaemon()` checks **state first**, then feature flag. But the actual code checks **feature flag first**, then routes.

**Current Reality**:
```swift
// Actual code checks feature flag FIRST
if featureFlagValue {
    return await createKanataLaunchDaemonViaSMAppService()
} else {
    return createKanataLaunchDaemonViaLaunchctl()
}
```

**Doc's Proposal**:
```swift
// Doc suggests checking state FIRST
let state = determineServiceManagementState()
switch state {
    case .legacyActive:
        if FeatureFlags.useSMAppServiceForDaemon {
            return false  // Must migrate first
        }
        return createKanataLaunchDaemonViaLaunchctl()
    // ...
}
```

**Impact**: The doc proposes a different architecture than what exists. This is a **breaking change** that needs to be intentional.

**Recommendation**: 
- **Option A**: Update doc to match current architecture (state-aware guards, but feature flag still primary)
- **Option B**: Propose the state-first approach as a refactor (more work, but cleaner)

### 3. **Race Conditions Not Fully Addressed**

**Problem**: The doc claims "Immutable State Checks" but state can change between:
1. `determineServiceManagementState()` call
2. Decision based on state
3. Action taken

**Example Race**:
```swift
let state = determineServiceManagementState()  // Returns .uninstalled
// User migrates in another thread/process
// Legacy plist gets removed, SMAppService gets registered
// But we still have .uninstalled in our variable
if state == .uninstalled {
    // Now we install via wrong method!
}
```

**Impact**: Still possible to make wrong decisions

**Recommendation**: 
- Acknowledge this limitation
- Add defensive checks at action points (re-check state right before acting)
- OR: Make state determination part of the action (check-and-act atomically)

### 4. **Missing Error Handling Strategy**

**Problem**: The doc doesn't address what happens when:
- State is `.uninstalled`, feature flag ON, but SMAppService registration fails
- State is `.conflicted` - how do we resolve?
- State is `.unknown` - what does "investigate" mean?

**Impact**: System can get stuck in bad states

**Recommendation**: Add error handling section:
- `.conflicted`: Auto-resolve by removing legacy plist (if feature flag ON)
- `.unknown`: Check process owner, check launchctl, make best guess
- Registration failures: Don't fall back to launchctl if feature flag ON (current behavior is correct)

### 5. **Decision Matrix Incomplete**

**Problem**: The decision matrix doesn't cover all scenarios:
- What if `.legacyActive` + feature flag ON? (Should trigger migration, not install)
- What if `.smappservicePending` + user wants to retry registration?
- What if `.conflicted` + feature flag OFF? (Should use legacy)

**Impact**: Edge cases not handled

**Recommendation**: Expand decision matrix or add "State + Feature Flag" combinations

### 6. **Migration Path Unclear**

**Problem**: The doc says "Update one installation function at a time" but doesn't specify:
- Which functions first?
- How to test incrementally?
- What happens during transition period (some functions use state, others don't)?

**Impact**: Risky migration, potential for bugs during transition

**Recommendation**: 
- Specify order: `isServiceLoaded()` → `createKanataLaunchDaemon()` → `restartUnhealthyServices()` → others
- Add compatibility layer during transition
- Specify testing strategy for each phase

## Missing Considerations 🤔

### 1. **Performance**

**Question**: How expensive is `determineServiceManagementState()`?
- File system check (fast)
- SMAppService status check (fast)
- Process check via `pgrep` (slower, spawns process)

**Impact**: If called frequently, could be slow

**Recommendation**: Add caching/memoization strategy OR document that it's fast enough

### 2. **Testing Strategy**

**Question**: How do we test all state transitions?
- Need to simulate: legacy plist creation/deletion, SMAppService registration/unregistration, process start/stop

**Impact**: Hard to verify correctness

**Recommendation**: Add testing section with mock strategies

### 3. **Backward Compatibility**

**Question**: What about existing code that uses `isUsingSMAppService`, `hasLegacyInstallation()`, etc.?

**Impact**: Need to deprecate gradually or keep both

**Recommendation**: Keep old methods as wrappers around state machine initially

### 4. **Logging Strategy**

**Question**: The doc mentions logging but doesn't specify:
- What level? (debug vs info vs error)
- How much detail?
- Performance impact?

**Impact**: Could be too verbose or not verbose enough

**Recommendation**: Specify logging levels and when to log

## Recommendations 📋

### High Priority

1. **Fix inconsistency**: Remove `.migrated` from doc OR add to implementation
2. **Clarify architecture**: State-first vs feature-flag-first - pick one and document why
3. **Add error handling**: Specify what to do for `.conflicted`, `.unknown`, registration failures
4. **Expand decision matrix**: Cover all state + feature flag combinations

### Medium Priority

5. **Address race conditions**: Add defensive re-checks or acknowledge limitation
6. **Specify migration order**: Which functions to update first, testing strategy
7. **Add performance considerations**: Caching, when to call state determination

### Low Priority

8. **Add testing strategy**: How to test state transitions
9. **Add logging spec**: What to log, when, at what level
10. **Add backward compatibility plan**: How to deprecate old methods

## Alternative Approach Consideration

**Question**: Is a full state machine necessary, or would a simpler "guard function" suffice?

**Simpler Alternative**:
```swift
nonisolated static func shouldUseSMAppService() -> Bool {
    // If legacy plist exists, never use SMAppService (must migrate first)
    if FileManager.default.fileExists(atPath: legacyPlistPath) {
        return false
    }
    // Otherwise, use feature flag
    return FeatureFlags.useSMAppServiceForDaemon
}
```

**Pros**: Simpler, less code, easier to understand
**Cons**: Less explicit states, harder to debug ambiguous cases

**Recommendation**: The state machine is better for debugging and explicit handling, but consider if simpler would suffice.

## Conclusion

The design is **sound in principle** but needs:
1. Consistency fixes (doc vs implementation)
2. Architecture decision (state-first vs feature-flag-first)
3. Error handling strategy
4. More complete decision matrix
5. Clearer migration path

**Recommendation**: Fix the critical issues before full implementation, then proceed incrementally.

