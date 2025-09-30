# Phase 1 Testing Guide

**Status:** Ready for manual testing
**Date:** 2025-09-29

## What Was Built

### New Files (531 lines)

1. **SystemSnapshot.swift** (~200 lines)
   - Pure data model representing complete system state
   - Computed properties for UI (`isReady`, `blockingIssues`, `allIssues`)
   - `validate()` method with staleness assertions

2. **SystemValidator.swift** (~250 lines)
   - Stateless validator (no caching, no @Published properties)
   - Calls existing services (Oracle, LaunchDaemonInstaller, VHIDDeviceManager, etc.)
   - 4 defensive assertions to catch validation spam

3. **SystemValidatorTests.swift** (~80 lines)
   - Basic smoke tests (existing test suite has unrelated errors)

### Defensive Assertions (What Will Crash the App if Broken)

#### Assertion 1: Concurrent Validation Detection
```swift
precondition(activeValidations == 0, "VALIDATION SPAM DETECTED!")
```
**Catches:** Multiple validations running simultaneously
**Example:** If Combine publisher + onChange + NotificationCenter all trigger at once

#### Assertion 2: Rapid-Fire Detection
```swift
if interval < 0.5 {
    AppLogger.shared.log("RAPID VALIDATION: 0.2s since last")
}
```
**Catches:** Validations < 0.5s apart (indicates automatic trigger)
**Example:** onChange firing on every keystroke

#### Assertion 3: Oracle Freshness
```swift
assert(oracleAge < 5.0, "Oracle snapshot is 7.3s old")
```
**Catches:** Oracle cache broken or not refreshing
**Example:** Oracle returning stale cached results

#### Assertion 4: Snapshot Staleness
```swift
assert(age < 30.0, "Snapshot is 45s old - stale UI state!")
```
**Catches:** UI displaying old snapshot data
**Example:** User looking at 45-second-old validation results

## How to Test

### Quick Smoke Test (5 minutes)

```bash
# 1. Build the app
swift build -c release
open build/Release/KeyPath.app

# 2. Monitor logs (in another terminal)
tail -f ~/Library/Logs/KeyPath/keypath.log | grep "SystemValidator"

# 3. Watch for validation behavior
#    Expected: ONE validation on app launch
#    Expected: Clean completion (no errors/assertions)
```

**What to Look For:**
```
✅ Good:
🔍 [SystemValidator] Starting validation #1
🔍 [SystemValidator] Validation #1 complete in 0.523s
🔍 [SystemValidator] Result: ready=true, blocking=0, total=0

❌ Bad (would indicate bugs):
🚨 VALIDATION SPAM DETECTED!
⚠️ RAPID VALIDATION: 0.123s since last validation
🚨 STALE STATE: Snapshot is 45.2s old
```

### Integration Test (Not Yet - Phase 3)

SystemValidator is standalone code and **not integrated** into the app yet. To use it:

```swift
// Example integration (don't do this yet - just for reference)
let processManager = ProcessLifecycleManager(kanataManager: kanataManager)
let validator = SystemValidator(processLifecycleManager: processManager, kanataManager: kanataManager)

let snapshot = await validator.checkSystem()
print("System ready: \(snapshot.isReady)")
print("Issues: \(snapshot.blockingIssues.count)")
```

This will happen in Phase 2 when we build WizardStateMachine, and Phase 3 when we replace StartupValidator.

## Validation Checklist

### Compilation
- [x] `swift build` succeeds ✅
- [x] No new compilation errors
- [x] Only warnings are from existing code (deprecated String init)

### Code Quality
- [x] Stateless design (no @Published, no cache)
- [x] Defensive assertions in place
- [x] Logging for observability
- [x] Calls existing services (no reimplementation)

### Documentation
- [x] Comments explain defensive assertions
- [x] IMPROVEPLAN.md describes architecture
- [x] This testing guide exists

## What's NOT Tested Yet

- **Actual validation spam detection** - Need to integrate to trigger assertions
- **UI state flow** - Need WizardStateMachine (Phase 2)
- **Real permission flows** - Need full integration (Phase 3)
- **Assertion recovery** - What happens after crash? (By design: app crashes, user reports bug)

## Expected Behavior (After Full Integration)

### Successful Case
1. User launches app
2. ONE validation runs (not multiple)
3. Status shows correctly (green/red/spinner)
4. No assertions triggered
5. Logs show single validation cycle

### Validation Spam Case (What We're Preventing)
1. User launches app
2. Multiple triggers fire (Combine + onChange + Notification)
3. **App crashes with precondition failure** 💥
4. Log shows: "🚨 VALIDATION SPAM DETECTED!"
5. Developer investigates and removes automatic trigger

**Key insight:** Crashing is GOOD here - it forces us to fix the root cause instead of hiding validation spam bugs.

## Next Steps

### For Developer (You)
1. ✅ Phase 1 complete - New code compiles
2. ⏸️  Don't integrate yet - wait for Phase 2 (WizardStateMachine)
3. 📋 Review SystemValidator.swift code (optional)
4. 🚀 Ready to start Phase 2 when you say go

### For Claude (Me)
1. ✅ SystemValidator built with defensive assertions
2. ✅ Code compiles and committed
3. ⏳ Awaiting your feedback on Phase 1
4. 🎯 Ready to build Phase 2: WizardStateMachine

## Questions to Consider

1. **Do the assertions make sense?** Too aggressive? Too lenient?
2. **Is the 0.5s rapid-fire threshold right?** Or should it be 1.0s?
3. **Should assertions crash in production?** Currently using `precondition()` which crashes in release builds too
   - Alternative: Log error and return cached state
4. **Ready for Phase 2?** Or want to adjust Phase 1 first?

## Debug Commands

```bash
# Check validation counters
grep "Starting validation" logs | wc -l

# Check for assertions triggered
grep "VALIDATION SPAM" logs
grep "RAPID VALIDATION" logs
grep "STALE STATE" logs

# Check Oracle freshness
grep "Oracle snapshot" logs | tail -5

# Time between validations
grep "Starting validation" logs | awk '{print $2}' | xargs -I {} date -j -f "%H:%M:%S" {} +%s
```

---

**Phase 1 Status: ✅ COMPLETE**
**Next: Phase 2 - WizardStateMachine**