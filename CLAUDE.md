# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CURRENT SESSION STATUS

**LATEST WORK:** Block 3 UI Polish Complete (December 16, 2025)

**Recent Commits:**
- `9231fb22` chore: format and lint Block 3 code
- `e0c50611` Document Block 3 completion
- `95c2c7d5` Finalize Block 3 status polish
- `ba123bb6` block3: add Settings status details and log shortcuts
- `e6d1346e` block3: align Settings status with wizard semantics
- `47466c22` fix: check components before service status in wizard (CRITICAL BUG FIX)

**Current Session Accomplishments:**
1. **Critical Bug Fix**: Fixed wizard false positive where system showed green ✅ when Kanata binary was missing
   - Root cause: SystemContextAdapter checked service status BEFORE verifying components existed
   - Solution: Reordered checks to validate components first (Conflicts → Components → Permissions → Service Status)
2. **Block 3 Cherry-Pick**: Successfully integrated all Block 3 UI improvements on top of bug fix
   - Detailed status rows mirroring wizard pages
   - SystemDiagnostics shortcuts (one-click access to logs and System Settings)
   - Multi-level health indicators (Success/Warning/Critical/Checking)
   - Multiple action buttons per status card
3. **Full Notarization**: Built, signed, notarized (Submission ID: cf628ac7-efba-4183-a0d6-765f569e90fa), and deployed

**Tagged State:** `mappingWorking` (9231fb22) - Block 2 + bug fix + Block 3 UI polish

**⚠️ INCOMPLETE WORK (requires follow-up):**
- HELPER.md: Phase 4 pending (Documentation & Testing) - Phases 1-3.5 complete

**✅ Privileged Helper (Nov 2025):**
- Phase 1: Coordinator extraction ✅
- Phase 2A: Helper infrastructure ✅
- Phase 2B: Caller migration ✅
- Phase 3: Build scripts & embedding ✅
- Phase 3.5: Security hardening ✅
- Phase 4: Documentation complete ✅, testing pending (requires maintainer for release build)

**✅ ADR-012 Complete (verified Nov 24, 2025):**
- Driver version detection: `VHIDDeviceManager.hasVersionMismatch()` → `SystemContext.components.vhidVersionMismatch`
- Fix button wiring: `ActionDeterminer` adds `.fixDriverVersionMismatch` action
- Dialog + download: `WizardAutoFixer.fixDriverVersionMismatch()` shows dialog and installs v5.0.0

**✅ COMPLETED (Nov 24, 2025):**
- **Strangler Fig Migration:** All 5 phases complete
  - Phase 1: Internalize Repair Recipes ✅
  - Phase 2: Expose Health Check APIs ✅
  - Phase 3: Test Sweep ✅
  - Phase 4: Decommission Legacy Managers ✅
  - Phase 5: Cleanroom Post-Refactor Pass ✅

**Core Architecture (Stable):**
- **InstallerEngine:** Primary façade for all installation/repair logic (Strangler Fig complete)
- **Single Executable Target:** Reverted from split modules for simplicity (see ADR-010)
- **Fast Test Suite:** Tests complete in <5 seconds
- **TCP Communication:** Primary protocol between KeyPath and Kanata (no authentication - see ADR-013)
- **PermissionOracle:** Single source of truth for all permission detection (DO NOT BREAK)
- **TCC-Safe Deployment:** Stable Developer ID signing preserves Input Monitoring permissions

## Project Overview

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features a SwiftUI frontend and a LaunchDaemon architecture for reliable system-level key remapping.

## High-Level Architecture

### System Design
```
KeyPath.app (SwiftUI) → InstallerEngine → LaunchDaemon/PrivilegedHelper
          ↓                    ↓
    KanataManager      SystemContext (State)
          ↓
   TCP/Runtime Control
```

### Core Components
- **KeyPath.app**: SwiftUI application with Liquid Glass UI (macOS 15+)
- **InstallerEngine**: Unified façade for installation, repair, and system inspection
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **Configuration**: User config at `~/Library/Application Support/KeyPath/keypath.kbd`
- **System Integration**: Uses CGEvent taps for key capture and launchctl for service management

