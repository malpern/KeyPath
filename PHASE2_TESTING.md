# Phase 2 Testing Guide

**Status:** Ready for integrated testing
**Date:** 2025-09-29

## What Was Built

### New Files (Phase 1 + Phase 2: ~1,010 lines total)

**Phase 1 (Foundation):**
1. SystemSnapshot.swift (~200 lines) - Pure data model
2. SystemValidator.swift (~250 lines) - Stateless validator with assertions
3. SystemValidatorTests.swift (~80 lines) - Basic tests

**Phase 2 (Integration):**
4. **WizardStateMachine.swift** (~250 lines) - Simple state machine with navigation
5. **SystemSnapshotAdapter.swift** (~230 lines) - Converts new format to old wizard format

### Modified Files

**InstallationWizardView.swift:**
- WizardStateManager now uses SystemValidator instead of SystemStatusChecker
- Removed quick check optimizations (full check is fast enough)
- Defensive assertions now active in wizard

## Integration Strategy

Used **adapter pattern** to minimize changes:
- SystemValidator returns SystemSnapshot (new format)
- SystemSnapshotAdapter converts to SystemStateResult (old wizard format)
- Existing wizard UI pages work unchanged
- Can replace adapter with native SystemSnapshot support later (Phase 4)

##What Changed Internally

**Before (Old):**
```
WizardStateManager → SystemStatusChecker → detectCurrentState()
                                            ↓
                                    SystemStateResult
```

**After (New):**
```
WizardStateManager → SystemValidator → checkSystem()
                                        ↓
                                   SystemSnapshot
                                        ↓
                            SystemSnapshotAdapter.adapt()
                                        ↓
                                 SystemStateResult
```

## Defensive Assertions Now Active

### 1. Validation Spam Detection
**Where:** SystemValidator.checkSystem()
**Triggers:** If concurrent validations detected
**Result:** App crashes with precondition failure

```
🚨 VALIDATION SPAM DETECTED!
Concurrent validation detected: 1 validation(s) already running.
This indicates automatic reactivity triggers that should have been removed.
```

