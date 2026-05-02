# Service Layer Consolidation Plan

## The Problem

KeyPath has 69 coordinator/manager/service classes totaling 22,873 lines. Many follow a pattern where Coordinator A delegates to Manager B which delegates to Service C — three classes for one operation. This creates:

- **Navigation overhead**: understanding "what happens when I click Start" requires tracing through 5 files
- **Naming confusion**: Manager vs Coordinator vs Service has no consistent meaning
- **Boilerplate wrapping**: some coordinators add nothing beyond "call the manager, then fire a callback"

This grew organically — each class was added for a reason (testability, separation of concerns, safety checks) but the cumulative effect is excessive indirection.

## What NOT to Do

- Don't merge classes across module boundaries (AppKit vs InstallationWizard vs Core)
- Don't merge classes that are genuinely used by multiple independent callers
- Don't merge classes that serve as test seams (protocols with mock conformers)
- Don't do this all at once — each merge is one PR, one chain at a time

## The Seven Delegation Chains

### 1. Rule Collections: Coordinator → Manager (349 lines)

**Verdict: MERGE — highest value, lowest risk**

`RuleCollectionsCoordinator` (242L) is pure delegation + side-effect injection. Every method calls `RuleCollectionsManager` then fires a callback. The manager (107L) holds the actual state.

Merge the coordinator's logic into the manager. The "apply mappings after change" and "notify observers" side-effects become part of the manager's mutation methods.

**Why it's safe:** Same module, same actor, no external conformers. The coordinator exists because it was extracted from RuntimeCoordinator, not because it serves an independent purpose.

**Lines saved:** ~200 (coordinator becomes unnecessary)

---

### 2. Config Save: SaveCoordinator + ConfigBackupManager (649 lines combined)

**Verdict: MERGE — medium value**

`SaveCoordinator` (393L) orchestrates save + backup + rollback. `ConfigBackupManager` (256L) manages timestamped backup files. These always work together — no caller uses ConfigBackupManager independently.

Merge backup logic into SaveCoordinator. `ConfigurationService` (973L) stays separate — it's in a different module and used by multiple callers.

**Why it's safe:** ConfigBackupManager has exactly one consumer (SaveCoordinator). The backup retention logic (max 5 files, timestamped names) is a detail of saving, not a separate concern.

**Lines saved:** ~100 (remove delegation glue, shared imports)

---

### 3. Config Reload: Coordinator + SafetyMonitor (456 lines combined)

**Verdict: MERGE — medium value**

`ConfigReloadCoordinator` (216L) orchestrates reload. `ReloadSafetyMonitor` (240L) tracks reload history and crash loops. Every reload goes through both — the safety monitor is never used independently.

Merge safety tracking into the coordinator. The "is it safe to reload?" check becomes a private method, not a separate class.

`EngineClient` protocol (39L) and `TCPEngineClient` (34L) stay separate — the protocol is a test seam.

**Lines saved:** ~80

---

### 4. Service Lifecycle: KanataDaemonService + KanataDaemonManager (1,130 lines combined)

**Verdict: MERGE — high value, medium risk**

`KanataDaemonService` (323L) and `KanataDaemonManager` (807L) both wrap SMAppService with overlapping responsibilities. KanataDaemonService does registration/status polling. KanataDaemonManager does state determination, migration logic, plist management.

These should be one class. The current split creates confusion about which one to call for daemon operations.

`ServiceLifecycleCoordinator` (280L) stays separate — it's the public API for start/stop that UI code calls.

**Why it's riskier:** KanataDaemonManager is 807 lines with complex state machine logic. Merging requires careful testing of all daemon state transitions.

**Lines saved:** ~150

---

### 5. Health Check: Checker + Monitor (1,351 lines combined)

**Verdict: CONSIDER — high value, high risk**

`ServiceHealthChecker` (826L) takes snapshots. `ServiceHealthMonitor` (525L) tracks health over time. Both check the same services, use the same launchctl calls, and share the same PID cache.

Could merge into one class with both "check now" and "monitor continuously" capabilities. But ServiceHealthChecker lives in the InstallationWizard module while ServiceHealthMonitor is in AppKit — **module boundary blocks simple merge.**

`LaunchDaemonPIDCache` (234L) stays separate — it's a shared singleton used by multiple callers.

**Lines saved if feasible:** ~200

**Recommendation:** Defer unless you're already refactoring the module boundary.

---

### 6. Installation: Coordinator + Engine (922 lines combined)

**Verdict: SKIP**

`InstallationCoordinator` (176L) and `InstallerEngine` (746L) are in different modules. The coordinator is app-level; the engine is wizard-level. The separation is justified by the module boundary.

---

### 7. Recovery: RecoveryCoordinator (262 lines)

**Verdict: SKIP — already self-contained**

No delegation chain. Uses callbacks injected by RuntimeCoordinator. Clean design.

---

## Priority Order

| Priority | Chain | Lines Saved | Risk | Effort |
|----------|-------|-------------|------|--------|
| 1 | Rule Collections (merge Coordinator into Manager) | ~200 | Low | 1 hour |
| 2 | Config Save (merge BackupManager into SaveCoordinator) | ~100 | Low | 1 hour |
| 3 | Config Reload (merge SafetyMonitor into Coordinator) | ~80 | Low | 1 hour |
| 4 | Daemon Service (merge Service into Manager) | ~150 | Medium | 2-3 hours |
| 5 | Health Check (merge Checker + Monitor) | ~200 | High (module boundary) | Defer |
| 6-7 | Installation, Recovery | — | — | Skip |

## What This Achieves

If priorities 1-4 are completed:

| Metric | Before | After |
|--------|--------|-------|
| Coordinator/Manager/Service classes | 69 | 65 |
| Total lines in these classes | 22,873 | ~22,340 |
| Average hops per operation | 3-4 | 2-3 |
| Classes with "what does this add?" answer of "nothing" | ~4 | 0 |

The line savings are modest (~530 lines). The real value is reducing the number of classes a developer navigates to understand an operation. Each merge removes one "why does this class exist?" question.

## When to Do This

Not urgent. These chains work correctly — the over-engineering adds cognitive cost but doesn't cause bugs. Good candidates for:
- Pairing with a junior developer learning the codebase (each merge is self-contained and educational)
- Slow weeks between feature work
- Pre-requisite cleanup before adding new functionality to the affected chain
