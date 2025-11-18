# API Contract - Frozen Signatures

**Status:** ✅ FROZEN - Do not change without discussion

**Date Frozen:** 2025-11-17

**Source:** `docs/InstallerEngine-Design.html`

---

## InstallerEngine Public API

### Method 1: inspectSystem()

```swift
func inspectSystem() -> SystemContext
```

**Purpose:** Capture current system state

**Returns:** Read-only snapshot of service states, file/permission status, and helper availability

**Use cases:**
- Render current status in UI
- Decide what actions are needed
- Provide context for planning

**Wraps:** Consolidates logic from `SystemSnapshotAdapter`, `SystemRequirements`, `ServiceStatusEvaluator`, and conflict detection scripts (`dev-tools/test-updated-conflict.swift`)

---

### Method 2: makePlan()

```swift
func makePlan(for intent: InstallIntent, context: SystemContext) -> InstallPlan
```

**Purpose:** Create an execution plan without running it

**Returns:** Ordered list of operations tailored to the observed context. If prerequisites are unmet, the plan will be marked as `.blocked` with details about missing requirements.

**Parameters:**
- `intent: InstallIntent` - Desired action (`.install`, `.repair`, `.uninstall`, `.inspectOnly`)
- `context: SystemContext` - Current system state from `inspectSystem()`

**Converts intents into:**
- Required `ServiceRecipe`s
- Privileged operations
- Configuration updates
- Health check steps
- Requirement validation (admin rights, writable directories, SMAppService approval, helper registration)

**Wraps:** Captures orchestration from `WizardAutoFixer`, `LaunchDaemonInstaller` (all the `create...Service` helpers), `PackageManager`, and health/driver routines in `VHIDDeviceManager`

---

### Method 3: execute()

```swift
func execute(plan: InstallPlan, using broker: PrivilegeBroker) -> InstallerReport
```

**Purpose:** Execute the planned operations

**Returns:** Structured report with success/failure details and final state. If the plan was blocked by unmet requirements, execution stops immediately and the report indicates which requirement failed.

**Parameters:**
- `plan: InstallPlan` - Execution plan from `makePlan()`
- `using broker: PrivilegeBroker` - Strategy for executing privileged operations

**Performs actions such as:**
- Copy plists to system directories
- Bootstrap LaunchDaemons
- Restart unhealthy services
- Install log rotation
- Register SMAppService items

**Wraps:** Becomes a façade over `PrivilegedOperationsCoordinator`, `HelperManager`, Authorization Services fallbacks, and admin-dialog scripts (e.g., `dev-tools/test-admin-dialog-direct.swift`), while reusing the existing `InstallerReport` struct

---

### Method 4: run()

```swift
func run(intent: InstallIntent, using broker: PrivilegeBroker) -> InstallerReport
```

**Purpose:** Convenience wrapper that chains `inspectSystem()` → `makePlan()` → `execute()` internally

**Returns:** `InstallerReport` with full execution results

**Parameters:**
- `intent: InstallIntent` - Desired action
- `using broker: PrivilegeBroker` - Strategy for executing privileged operations

**Use cases:**
- CLI "one-button repair" automation
- Simple GUI flows
- Quick install/repair operations

**Note:** The intermediate `SystemContext` and `InstallPlan` are still available through logging for debugging and inspection.

**Wraps:** Mirrors today's wizard auto-fix button (`WizardAutoFixer.performAutoFix`) and CLI scripts that manually chain detection + install

---

## Change Policy

**These signatures are FROZEN.** Changes require:
1. Update this document
2. Update `docs/InstallerEngine-Design.html`
3. Update all callers
4. Update tests

**Rationale:** Changing signatures breaks all callers and tests. Freeze early to avoid churn.

