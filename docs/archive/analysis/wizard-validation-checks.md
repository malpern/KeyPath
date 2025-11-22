# Wizard Validation Checks Analysis

## Important Distinction

**5 Validation Steps** ≠ **10 Wizard Pages**

- **5 Validation Steps**: The **system checks** that run during the progress bar phase (before you see any wizard pages)
- **10 Wizard Pages**: The **UI pages** you navigate to AFTER validation completes, based on what issues were found

The validation steps gather information about your system. Based on that information, the wizard then shows you the appropriate pages to fix issues.

## Overview

This document details the system validation checks performed when:
1. **Main screen loads** - The gear icon spins in `SystemStatusIndicator`
2. **Wizard opens** - The progress bar animates in `WizardPreflightView`

Both use the same `SystemValidator.checkSystem()` method, which performs checks sequentially (not in parallel).

## Wizard Pages (After Validation)

After validation completes, the wizard can show up to **10 pages**:

1. **Summary** - Overview of all issues
2. **Helper** - Privileged Helper installation
3. **Full Disk Access** - Optional permission
4. **Conflicts** - Resolve system conflicts
5. **Accessibility** - Accessibility permission
6. **Input Monitoring** - Input Monitoring permission
7. **Karabiner Components** - Karabiner driver setup
8. **Kanata Components** - Kanata engine setup
9. **Service** - Start keyboard service
10. **Communication** - TCP communication setup

**Note:** Not all pages are shown - only pages relevant to detected issues are displayed.

## Execution Flow

### Main Screen Load (SystemStatusIndicator)

**Trigger:** `MainAppStateController.performInitialValidation()` called on app launch

**Steps:**
1. Wait for Kanata service to be ready (first run only, up to 10s timeout)
2. Clear startup mode flag if active
3. Invalidate Oracle cache if startup mode was active
4. Call `SystemValidator.checkSystem()` (no progress callback)
5. Additional: Check TCP configuration (if state is `.active`)

### Wizard Open (WizardPreflightView)

**Trigger:** `WizardStateManager.detectCurrentState()` called when wizard opens

**Steps:**
1. Call `SystemValidator.checkSystem()` with progress callback
2. Progress updates: 0% → 20% → 40% → 60% → 80% → 100%

## Validation Checks (Sequential Order)

All checks are performed **sequentially** using `await` - none run in parallel.

| Step | Progress | Check | Sub-checks | Notes |
|------|----------|-------|------------|-------|
| **1** | 0% → 20% | **Helper** | • `HelperManager.isHelperInstalled()`<br>• `HelperManager.getHelperVersion()` (XPC test)<br>• `HelperManager.testHelperFunctionality()` (XPC test) | Checks BTM registration, binary existence, and XPC communication |
| **2** | 20% → 40% | **Permissions** | • `PermissionOracle.currentSnapshot()`<br>  - KeyPath Accessibility<br>  - KeyPath Input Monitoring<br>  - Kanata Accessibility (TCC)<br>  - Kanata Input Monitoring (TCC) | Oracle has 1.5s cache; checks TCC database |
| **3** | 40% → 60% | **Components** | • `KanataBinaryDetector.isInstalled()`<br>• `KanataManager.isKarabinerDriverExtensionEnabled()`<br>• `KanataManager.isKarabinerDaemonRunning()`<br>• `VHIDDeviceManager.detectInstallation()`<br>• `VHIDDeviceManager.detectConnectionHealth()`<br>• `VHIDDeviceManager.hasVersionMismatch()`<br>• `LaunchDaemonInstaller.getServiceStatus()` | Multiple synchronous checks |
| **4** | 60% → 80% | **Conflicts** | • `ProcessLifecycleManager.detectConflicts()` (external kanata processes)<br>• `KanataManager.isKarabinerElementsRunning()`<br>• `getKarabinerGrabberPID()` (pgrep) | Checks for conflicting processes |
| **5** | 80% → 100% | **Health** | • `KanataManager.isRunning`<br>• `KanataManager.isKarabinerDaemonRunning()`<br>• `VHIDDeviceManager.detectConnectionHealth()` | Final health verification |

## Timing Data

**Note:** Timing instrumentation has been added to `SystemValidator`. Each step now logs its duration.

### How to Capture Timing Data

1. **Launch the app** - The gear icon will spin while validation runs
2. **Monitor logs** - Look for lines starting with `⏱️ [SystemValidator] Step X`
3. **Open wizard** - The progress bar will show progress, and logs will show step timings

**Log Pattern:**
```
🔍 [SystemValidator] Starting validation #1
⏱️ [SystemValidator] Step 1 (Helper) completed in X.XXXs
⏱️ [SystemValidator] Step 2 (Permissions) completed in X.XXXs
⏱️ [SystemValidator] Step 3 (Components) completed in X.XXXs
⏱️ [SystemValidator] Step 4 (Conflicts) completed in X.XXXs
⏱️ [SystemValidator] Step 5 (Health) completed in X.XXXs
🔍 [SystemValidator] Validation #1 complete in X.XXXs
```

### Test Run 1
| Step | Check | Duration | Notes |
|------|-------|----------|-------|
| 1 | Helper | _capture from logs_ | |
| 2 | Permissions | _capture from logs_ | |
| 3 | Components | _capture from logs_ | |
| 4 | Conflicts | _capture from logs_ | |
| 5 | Health | _capture from logs_ | |
| **Total** | | _capture from logs_ | |

### Test Run 2
| Step | Check | Duration | Notes |
|------|-------|----------|-------|
| 1 | Helper | _capture from logs_ | |
| 2 | Permissions | _capture from logs_ | |
| 3 | Components | _capture from logs_ | |
| 4 | Conflicts | _capture from logs_ | |
| 5 | Health | _capture from logs_ | |
| **Total** | | _capture from logs_ | |

## Key Observations

1. **Sequential Execution**: All checks use `await` - no parallelization
2. **Progress Reporting**: Only wizard uses progress callbacks; main screen validation has no progress indicator
3. **Oracle Cache**: Permission checks benefit from 1.5s cache in `PermissionOracle`
4. **Service Wait**: Main screen waits up to 10s for Kanata service on first run
5. **TCP Check**: Additional TCP configuration check performed after validation if state is `.active`

## Logging

Validation logs use the prefix `🔍 [SystemValidator]` and include:
- Start time: `Starting validation #N`
- **Step timings**: `⏱️ [SystemValidator] Step X (Name) completed in X.XXXs` (NEW)
- Completion time: `Validation #N complete in X.XXXs`
- Results: `ready=X, blocking=Y, total=Z`

To capture timing data, monitor logs for:
```
🔍 [SystemValidator] Starting validation #1
⏱️ [SystemValidator] Step 1 (Helper) completed in X.XXXs
⏱️ [SystemValidator] Step 2 (Permissions) completed in X.XXXs
⏱️ [SystemValidator] Step 3 (Components) completed in X.XXXs
⏱️ [SystemValidator] Step 4 (Conflicts) completed in X.XXXs
⏱️ [SystemValidator] Step 5 (Health) completed in X.XXXs
🔍 [SystemValidator] Validation #1 complete in X.XXXs
```