### Key Manager Classes
- **`InstallerEngine`**: **The Façade** - Handles all "write" operations (install/repair/uninstall) and system inspection.
- **`KanataManager`**: **Runtime Coordinator** - orchestrates active service, handles config reloading, user interactions (NOT ObservableObject).
- `KanataViewModel`: **UI Layer (MVVM)** - ObservableObject with @Published properties for SwiftUI reactivity.
- `ConfigurationService`: Configuration file management (reading, writing, parsing, validation, backup).
- `ServiceHealthMonitor`: Health checking, restart cooldown, recovery strategies.
- `PermissionOracle`: **🔮 CRITICAL ARCHITECTURE** - Single source of truth for all permission detection.
- `UserNotificationService`: macOS Notification Center integration.
- `InstallationWizard/`:
  - `InstallerEngine` powers the wizard logic.
  - `WizardNavigationEngine`: State-driven wizard navigation.

### 🔗 Action URI System (`keypath://`)

KeyPath registers a custom URL scheme for deep linking and Kanata integration:

**URL Format:** `keypath://{action}/{target}[/{subaction}][?query=params]`

**Supported Actions:**
| Action | Format | Example |
|--------|--------|---------|
| `launch` | `keypath://launch/{app}` | `keypath://launch/Safari` |
| `fakekey` | `keypath://fakekey/{name}/{action}` | `keypath://fakekey/nav-mode/tap` |
| `layer` | `keypath://layer/{name}` | `keypath://layer/vim` |
| `rule` | `keypath://rule/{id}/fired` | `keypath://rule/hyper/fired` |
| `notify` | `keypath://notify?title=X&body=Y` | `keypath://notify?title=Done&body=Saved` |
| `open` | `keypath://open/{url}` | `keypath://open/github.com` |

**Key Components:**
- `KeyPathActionURI`: Parses `keypath://` URLs into action, target, path components, and query items
- `ActionDispatcher`: Routes URIs to handlers; singleton with `onError` and `onLayerAction` callbacks
- `VirtualKeyParser`: Extracts virtual keys from `defvirtualkeys`/`deffakekeys` blocks in config

**Integration with Kanata:**
```lisp
;; In keypath.kbd - trigger KeyPath actions via keyboard shortcuts
;; Note: Always use full application names in launch aliases (e.g., launch-terminal, not launch-term)
;; Use shorthand colon syntax for cleaner configs (lowercase resolves to Title Case)
(defalias
  launch-terminal (push-msg "launch:terminal")
  launch-obsidian (push-msg "launch:obsidian")
  nav-on (push-msg "fakekey:nav-mode:tap")
)
```

**External Triggering (Terminal/Raycast/Alfred):**
```bash
open "keypath://fakekey/email-sig/tap"
open "keypath://launch/Obsidian"
```

**Error Handling:** `ActionDispatcher.onError` is wired to `UserNotificationService.notifyActionError()` for user-visible feedback on failures.

### 🔮 PermissionOracle Architecture (CRITICAL - DO NOT BREAK)

**THE FUNDAMENTAL RULE: Apple APIs ALWAYS take precedence over TCC database**

1. **APPLE APIs** (IOHIDCheckAccess from GUI context) → **AUTHORITATIVE**
   - `.granted` / `.denied` → TRUST THIS RESULT
   - `.unknown` → Proceed to TCC fallback
2. **TCC DATABASE** → **NECESSARY FALLBACK** for `.unknown` cases
   - Required for chicken-and-egg wizard scenarios
3. **FUNCTIONAL VERIFICATION** → Disabled in TCP-only mode

**✅ CORRECT BEHAVIOR:**
- Trust Apple API results unconditionally.
- DO use TCC database only when Apple API returns `.unknown`.
- Log source clearly: "gui-check" vs "tcc-fallback".

### 🎯 Validation Architecture (InstallerEngine Era)

**Validation is now pull-based via `InstallerEngine.inspectSystem()`**:
- **`inspectSystem()`** returns a `SystemContext` snapshot.
- **`SystemValidator`** is the internal engine used by `inspectSystem()`.
- **No Reactive Spam**: We explicitly request context when needed (app launch, wizard open/close, refresh).

**Critical Design Pattern:**
```swift
let engine = InstallerEngine()
let context = await engine.inspectSystem() // Returns pure value struct
if context.permissions.inputMonitoring != .granted { ... }
```

## 🚫 Critical Anti-Patterns to Avoid

### Permission Detection
❌ **Never bypass Oracle** - All permission checks must go through `PermissionOracle.shared`.
❌ **Never check permissions from root process** - IOHIDCheckAccess unreliable for daemons.
✅ **Always** use Oracle for GUI checks.

