# Startup Experience Optimization Analysis

**Generated:** 2025-11-08  
**Focus:** Optimizations beyond wizard validation that improve startup speed without over-engineering

## Current Startup Sequence

### Timeline (from logs)
1. **App Launch** (~0.0s)
   - App.swift init
   - AppDelegate.applicationDidFinishLaunching
   - Window controller creation

2. **Auto-Launch Sequence** (~0.0-0.1s)
   - `startAutoLaunch()` → `attemptQuietStart()` → `attemptAutoStart()` → `startKanata()`
   - Service start attempt

3. **Initial Validation** (~3.2s + 4.4s = 7.6s total)
   - Service wait: 3.151s (optimized from 10s)
   - Validation: 4.416s (cold cache)

**Total Startup Time:** ~7.6s (service wait + validation)

---

## Optimization Opportunities

### 1. ✅ **Skip Service Wait If Already Running** (Already Optimized)
**Current:** Fast process check implemented  
**Status:** ✅ Working  
**Impact:** 7.2s saved (when service is running)

---

### 2. **Skip Validation If Recently Completed** ⭐ **HIGH VALUE**
**Current:** Always validates on startup  
**Proposal:** Skip validation if completed within last 30 seconds

**Implementation:**
```swift
// In MainAppStateController
private var lastValidationTime: Date?
private let validationCooldown: TimeInterval = 30.0

func performInitialValidation() async {
    // Skip if recently validated
    if let lastTime = lastValidationTime,
       Date().timeIntervalSince(lastTime) < validationCooldown {
        AppLogger.shared.log("⏭️ [MainAppStateController] Skipping validation - completed \(Int(Date().timeIntervalSince(lastTime)))s ago")
        return
    }
    
    // ... existing validation logic ...
    lastValidationTime = Date()
}
```

**Pros:**
- ✅ Simple, low risk
- ✅ Prevents redundant validation on rapid restarts
- ✅ No UI impact (validation happens in background)
- ✅ Saves ~7.6s on rapid restarts

**Cons:**
- ⚠️ May miss state changes if user fixes issues externally
- ⚠️ Need to invalidate on wizard close

**Risk:** Low  
**Effort:** Low (~15 minutes)  
**Impact:** High (saves 7.6s on rapid restarts)

---

### 3. **Defer Non-Critical Initialization** ⭐ **MEDIUM VALUE**
**Current:** All initialization happens synchronously  
**Proposal:** Defer non-critical setup until after UI is visible

**What to Defer:**
- Notification observers (already async)
- Config file watcher setup
- Diagnostic manager initialization
- Log monitoring start

**Implementation:**
```swift
// In AppDelegate.applicationDidFinishLaunching
Task { @MainActor in
    // Critical: Window + auto-launch
    await manager.startAutoLaunch(...)
    
    // Defer non-critical setup
    Task.detached(priority: .background) {
        await setupNonCriticalServices()
    }
}
```

**Pros:**
- ✅ UI appears faster
- ✅ User can interact while background setup completes
- ✅ Low risk (non-critical services)

**Cons:**
- ⚠️ Slight complexity increase
- ⚠️ Need to handle race conditions

**Risk:** Low-Medium  
**Effort:** Medium (~1 hour)  
**Impact:** Medium (saves ~0.5-1s perceived startup)

---

### 4. **Pre-warm Caches Before Validation** ⭐ **MEDIUM VALUE**
**Current:** Caches are cold on first validation  
**Proposal:** Pre-warm caches during service wait

**Implementation:**
```swift
// In performInitialValidation()
let serviceWaitStart = Date()
let isReady = await kanataManager.waitForServiceReady(timeout: 3.0)

// Pre-warm caches while waiting (if service is ready)
if isReady {
    Task.detached {
        await PermissionOracle.shared.currentSnapshot() // Warm cache
        await PackageManager.shared.preloadCommonPaths() // Warm code signing cache
    }
}
```

**Pros:**
- ✅ Reduces cold cache penalty (~1.9s)
- ✅ Uses idle time during service wait
- ✅ No UI blocking

**Cons:**
- ⚠️ Only helps if service is ready quickly
- ⚠️ Adds complexity

**Risk:** Low  
**Effort:** Medium (~30 minutes)  
**Impact:** Medium (saves ~1.9s when service is ready)

---

### 5. **Parallelize Service Wait and UI Initialization** ⚠️ **LOW VALUE**
**Current:** Sequential (service wait → validation)  
**Proposal:** Start validation immediately, cancel if service not ready

**Pros:**
- ✅ Could save time if service starts quickly

**Cons:**
- ❌ Complex cancellation logic
- ❌ May waste work if service not ready
- ❌ Risk of race conditions
- ❌ Over-engineered for minimal gain

**Risk:** Medium-High  
**Effort:** High (~2-3 hours)  
**Impact:** Low-Medium (saves ~1-2s in best case)

**Recommendation:** ❌ **Skip** - Over-engineered, high risk

---

### 6. **Optimize Fresh Install Detection** ⭐ **LOW VALUE**
**Current:** `isFirstTimeInstall()` checks file system  
**Proposal:** Cache result in UserDefaults

