# Collaborators - Dependencies List

**Status:** ✅ IDENTIFIED - Classes the façade will call

**Date:** 2025-11-17

**Strategy:** Start with direct singleton calls, add DI later if needed

---

## Detection & Context Gathering

### SystemSnapshotAdapter
**Location:** `Sources/KeyPath/InstallationWizard/Core/SystemSnapshotAdapter.swift`

**What it does:**
- Converts `SystemSnapshot` (new format) to `SystemStateResult` (old wizard format)
- Determines system state priority (conflicts → kanata running → permissions → components)
- Maps issues to wizard format

**How façade will use it:**
- Call `SystemSnapshotAdapter.adapt(snapshot)` to get wizard-compatible state
- Use output to populate `SystemContext`

**Access:** Static method, no instance needed

---

### SystemRequirements
**Location:** `Sources/KeyPath/InstallationWizard/Core/SystemRequirements.swift`

**What it does:**
- Detects macOS version (modern/legacy/unknown)
- Determines required driver type (DriverKit/kernel extension)
- Validates system compatibility

**How façade will use it:**
- Call `SystemRequirements().validateSystemCompatibility()`
- Include compatibility info in `SystemContext`

**Access:** Create instance, call methods

---

### ServiceStatusEvaluator
**Location:** `Sources/KeyPath/InstallationWizard/Core/ServiceStatusEvaluator.swift`

**What it does:**
- Evaluates service health status
- Checks if services are running, loaded, healthy

**How façade will use it:**
- Call to check service health
- Include service status in `SystemContext`

**Access:** Create instance, call methods

---

### Conflict Detection Scripts
**Location:** `dev-tools/test-updated-conflict.swift`

**What it does:**
- Detects root-owned Kanata processes
- Detects any conflicting Kanata processes

**How façade will use it:**
- Extract logic into `inspectSystem()`
- Include conflicts in `SystemContext`

**Access:** Extract logic, don't call script directly

---

## Planning & Recipe Generation

### WizardAutoFixer
**Location:** `Sources/KeyPath/InstallationWizard/Core/WizardAutoFixer.swift`

**What it does:**
- Maps issues to auto-fix actions
- Performs auto-fix operations
- Determines if actions can be auto-fixed

**How façade will use it:**
- Use `canAutoFix()` to check if action is possible
- Use `performAutoFix()` logic to generate recipes
- Map `InstallIntent` to appropriate auto-fix actions

**Access:** Create instance with dependencies

---

### LaunchDaemonInstaller
**Location:** `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift`

**What it does:**
- Creates service plist files
- Generates plist content for Kanata, VHID daemon, VHID manager
- Checks service health
- Checks if services should be upgraded

**Key methods:**
- `createAllLaunchDaemonServices()` - Creates all services
- `createKanataLaunchDaemon()` - Creates Kanata service
- `shouldUpgradeKanata()` - Checks version
- `isServiceLoaded()` - Checks if service loaded
- `isServiceHealthy()` - Checks service health

**How façade will use it:**
- Call methods to generate `ServiceRecipe`s
- Use plist generation logic
- Respect service dependency order

**Access:** Create instance, call methods

**Test overrides available:**
- `LaunchDaemonInstaller.authorizationScriptRunnerOverride` - Override privilege execution
- `LaunchDaemonInstaller.isTestModeOverride` - Override test mode

---

### PackageManager
**Location:** `Sources/KeyPath/InstallationWizard/Core/PackageManager.swift`

**What it does:**
- Manages component installation
- Handles package installation logic

**How façade will use it:**
- Generate recipes for component installation
- Include in `InstallPlan` when components missing

**Access:** Create instance, call methods

---

### BundledKanataManager
**Location:** `Sources/KeyPath/InstallationWizard/Core/BundledKanataManager.swift`

**What it does:**
- Manages bundled Kanata binary
- Handles installation of bundled Kanata

**How façade will use it:**
- Generate recipes for Kanata installation
- Include in `InstallPlan` when Kanata missing

**Access:** Create instance, call methods

---

### VHIDDeviceManager
**Location:** `Sources/KeyPath/InstallationWizard/Core/VHIDDeviceManager.swift`

**What it does:**
- Manages VirtualHID device
- Checks driver version compatibility
- Detects VHID installation
- Handles VHID activation

**How façade will use it:**
- Check driver version in `inspectSystem()`
- Generate recipes for VHID operations
- Include driver checks in requirement validation

**Access:** Create instance, call methods

---

## Execution & Privilege Operations

### PrivilegedOperationsCoordinator
**Location:** `Sources/KeyPath/Core/PrivilegedOperationsCoordinator.swift`

**What it does:**
- Coordinates all privileged operations
- Handles helper vs sudo fallbacks
- Executes privileged commands safely

**Key methods:**
- `installAllLaunchDaemonServices()` - Install all services
- `restartUnhealthyServices()` - Restart services
- `installLogRotation()` - Install log rotation
- `repairVHIDDaemonServices()` - Repair VHID services
- `downloadAndInstallCorrectVHIDDriver()` - Install driver

**How façade will use it:**
- Wrap in `PrivilegeBroker` struct
- Delegate all privileged operations to coordinator
- Preserve fallback chain (helper → auth services → osascript)

**Access:** `PrivilegedOperationsCoordinator.shared` (singleton)

---

### HelperManager
**Location:** `Sources/KeyPath/Core/HelperManager.swift`

**What it does:**
- Manages privileged helper tool
- Handles helper installation
- Provides IPC to helper

**How façade will use it:**
- Used indirectly through `PrivilegedOperationsCoordinator`
- May check helper status for requirement validation

**Access:** `HelperManager.shared` (singleton)

---

## Summary: Dependency Strategy

**Start Simple:**
- Call singletons directly: `PrivilegedOperationsCoordinator.shared`
- Create instances where needed: `SystemRequirements()`, `LaunchDaemonInstaller()`
- Use existing test overrides: `LaunchDaemonInstaller.authorizationScriptRunnerOverride`

**No DI Initially:**
- No constructor injection
- No factory patterns
- No protocol abstractions

**Add Later If Needed:**
- If testing becomes difficult → Add protocols
- If we need multiple implementations → Add DI
- YAGNI principle: add complexity only when proven necessary

---

## Dependency Graph

```
InstallerEngine
├── SystemSnapshotAdapter (static)
├── SystemRequirements (instance)
├── ServiceStatusEvaluator (instance)
├── WizardAutoFixer (instance)
│   ├── KanataManager
│   ├── VHIDDeviceManager
│   ├── LaunchDaemonInstaller
│   ├── PackageManager
│   └── BundledKanataManager
├── LaunchDaemonInstaller (instance)
├── PrivilegedOperationsCoordinator.shared (singleton)
│   └── HelperManager.shared (singleton)
└── Conflict detection (extracted logic)
```

**Total dependencies:** ~8-10 classes, mostly existing singletons or simple instances