### Service Management
❌ **Do not use KanataManager for installation** - Use `InstallerEngine.run(intent: .install)`.
❌ **Do not manually call launchctl** - Use `InstallerEngine` recipes.
❌ **No restart loops** - Use cooldown timers.

### Test Performance
❌ **No real sleeps** - Use backdated timestamps (`Date().addingTimeInterval(-3.0)`).
✅ **Mock time control** - Keep tests fast (<5s total).

### Test Seams (CRITICAL)
❌ **Never call real `pgrep`** - Tests using `InstallerEngine`, `RuntimeCoordinator`, or `SystemValidator` will deadlock.
✅ **Always use `KeyPathTestCase` base class** - Automatically sets up `VHIDDeviceManager.testPIDProvider = { [] }`.
✅ **Or manually set seam** - If not using base class: set `VHIDDeviceManager.testPIDProvider` in setUp/tearDown.

**Why?** `VHIDDeviceManager.detectConnectionHealth()` spawns `pgrep` subprocesses with 3s timeouts that deadlock during rapid parallel test execution.

## 📜 Architecture Decision Records

### ADR-015: InstallerEngine Façade (Completed Nov 2025) ✅
Unified all installation/repair logic into `InstallerEngine`.
- **Input**: `InstallIntent` (.install, .repair, .uninstall)
- **Output**: `InstallerReport`
- **Logic**: `inspectSystem()` → `makePlan()` → `execute()`
- **Replaces**: `WizardAutoFixer`, `LaunchDaemonInstaller` direct calls, `SystemStatusChecker`.

### ADR-001: Oracle Pattern ✅
Single source of truth for all permission detection.

### ADR-006: Oracle Apple API Priority ✅
Apple API results are AUTHORITATIVE.

### ADR-008: Validation Refactor ✅
Stateless `SystemValidator` behind `InstallerEngine`.

### ADR-009: Service Extraction & MVVM ✅
`KanataManager` broken down; `KanataViewModel` holds UI state.

### ADR-013: TCP Communication Without Authentication ⚠️
Used for localhost IPC. No auth supported by Kanata 1.9.0 TCP server.

### ADR-014: XPC Signature Mismatch Prevention ✅
Robust app restart logic to prevent mismatched helpers.

### ADR-016: TCC Database Reading for Sequential Permission Flow ✅
**Context**: The wizard needs to guide users through Accessibility and Input Monitoring permissions one at a time. Without pre-flight detection, starting Kanata would trigger both system permission dialogs simultaneously, creating a confusing UX.

**Decision**: Read the TCC database (`~/Library/Application Support/com.apple.TCC/TCC.db`) to detect Kanata's permission state before prompting. This is a read-only operation used as a UX optimization.

**Why not "try and see"?**
- `IOHIDCheckAccess()` only works for the calling process (KeyPath), not for checking another binary (Kanata)
- Starting Kanata to probe permissions triggers simultaneous AX+IM prompts
- PR #1759 to Kanata proved daemon-level permission checking is unreliable (false negatives for root processes)

**Why this is acceptable:**
- Read-only (not modifying TCC) - Apple's guidance is primarily about preventing TCC writes/bypasses
- Graceful degradation: Falls back to `.unknown` if TCC read fails (no FDA)
- GUI context: Runs in KeyPath app (user session), not daemon
- UX requirement: Sequential permission prompts are essential for user comprehension
- Apple policy: macOS protects TCC.db with Full Disk Access; read access with user-granted FDA is allowed, while writes require Apple-only entitlements and are effectively blocked. Our usage is read-only.

**Alternative considered**: Contributing `--check-permissions` to Kanata upstream. Rejected because maintainer has no macOS devices and the API (`IOHIDCheckAccess`) doesn't work correctly from daemon context anyway.

### ADR-017: InstallerEngine Protocol Segregation (ISP) ✅
Three separate protocols exist for InstallerEngine - this is intentional Interface Segregation:
- `InstallerEngineProtocol` (4 methods) - CLI layer, @MainActor
- `WizardInstallerEngineProtocol` (1 method) - Wizard layer, Sendable for concurrency
- `InstallerEnginePrivilegedRouting` (3 methods) - Services layer, throws

**Why separate:** Zero method overlap. Each consumer gets exactly what it needs. Different Sendable/throwing requirements. Smaller test mocks. **Do not consolidate.**