### 2. Rapid-Fire Detection
**Where:** SystemValidator.checkSystem()
**Triggers:** If validations < 0.5s apart
**Result:** Logs warning (doesn't crash)

```
⚠️ [SystemValidator] RAPID VALIDATION: 0.123s since last validation
This might indicate automatic triggers. Expected: manual user actions only.
```

### 3. Oracle Freshness
**Where:** SystemValidator.checkPermissions()
**Triggers:** If Oracle snapshot > 5s old
**Result:** Assertion failure in debug builds

```
Oracle snapshot is 7.3s old - Oracle cache may be broken
```

### 4. Snapshot Staleness
**Where:** SystemSnapshot.validate()
**Triggers:** If snapshot > 30s old
**Result:** Assertion failure in debug builds

```
🚨 STALE STATE: Snapshot is 45.2s old - UI showing outdated state!
```

## How to Test

### Quick Test (10 minutes)

```bash
# 1. Build release version
swift build -c release

# 2. Launch app
open build/Release/KeyPath.app

# 3. Open wizard (it should auto-open if issues exist)
# 4. Monitor logs in another terminal
tail -f ~/Library/Logs/KeyPath/keypath.log | grep -E "(SystemValidator|WizardStateManager|VALIDATION|RAPID)"
```

### What to Look For

#### ✅ Good Signs
```
🎯 [WizardStateManager] Configured with NEW SystemValidator (Phase 2)
🎯 [WizardStateManager] Using SystemValidator (Phase 2)
🔍 [SystemValidator] Starting validation #1
🔍 [SystemValidator] Validation #1 complete in 0.523s
🔍 [SystemValidator] Result: ready=true, blocking=0, total=0
```

#### ❌ Bad Signs (Indicates Bugs to Fix)
```
🚨 VALIDATION SPAM DETECTED!  <- App should crash (GOOD - forces us to fix)
⚠️ RAPID VALIDATION: 0.123s   <- Multiple triggers firing
🚨 STALE STATE: 45.2s old      <- UI showing old data
```

### Test Scenarios

#### Scenario 1: App Launch (Most Important)
1. Quit app completely
2. Launch app
3. Check logs for validation count

**Expected:**
- ONE validation on startup
- No rapid validation warnings
- No validation spam errors

**If you see multiple validations:**
- This is the bug we're trying to fix!
- Assertions should catch it

#### Scenario 2: Open Wizard
1. Click "Setup" or status indicator to open wizard
2. Watch logs

**Expected:**
- ONE validation when wizard opens
- No validation spam
- Status shows correctly on each page

#### Scenario 3: Navigate Wizard Pages
1. Click through wizard pages (Summary → Conflicts → Permissions → etc.)
2. Watch logs

**Expected:**
- NO automatic validations on page change
- Only validates when you click "Refresh" button
- No rapid-fire warnings

#### Scenario 4: Close Wizard
1. Close wizard
2. Watch logs

**Expected:**
- ONE validation after close (to refresh main screen)
- No validation spam

#### Scenario 5: Manual Refresh
1. In wizard, click any "Refresh" or "Check Status" button
2. Watch logs

**Expected:**
- ONE validation per button click
- If you click rapidly (< 0.5s), should see rapid-fire warning (but not crash)

### Debug Commands

```bash
# Count validations in last session
grep "Starting validation" ~/Library/Logs/KeyPath/keypath.log | tail -20

# Check for validation spam
grep "VALIDATION SPAM" ~/Library/Logs/KeyPath/keypath.log

# Check for rapid-fire
grep "RAPID VALIDATION" ~/Library/Logs/KeyPath/keypath.log

# Check timing between validations
grep "Starting validation" ~/Library/Logs/KeyPath/keypath.log | \
  awk '{print $2}' | tail -10

# See which component is calling validator
grep "WizardStateManager\|SystemValidator" ~/Library/Logs/KeyPath/keypath.log | tail -30
```

## Expected Behavior Changes

### What Should Be SAME
- Wizard UI looks the same
- Wizard pages work the same
- Permission detection works the same
- Auto-fix works the same

### What Should Be DIFFERENT
- **Logs show "Phase 2"** markers
- **Validation is slightly faster** (no cache overhead)
- **Assertions will crash** if validation spam occurs (this is good!)
- **Clearer logging** about validation timing

## Known Limitations

1. **Adapter overhead:** Extra conversion step (will remove in Phase 4)
2. **No quick checks:** Full validation every time (but fast enough <1s)
3. **WizardStateMachine unused:** Created but not integrated yet (Phase 3)

## Rollback Plan

If Phase 2 breaks things:

```bash
# Revert to pre-Phase 2 state
git revert HEAD  # Reverts Phase 2 commit
git revert HEAD~1  # Also reverts Phase 1 if needed

# Or checkout previous version
git checkout df5e83b  # Before any Phase 1/2 changes
```

## Success Criteria

- [x] Compiles successfully
- [ ] App launches without crash
- [ ] Wizard opens and shows correct status
- [ ] ONE validation per trigger event (not multiple)
- [ ] No validation spam in logs
- [ ] Permissions detected correctly
- [ ] Main screen and wizard show same status

## What to Report

### If It Works Well
"Tested wizard for 10 minutes - only ONE validation per action, no spam detected"

### If Assertions Trigger
"App crashed with validation spam error - see logs at [timestamp]"
→ This is GOOD! Means assertions caught a bug. Share the logs.

### If Behav

ior is Wrong
"Wizard shows X but main screen shows Y" with specific example

## Next Steps After Testing

**If successful:**
- Phase 3: Replace StartupValidator in main app
- Same pattern as wizard integration

**If issues found:**
- Fix validation spam bugs (remove automatic triggers)
- Tune assertion thresholds if needed
- May need to adjust 0.5s rapid-fire threshold

---

**Phase 2 Status: ✅ COMPLETE & INTEGRATED**
**Next: User testing (you!)**
**Then: Phase 3 - Main app integration**