**Implementation:**
```swift
func isFirstTimeInstall() -> Bool {
    // Check cached result first
    if let cached = UserDefaults.standard.object(forKey: "KeyPath.IsFirstTimeInstall") as? Bool {
        return cached
    }
    
    // Perform actual check
    let result = checkFileSystem()
    UserDefaults.standard.set(result, forKey: "KeyPath.IsFirstTimeInstall")
    return result
}
```

**Pros:**
- ✅ Simple, low risk
- ✅ Saves file system I/O

**Cons:**
- ⚠️ Minimal impact (~0.01-0.05s)
- ⚠️ Need to handle edge cases

**Risk:** Low  
**Effort:** Low (~10 minutes)  
**Impact:** Low (saves ~0.01-0.05s)

---

### 7. **Skip Auto-Launch If Service Already Running** ⭐ **MEDIUM VALUE**
**Current:** Always attempts auto-launch  
**Proposal:** Check if service is running first, skip if already running

**Implementation:**
```swift
func startAutoLaunch(...) async {
    // Fast check: Is service already running?
    if Self.isProcessRunningFast() {
        AppLogger.shared.log("⏭️ [KanataManager] Service already running - skipping auto-launch")
        await refreshStatus() // Just sync state
        return
    }
    
    // ... existing auto-launch logic ...
}
```

**Pros:**
- ✅ Simple, low risk
- ✅ Saves ~0.1-0.5s when service is running
- ✅ Reduces unnecessary work

**Cons:**
- ⚠️ Need to ensure state is synced

**Risk:** Low  
**Effort:** Low (~15 minutes)  
**Impact:** Medium (saves ~0.1-0.5s when service is running)

---

## Recommended Optimizations (Priority Order)

### Priority 1: **Skip Validation If Recently Completed** ⭐⭐⭐
- **Impact:** High (saves 7.6s on rapid restarts)
- **Risk:** Low
- **Effort:** Low (~15 minutes)
- **Recommendation:** ✅ **Implement**

### Priority 2: **Skip Auto-Launch If Service Already Running** ⭐⭐
- **Impact:** Medium (saves ~0.1-0.5s)
- **Risk:** Low
- **Effort:** Low (~15 minutes)
- **Recommendation:** ✅ **Implement**

### Priority 3: **Pre-warm Caches During Service Wait** ⭐⭐
- **Impact:** Medium (saves ~1.9s when service is ready)
- **Risk:** Low
- **Effort:** Medium (~30 minutes)
- **Recommendation:** ✅ **Consider**

### Priority 4: **Defer Non-Critical Initialization** ⭐
- **Impact:** Medium (saves ~0.5-1s perceived startup)
- **Risk:** Low-Medium
- **Effort:** Medium (~1 hour)
- **Recommendation:** ⚠️ **Consider** (if time permits)

### Priority 5: **Optimize Fresh Install Detection** ⭐
- **Impact:** Low (saves ~0.01-0.05s)
- **Risk:** Low
- **Effort:** Low (~10 minutes)
- **Recommendation:** ⚠️ **Optional** (nice to have)

---

## Summary

**Top 3 Quick Wins:**
1. ✅ Skip validation if recently completed (15 min, saves 7.6s)
2. ✅ Skip auto-launch if service already running (15 min, saves ~0.5s)
3. ✅ Pre-warm caches during service wait (30 min, saves ~1.9s)

**Total Potential Savings:**
- **Best Case:** ~10s (rapid restart with service running)
- **Typical Case:** ~2-3s (normal startup)
- **Worst Case:** ~0.5s (first launch, service not ready)

**Total Effort:** ~1 hour  
**Risk:** Low  
**Recommendation:** ✅ **Proceed with Priority 1 & 2**

---

## Implementation Notes

### Skip Validation Cooldown
- Use 30-second cooldown (configurable)
- Invalidate on wizard close
- Invalidate on manual refresh
- Log when skipping for debugging

### Skip Auto-Launch Check
- Use existing `isProcessRunningFast()` helper
- Still call `refreshStatus()` to sync state
- Log when skipping for debugging

### Pre-warm Caches
- Only pre-warm if service is ready quickly (<1s)
- Use background task priority
- Don't block UI thread

---

## Testing Plan

1. **Rapid Restart Test:**
   - Launch app → quit → relaunch within 30s
   - Verify validation is skipped
   - Verify UI still updates correctly

2. **Service Running Test:**
   - Start service manually
   - Launch app
   - Verify auto-launch is skipped
   - Verify state is synced

3. **Cache Pre-warm Test:**
   - Launch app with service ready
   - Verify validation is faster (warm cache)
   - Check logs for pre-warm activity

---

## Conclusion

**Recommended Actions:**
1. ✅ Implement Priority 1 & 2 (30 minutes total)
2. ⚠️ Consider Priority 3 if time permits (30 minutes)
3. ❌ Skip Priority 4 & 5 (low impact, not worth complexity)

**Expected Results:**
- **Rapid Restarts:** ~10s faster
- **Normal Startup:** ~2-3s faster
- **First Launch:** ~0.5s faster

All optimizations are **low risk** and **pragmatic** - no over-engineering, no brittle code.