### ADR-018: HelperProtocol XPC Duplication ✅
`HelperProtocol.swift` exists as identical copies in two locations:
- `Sources/KeyPathAppKit/Core/HelperProtocol.swift`
- `Sources/KeyPathHelper/HelperProtocol.swift`

**Why duplicated:** XPC architecture requires the protocol compiled into both app and helper separately - they cannot share a module at runtime. The helper is a standalone Mach-O binary.

**Risk:** If files diverge, XPC calls fail at runtime with selector-not-found errors.

**Mitigation:** `HelperProtocolSyncTests` validates both files are identical. CI will fail if they diverge.

**When modifying:** Update BOTH files, then run `swift test --filter HelperProtocolSyncTests`.

### ADR-019: Test Seams via TestEnvironment Checks ✅
Production code uses `TestEnvironment.isRunningTests` checks (37 occurrences) to disable side effects during testing.

**What's protected:** Process spawning (`pgrep`), CGEvent taps, sound playback, TCP connections, modal alerts, Notification Center, file watchers.

**Why not full DI:** Would require injecting SoundManager, NotificationService, EventTapController, SafetyAlertPresenter, shell runners, TCP clients, etc. - massive refactoring for marginal benefit.

**Why this is safe:** These checks guard **side effects**, not business logic. Core logic still executes and is tested.

**Escape hatches:** `KEYPATH_FORCE_REAL_VALIDATION=1` forces real behavior when needed.

**For new code:** Prefer injectable seams (like `VHIDDeviceManager.testPIDProvider`) over environment checks where practical. Use `TestEnvironment.isRunningTests` for UI/system side effects that would disrupt test execution.

### ADR-020: Process Detection Strategy (pgrep vs launchctl) ✅
Two approaches for detecting running processes, each for different scenarios:

**Use `launchctl` (preferred for our services):**
- Checking if `com.keypath.kanata` or `com.keypath.karabiner-vhiddaemon` is running
- Fast, reliable, no subprocess spawning race conditions
- Already migrated in `SystemValidator`, `ServiceHealthChecker`

