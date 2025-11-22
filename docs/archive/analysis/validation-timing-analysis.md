# Validation Timing Analysis Report

## Issue
User reports that:
- **Main screen validation (first run)**: Very slow
- **Wizard progress bar validation**: Very fast

## Key Differences

### Main Screen Validation (`MainAppStateController.performInitialValidation()`)

**First Run Only:**
1. **Wait for Kanata service** (up to 10 seconds timeout)
   ```swift
   let isReady = await kanataManager.waitForServiceReady(timeout: 10.0)
   ```

2. **Clear startup mode flags**
   ```swift
   if FeatureFlags.shared.startupModeActive {
       FeatureFlags.shared.deactivateStartupMode()
   }
   ```

3. **Invalidate Oracle cache**
   ```swift
   await PermissionOracle.shared.invalidateCache()
   ```

4. **Run validation** (WITHOUT progress callback)
   ```swift
   let snapshot = await validator.checkSystem()
   ```

**Subsequent Runs:**
- Skips service wait
- Runs validation directly

### Wizard Validation (`WizardStateManager.detectCurrentState()`)

1. **Run validation** (WITH progress callback)
   ```swift
   let snapshot = await validator.checkSystem(progressCallback: progressCallback)
   ```

**No service wait, no cache invalidation**

## Expected Timing Breakdown

### Main Screen (First Run)
- Service wait: 0-10s (depends on Kanata startup)
- Cache invalidation: ~0.1s
- Validation: ~2-6s (based on previous measurements)
- **Total: ~2-16s** (highly variable)

### Wizard Progress Bar
- Validation: ~2-6s (same as above)
- **Total: ~2-6s** (consistent)

## Root Cause Hypothesis

The main screen is slow because:
1. **Service wait overhead**: Up to 10 seconds waiting for Kanata
2. **Cache invalidation**: Forces fresh permission checks (slower)
3. **No progress feedback**: User sees spinner with no updates

The wizard is fast because:
1. **No service wait**: Assumes service is already running
2. **Uses cached permissions**: Oracle cache is still valid
3. **Progress feedback**: User sees progress bar advancing

## Recommendations

1. **Add progress callback to main screen validation**
   - Provides user feedback during wait
   - Makes perceived performance better

2. **Optimize service wait**
   - Reduce timeout or make it non-blocking
   - Show progress during wait

3. **Consider skipping cache invalidation on first run**
   - Or invalidate asynchronously
   - Don't block validation on cache clear

4. **Add timing instrumentation**
   - Log each phase duration
   - Track service wait time separately

## Next Steps

1. Extract actual timing data from logs
2. Identify which phase is the bottleneck
3. Implement optimizations based on findings

