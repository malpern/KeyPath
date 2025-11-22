# Next Steps: Testing & Validation

## What We've Completed ✅

### Phase 2: Critical Guards - DONE
- ✅ All 5 critical guards updated to use state determination
- ✅ Performance improvements (removed redundant checks, lazy pgrep)
- ✅ UI consistency (DiagnosticsView uses state determination)
- ✅ Code quality improvements

## What's Next: Testing & Validation

### Primary Goal
**Verify that guards prevent the original problem**: App reverting to launchctl after restart/migration

### Critical Test Scenarios

#### 1. **Migration Persistence Test** (Most Important)
**Scenario**: The original bug - migration gets reset after restart

**Steps**:
1. Start with legacy installation (if exists)
2. Migrate to SMAppService via Diagnostics UI
3. Restart KeyPath app
4. **Verify**: Still using SMAppService (not reverted to launchctl)
5. **Verify**: No legacy plist recreated

**Success Criteria**:
- ✅ State remains `.smappserviceActive` or `.smappservicePending` after restart
- ✅ No legacy plist at `/Library/LaunchDaemons/com.keypath.kanata.plist`
- ✅ UI shows "Using SMAppService" (not "Using launchctl")

---

#### 2. **Guard Prevention Test**
**Scenario**: Ensure guards block legacy plist creation when SMAppService is active

**Steps**:
1. Ensure SMAppService is active (migrated state)
2. Trigger operations that might create legacy plist:
   - Click "Regenerate Services" in Diagnostics
   - Run wizard auto-fix
   - Restart unhealthy services
3. **Verify**: Legacy plist NOT created
4. **Verify**: Guards log warnings when blocking

**Success Criteria**:
- ✅ `createKanataLaunchDaemonViaLaunchctl()` returns false
- ✅ Guards log: "SMAppService is active - skipping legacy plist creation"
- ✅ No legacy plist created

---

#### 3. **Fresh Install Test**
**Scenario**: New installation with feature flag ON

**Steps**:
1. Remove all existing installations (legacy + SMAppService)
2. Fresh install via wizard
3. **Verify**: Uses SMAppService (not launchctl)
4. **Verify**: Plist in app bundle (not `/Library/LaunchDaemons`)

**Success Criteria**:
- ✅ State is `.smappserviceActive` or `.smappservicePending`
- ✅ Plist at `Bundle.main.bundlePath/Contents/Library/LaunchDaemons/com.keypath.kanata.plist`
- ✅ No legacy plist created

---

#### 4. **State Detection Consistency Test**
**Scenario**: Ensure UI and guards use same logic

**Steps**:
1. Check state via `determineServiceManagementState()`
2. Check UI display in Diagnostics
3. **Verify**: UI matches state determination

**Success Criteria**:
- ✅ UI shows same method as state determination
- ✅ No discrepancies between UI and guards

---

## Testing Approach

### Option A: Manual Testing (Recommended First)
**Pros**: Real environment, catches integration issues
**Cons**: Time-consuming, manual

**Steps**:
1. Build, sign, deploy app
2. Run each test scenario manually
3. Check logs for guard behavior
4. Verify state persistence

### Option B: Automated Unit Tests
**Pros**: Fast, repeatable
**Cons**: May miss integration issues

**What to Test**:
- State determination for all scenarios
- Guard behavior (blocks when appropriate)
- State persistence logic

### Option C: Integration Tests
**Pros**: Catches real-world issues
**Cons**: Requires test infrastructure

**What to Test**:
- End-to-end migration flow
- Restart persistence
- Guard effectiveness

---

## Recommended Next Steps

### Immediate (Today)
1. **Build, sign, deploy** the updated app
2. **Run Migration Persistence Test** (most critical)
3. **Check logs** for guard behavior
4. **Verify** state persistence after restart

### Short-term (This Week)
5. **Run all 4 test scenarios** manually
6. **Document any issues** found
7. **Fix any bugs** discovered
8. **Add unit tests** for state determination (if time)

### Medium-term (Next Week)
9. **Add integration tests** for critical flows
10. **Monitor production** for any fallback issues
11. **Gather feedback** on migration experience

---

## Success Criteria

**Phase 2 Complete When**:
- ✅ Guards prevent legacy fallback in all tested scenarios
- ✅ Migration persists across app restarts
- ✅ No regressions in existing functionality
- ✅ UI consistently shows correct state

**Ready for Production When**:
- ✅ All test scenarios pass
- ✅ No critical bugs found
- ✅ Logs show guards working correctly
- ✅ User can migrate and it persists

---

## Rollback Plan

If issues arise:
- **Feature flag**: Can disable SMAppService path via `FeatureFlags.useSMAppServiceForDaemon = false`
- **Guards**: Are additive - old code paths still exist
- **State determination**: Can be disabled if needed (though unlikely)

---

## Questions to Answer

1. **Does migration persist after restart?** (Original bug)
2. **Do guards prevent legacy plist recreation?**
3. **Is UI detection consistent with guards?**
4. **Are there any edge cases we missed?**

Let's test and find out! 🚀