**Use `pgrep` (required for these cases):**
- **External processes** (Karabiner's `karabiner_grabber`, `VirtualHIDDevice-Daemon`) - not our launchd services
- **Orphan detection** - finding kanata processes NOT managed by launchd
- **Post-kill verification** - checking if process died after `pkill`
- **Diagnostics** - enumerating ALL matching processes

**Do not migrate remaining pgrep usages** - they exist for scenarios where launchctl cannot help.

### ADR-021: Conservative Timing for VHID Driver Installation ✅
The "fix Karabiner driver" operation takes ~11 seconds. This is intentional.

**Timing breakdown in `VHIDDeviceManager.downloadAndInstallCorrectVersion()`:**
| Step | Operation | Sleep | Purpose |
|------|-----------|-------|---------|
| 1 | `systemextensionsctl uninstall` | 2s | Wait for DriverKit extension removal |
| 2 | `installer -pkg` (admin prompt) | 2s | Wait for pkg postinstall scripts |
| 3 | Post-install settle | 3s | Allow DriverKit extension registration |
| 4 | `activate` command | 2s | Wait for manager activation |

**Why not optimize?**
1. **Rare operation**: Driver install happens once per machine, or on Kanata major version upgrades (yearly)
2. **Reliability over speed**: DriverKit extension loading is asynchronous and timing varies by:
   - SSD speed (especially on older Macs or VMs)
   - System load (Spotlight indexing, Time Machine, etc.)
   - macOS version (DriverKit behavior differs across versions)
3. **No reliable completion signal**: `systemextensionsctl` and `installer` return before async work completes
4. **Failure cost is high**: A race condition here leaves the user with a broken driver requiring manual intervention

**Alternatives considered and rejected:**
- **Poll-based verification**: DriverKit activation has no reliable API to poll; `detectActivation()` checks file presence, not extension loading state
- **Reduce sleeps by 50%**: Tested; caused intermittent failures on slower machines
- **Skip uninstall for same version**: Doesn't help upgrade cases; risks corrupted state

**Decision**: Keep conservative 9s of sleeps + ~2s command execution. User sees progress UI during this time. The 11 seconds ensures reliability across all supported hardware configurations.

### ADR-022: No Concurrent pgrep Calls in TaskGroups ✅
Concurrent calls to functions that spawn pgrep subprocesses with retry logic can hang indefinitely.

**The Bug (November 2024):**
- `SystemValidator.performValidationBody()` runs 5 checks in a `withTaskGroup`
- Both `checkComponents()` and `checkHealth()` called `detectConnectionHealth()`
- `detectConnectionHealth()` → `detectRunning()` → `evaluateDaemonProcess()` spawns pgrep via `Task.detached`
- When daemon isn't running, both tasks entered 500ms retry sleeps
- Concurrent pgrep subprocesses caused one task to never complete
- The TaskGroup's `for await result in group` loop hung forever

**Root Cause:** `Process.waitUntilExit()` inside `Task.detached` with concurrent calls creates contention that can cause hangs.

**Prevention Rules:**
1. **Never call the same subprocess-spawning function from multiple TaskGroup tasks**
2. **Use launchctl-based checks** (`ServiceHealthChecker`) for concurrent health checking
3. **Reserve pgrep** for single-caller scenarios: diagnostics, orphan detection, post-kill verification
4. **Add ⚠️ CONCURRENCY WARNING comments** to functions with retry/sleep logic

**Code Pattern:**
```swift
// ❌ BAD - Both tasks call detectConnectionHealth() which has retries
withTaskGroup { group in
    group.addTask { await checkComponents() }  // calls detectConnectionHealth()
    group.addTask { await checkHealth() }      // also calls detectConnectionHealth()
}

// ✅ GOOD - Only one task uses pgrep-based check
withTaskGroup { group in
    group.addTask { /* use ServiceHealthChecker.getServiceStatus() */ }
    group.addTask { await checkHealth() }  // only caller of detectConnectionHealth()
}
```

### ADR-023: No Config File Parsing - Use TCP and Simulator ✅
KeyPath must NEVER parse Kanata config files directly. All config understanding comes from Kanata itself.

**Decision:** Use TCP communication and the kanata-simulator for all config-related information:
- **Layer names and state**: Query via TCP `layer-names` and `current-layer` commands
- **Key mappings per layer**: Use kanata-simulator with layer-switch key held
- **Config validation**: Let Kanata validate configs, report errors via TCP

**Why not parse configs?**
1. **Kanata is the source of truth** - Parsing would create a shadow implementation that can drift
2. **Config syntax is complex** - Aliases, macros, tap-hold, forks, layer-switch, includes, variables
3. **Maintenance burden** - Every Kanata syntax change would require KeyPath updates
4. **Already solved** - Simulator handles all edge cases correctly

**Implementation approach:**
- TCP for runtime state (current layer, layer list)
- Simulator for static analysis (what does key X output in layer Y?)
- If simulator lacks a feature, extend it in our local Kanata fork (`External/kanata`)

**What's allowed:**
- Reading config file path to pass to simulator
- Checking if config file exists
- Computing file hash for cache invalidation

**What's NOT allowed:**
- Regex/parsing to extract layer names, aliases, key mappings
- Interpreting Kanata syntax (defsrc, deflayer, defalias, etc.)
- Building any data structures from config text

### ADR-024: Custom Key Icons and Emphasis via push-msg (Partial ⚠️)
Users can specify custom icons and visual emphasis for keys in the overlay using Kanata's `push-msg` action.

**Status as of v1.0.0-beta4:**
- ✅ **Key Emphasis**: Fully implemented and working
- ⚠️ **Custom Icons**: Infrastructure in place, display logic deferred (see "Remaining Work" below)

#### Custom Icons

**Syntax in kanata config:**
```lisp
(defalias
  vim-left (multi left (push-msg "icon:arrow-left"))
  launch-safari (multi (push-msg "launch:safari") (push-msg "icon:safari"))
  nav-home (multi home (push-msg "icon:home"))
)
```

**KeyPath-side icon registry:**
```swift
enum IconSource {
    case sfSymbol(String)    // SF Symbol name -> Image(systemName:)
    case appIcon(String)     // App name -> NSWorkspace icon lookup
    case text(String)        // Fallback to text label
}

let iconRegistry: [String: IconSource] = [
    // Navigation (SF Symbols)
    "arrow-left": .sfSymbol("arrow.left"),
    "arrow-right": .sfSymbol("arrow.right"),
    "arrow-up": .sfSymbol("arrow.up"),
    "arrow-down": .sfSymbol("arrow.down"),
    "home": .sfSymbol("house"),

    // Apps (resolved via NSWorkspace)
    "safari": .appIcon("Safari"),
    "terminal": .appIcon("Terminal"),
    "obsidian": .appIcon("Obsidian"),
    "finder": .appIcon("Finder"),
]
```

**Icon Flow:**
1. User presses key with `(push-msg "icon:arrow-left")`
2. Kanata sends `{"MessagePush":{"message":"icon:arrow-left"}}` via TCP
3. KeyPath receives message, looks up `arrow-left` in registry
4. Overlay displays SF Symbol `arrow.left` on that key

#### Key Emphasis

Make specific keys visually "pop out" in the overlay - useful for highlighting core keys in a layer (e.g., HJKL in vim/nav layer).

**Syntax in kanata config:**
```lisp
;; Emphasize keys when entering nav layer
(defalias
  nav-on (multi
           (layer-while-held nav)
           (push-msg "emphasis:h,j,k,l"))
)

;; Or with layer-switch
(deflayer base
  ...
  @nav-on
  ...
)
```

**Emphasis Flow:**
1. Layer activates, sends `(push-msg "emphasis:h,j,k,l")`
2. Kanata sends `{"MessagePush":{"message":"emphasis:h,j,k,l"}}` via TCP
3. KeyPath parses comma-separated key names, maps to key codes
4. Overlay renders emphasized keys with visual distinction (glow, color pop, larger size)
5. Emphasis clears automatically on layer change, or via `(push-msg "emphasis:clear")`

**Visual Treatment Options:**
- Subtle glow/halo effect
- Accent color background
- Slightly larger scale (1.1x)
- Bolder font weight
- Border highlight

#### Implementation Status

**✅ COMPLETED (v1.0.0-beta4):**

**Key Emphasis:**
- `KeyboardVisualizationViewModel.customEmphasisKeyCodes` state tracking
- `.kanataMessagePush` notification infrastructure
- `RuleCollectionsManager` posts notification for non-URI push messages
- Message parsing: `emphasis:h,j,k,l` and `emphasis:clear`
- Merges custom emphasis with auto-emphasis (HJKL on nav layer)
- Visual treatment: Orange background (via existing `isEmphasized` in OverlayKeycapView)

**Icon Infrastructure:**
- `KeyIconRegistry` with 50+ icon mappings (SF Symbols + app icons)
- `KeyIconSource` enum (sfSymbol/appIcon/text)
- `.kanataMessagePush` notification receives `icon:...` messages
- Messages are logged but not yet displayed

**⚠️ REMAINING WORK:**

**Custom Icon Display (Deferred to future release):**

**Design Challenge:**
The current `push-msg` protocol doesn't include key context. When Kanata sends:
```json
{"MessagePush":{"message":"icon:arrow-left"}}
```
We receive the icon name but not which key sent it.

**Possible Solutions (not yet implemented):**
1. **Extract from layer mapping** (recommended):
   - During `LayerKeyMapper.buildMapping()`, parse output strings for `(push-msg "icon:X")`
   - Store icon name in `LayerKeyInfo` alongside `appLaunchIdentifier`
   - Display during layer rendering (persistent for the layer)
   - **Effort:** ~2-3 hours, requires careful layer mapping logic

2. **Track most-recent key**:
   - Associate icon with last key pressed before message arrives
   - **Risk:** Fragile timing, could mis-associate icons
   - **Not recommended**

3. **Upstream Kanata change**:
   - Add key context to MessagePush events
   - Requires upstream PR to Kanata
   - **Effort:** Unknown, depends on maintainer availability

4. **Scope reduction**:
   - Use icons only for app-launch actions (we already track these)
   - Skip generic icon support
   - **Trade-off:** Less flexible than ADR design

**Recommended Next Steps:**
- Implement solution #1 (extract from layer mapping) in v1.0.0-beta5
- Add `iconName: String?` field to `LayerKeyInfo`
- Update `OverlayKeycapView` to display custom icons when present
- Test with configs using `(push-msg "icon:...")` in outputs

**Files Involved:**
- `KeyboardVisualizationViewModel.swift` - Already has `customIcons` state (unused)
- `KeyIconRegistry.swift` - Icon registry ready to use
- `LayerKeyMapper.swift` - Needs icon extraction logic
- `LayerKeyInfo.swift` - Needs `iconName` field
- `OverlayKeycapView.swift` - Needs icon rendering logic

#### Benefits
- Config stays simple (semantic names, not paths or bundle IDs)
- KeyPath controls rendering (can update visuals without config changes)
- Extensible (add emoji, custom images, animations later)
- Follows ADR-023 (no config parsing - uses TCP messages)
- User controls what's emphasized per layer (not automatic)

### ADR-025: Configuration Management - One-Way Write with Segmented Ownership ✅
KeyPath uses a one-way write architecture for config management. JSON stores are the source of truth; the kanata config file is generated output.

**Context:** Managing keyboard remapping configuration involves:
- Rule collections (Vim, Caps Lock, etc.) with enable/disable state
- Custom user-defined rules
- The actual `keypath.kbd` file that Kanata reads
- Runtime state (active layer) from Kanata via TCP

**Decision:** JSON stores are the source of truth with one-way generation to config file.

```
┌─────────────────────────────────────────────────────────┐
│            SOURCE OF TRUTH (JSON Stores)                │
├──────────────────────────┬──────────────────────────────┤
│  RuleCollections.json    │    CustomRules.json          │
│  (collection states)     │    (user-defined rules)      │
└────────────┬─────────────┴──────────────┬───────────────┘
             │                            │
             └──────────┬─────────────────┘
                        │ ONE-WAY GENERATION
                        ▼
┌─────────────────────────────────────────────────────────┐
│              keypath.kbd (Generated Output)             │
├─────────────────────────────────────────────────────────┤
│  ;; === KEYPATH MANAGED ===                             │
│  (defsrc ...) (deflayer base ...)                       │
│                                                         │
│  ;; === USER SECTION (preserved) ===                    │
│  (defalias my-advanced-stuff ...)                       │
└─────────────────────────────────────────────────────────┘
                        │
                        │ Kanata reads
                        ▼
┌─────────────────────────────────────────────────────────┐
│              TCP (Runtime State Only)                   │
│  - Active layer, layer names                            │
│  - Key events, push-msg                                 │
└─────────────────────────────────────────────────────────┘
```

**Why NOT parse the kanata config:**
1. **Kanata syntax is complex** - Lisp-like with macros, aliases, tap-hold, forks, layers, includes, variables
2. **Maintenance burden** - Every Kanata syntax change would break KeyPath's parser
3. **Kanata is authoritative** - We'd create a shadow implementation that drifts from reality
4. **TCP provides runtime state** - Active layer, layer names come from Kanata directly

**Key invariants:**

1. **Save order matters** (implemented in `RuleCollectionsManager.regenerateConfigFromCollections`):
   ```swift
   // Config validates and writes FIRST
   try await configurationService.saveConfiguration(ruleCollections, customRules)
   // Only then persist to stores (atomic success)
   try await ruleCollectionStore.saveCollections(ruleCollections)
   try await customRulesStore.saveRules(customRules)
   ```
   This prevents store/config mismatch if validation fails.

2. **Segmented ownership** - KeyPath only modifies its managed sections (sentinel blocks like `KP:BEGIN`/`KP:END`). User additions outside these blocks are preserved.

3. **Single write path** - ALL config writes go through `RuleCollectionsManager.regenerateConfigFromCollections()`. No direct writes to config file from other components.

**What about external config edits?**
- File watcher detects changes but does NOT sync back to JSON stores
- Manual edits in user section are preserved
- Manual edits in KeyPath-managed section will be overwritten on next save
- Future: Add "import config" feature for advanced users

**What about AI-generated configs?**
- Must flow through RuleCollectionsManager, not direct file writes
- SaveCoordinator should delegate to RuleCollectionsManager for config persistence

**Runtime state via TCP (not config parsing):**
- Layer names: `layer-names` TCP command
- Active layer: `current-layer` TCP command
- Key mappings: kanata-simulator with layer held
- See ADR-023 for details

### ADR-026: System Validation Ordering - Components Before Service Status ✅
System health validation must check component existence BEFORE checking service status to prevent false positives.

**Context (December 2025):** The wizard displayed all green checkmarks (system healthy) but mappings failed with "Kanata Installation Required" error. The Kanata binary was missing from `/Library/KeyPath/bin/kanata`, yet the system was declared `.active`.

**Root Cause:** `SystemContextAdapter.adaptSystemState()` checked if `kanataRunning == true` BEFORE verifying components existed. If `ServiceHealthChecker.isServiceHealthy()` returned a false positive (during the 2-second warmup period after service restart, or due to any health check bug), the system would be declared `.active` without ever checking if the Kanata binary existed.

**Decision:** Validation checks MUST follow this order:

```swift
// ✅ CORRECT ORDER (enforced in SystemContextAdapter.adaptSystemState)
1. Conflicts          // Highest priority - blocks everything
2. Components         // Must exist before anything can run
3. Permissions        // Required for services to work
4. Service status     // Only checked if components exist + permissions granted
5. Daemon health      // Final check
```

**Why This Matters:**

1. **Health checks can have false positives** - Warmup windows, race conditions, bugs
2. **Components are prerequisites** - A service can't truly be "running" if its binary doesn't exist
3. **Fail-fast on missing components** - Better to show "missing binary" than "everything's working"
4. **Prevents confusion** - Users shouldn't see green checkmarks when critical files are missing

**Code Location:** `Sources/KeyPathAppKit/InstallationWizard/Core/SystemContextAdapter.swift:28-71`

**What NOT to do:**
- ❌ Don't check service status before verifying components exist
- ❌ Don't trust health checks unconditionally - validate prerequisites first
- ❌ Don't reorder these checks without understanding the implications

**What to do when adding new checks:**
- Ask: "Is this a prerequisite for something else?" → Place it earlier
- Ask: "Can this have false positives?" → Validate prerequisites first
- Ask: "What's the user impact if this check is wrong?" → Fail-fast on critical items

**Related:** This follows the same principle as ADR-006 (Apple API priority) - trust authoritative sources over derivative checks. File existence is more authoritative than service health reports.

## Build Commands

```bash
swift build             # Development
./Scripts/build.sh      # Production (local)
./Scripts/build-and-sign.sh # Release (signed)
```

## Quick Deploy

**"dd"** → "Aye aye Captain!"
```bash
cd /Users/malpern/local-code/KeyPath && SKIP_NOTARIZE=1 ./build.sh
```
Deploys release build locally and restarts app.

## Test Commands

```bash
swift test
KEYPATH_MANUAL_TESTS=true ./run-tests.sh  # Force manual tests
KEYPATH_USE_SUDO=1 swift test             # Run tests with sudo (requires sudoers setup)
```

### Sudoers Configuration (Local Development Only)

For running tests that need admin privileges without osascript dialogs:

```bash
# Setup (one-time)
sudo ./Scripts/dev-setup-sudoers.sh

# Run tests with sudo instead of osascript
KEYPATH_USE_SUDO=1 swift test

# Remove before public release!
sudo ./Scripts/dev-remove-sudoers.sh
```

**How it works:**
- `KEYPATH_USE_SUDO=1` makes `LaunchDaemonInstaller` use `sudo -n` instead of osascript
- `TestEnvironment.useSudoForPrivilegedOps` controls the behavior
- Sudoers rules are scoped to KeyPath-specific paths only

**Files:**
- `Scripts/dev-setup-sudoers.sh` - Adds NOPASSWD rules to `/etc/sudoers.d/keypath-dev`
- `Scripts/dev-remove-sudoers.sh` - Removes the rules

## Code Quality

```bash
swiftformat Sources/ Tests/ --swiftversion 5.9
swiftlint --fix --quiet
```

## Future Enhancements

### Config Output: Physical Keyboard Layout ✅
**Status:** Implemented | **Location:** `ConfigurationService.KeyboardGridFormatter`

Generated kanata configs are formatted as physical keyboard rows for visual scanning:

```lisp
;; Actual output format (physical keyboard layout):
(defsrc
  esc  f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  del
  grv  1    2    3    4    5    6    7    8    9    0    min  eql  bspc
  tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
  caps a    s    d    f    g    h    j    k    l    ;    '    ret
  lsft z    x    c    v    b    n    m    ,    .    /    rsft
  lctl lalt lmet spc  rmet ralt rctl
)
```

**Implementation Details:**
- `KeyboardGridFormatter` (private enum in ConfigurationService.swift)
- `layoutRows: [[String]]` defines physical keyboard layout (lines 405-412)
- `renderGridLines()` groups entries into physical rows (lines 456-483)
- `padRow()` aligns columns for visual clarity (lines 485-491)
- Sorts keys by physical position before rendering
- Skips empty rows (only renders rows with mappings)
- Collection metadata appears as comments above each row group

**Benefits:**
- Easier visual scanning for advanced users
- Matches physical keyboard layout
- Column alignment improves readability
- Compatible with standard Kanata parsers
