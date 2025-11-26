# Completed Refactorings Archive

**Purpose:** Single reference for all major completed refactoring efforts.  
**Last Updated:** November 2025

---

## 1. Strangler Fig Façade Migration (Nov 2024 - Nov 2025) ✅

### Summary
Unified all installation/repair logic into `InstallerEngine` façade using the [Strangler Fig Pattern](https://martinfowler.com/bliki/StranglerFigApplication.html).

### What Was Done
- **Phase 0:** Pre-Implementation Setup - API contracts, type definitions
- **Phase 1:** Core Types & Façade Skeleton - `InstallerEngine`, `SystemContext`, `InstallPlan`
- **Phase 2:** Implement `inspectSystem()` - Real system detection via `SystemValidator`
- **Phase 3:** Implement `makePlan()` - Recipe-based planning with `ServiceRecipe`
- **Phase 4:** Implement `execute()` - Recipe execution with health checks
- **Phase 5:** Implement `run()` convenience wrapper
- **Phase 6:** Caller migration (CLI, wizard, settings)
- **Phase 7-9:** Internal cleanup and legacy removal

### Final API
```swift
let engine = InstallerEngine()

// Inspect system state
let context = await engine.inspectSystem()

// Create plan
let plan = await engine.makePlan(for: .install, context: context)

// Execute plan
let report = await engine.execute(plan: plan, using: broker)

// Or use convenience wrapper
let report = await engine.run(intent: .repair, using: broker)
```

### Key Types Created
- `InstallerEngine` - Main façade
- `SystemContext` - Immutable system state snapshot
- `InstallPlan` - Ordered list of recipes
- `ServiceRecipe` - Atomic installation operation
- `InstallerReport` - Execution results

### Superseded Components
- Direct `LaunchDaemonInstaller` calls → Use `InstallerEngine`
- `WizardAutoFixer` direct usage → Use `InstallerEngine.runSingleAction()`
- `SystemStatusChecker` → Use `InstallerEngine.inspectSystem()`

---

## 2. Privileged Helper Implementation (Oct-Nov 2025) ✅

### Summary
Implemented hybrid privileged helper approach supporting both development (direct sudo) and production (XPC helper) workflows.

### Architecture
```
DEBUG BUILDS → Direct sudo (AppleScript) → No certificate needed
RELEASE BUILDS → XPC Helper (SMJobBless) → Professional UX
```

### What Was Done
- **Phase 1:** Extracted all privileged operations to `PrivilegedOperationsCoordinator`
- **Phase 2A:** Created `KeyPathHelper` XPC service infrastructure
- **Phase 2B:** Migrated all callers to coordinator API
- **Phase 3:** Build scripts for helper embedding and signing
- **Phase 3.5:** Security hardening (audit-token validation, removed executeCommand)

### Key Components
- `PrivilegedOperationsCoordinator.swift` - Runtime mode detection, unified API
- `HelperManager.swift` - XPC connection management
- `KeyPathHelper/` - Root-privileged helper binary (17 whitelisted operations)

### Security Features
- Audit-token validation using `SecCodeCheckValidity`
- No arbitrary command execution (removed `executeCommand` API)
- On-demand activation (helper not always resident)
- Code signing requirements for both app and helper

---

## 3. UDP → TCP Migration (2024) ✅

### Summary
Migrated from UDP to TCP for Kanata communication, then simplified the client.

### What Changed
- Removed UDP session management, connection pooling, inflight tracking
- Simplified to basic TCP request/response pattern
- Reduced from ~800 lines to ~369 lines (52% reduction)

---

## 4. Error Hierarchy Consolidation (2025) ✅

### Summary
Unified 19 scattered error types into single `KeyPathError` hierarchy.

### What Changed
- Created `KeyPathError` with nested enums for logical grouping
- Migrated all 25+ throw sites to unified type
- Added `LocalizedError` conformance with recovery suggestions
- Added error classification (`isRecoverable`, `shouldDisplayToUser`)

### Superseded Types
`ConfigurationError`, `ConfigError`, `ProcessLifecycleError`, `PermissionError`, 
`OracleError`, `UDPError`, `CoordinatorError` → All now `KeyPathError.*`

---

## 5. MVVM Separation (2024) ✅

### Summary
Separated business logic from UI reactivity.

### What Changed
- `RuntimeCoordinator` is NOT `ObservableObject` (business logic only)
- `KanataViewModel` handles `@Published` properties for SwiftUI
- UI reads state via `getCurrentUIState()` snapshots

---

## Historical Documentation

The original detailed phase-by-phase documentation was preserved in:
- `strangler-fig/` folder (phases 0-6, planning docs)
- `HELPER.md` (detailed helper implementation plan)

These are retained for historical reference but the summaries above represent the current state.

---

## Lessons Learned

### What Worked Well
1. **Strangler Fig pattern** - Allowed incremental migration without breaking changes
2. **Recipe-based execution** - Atomic operations with health checks
3. **Unified error hierarchy** - Single place to understand all errors
4. **Hybrid helper approach** - Zero friction for contributors, professional UX for users

### What to Avoid
1. **God objects** - RuntimeCoordinator is still too large (~2,800 lines)
2. **Over-engineering** - UDP client was 5x more complex than needed
3. **Scattered responsibilities** - Configuration logic was in 4+ places

### Principles Established
1. **No file > 1,000 lines** - If bigger, split it
2. **Single Responsibility** - One file, one job
3. **Localhost IPC ≠ Network** - Don't engineer for distributed systems
4. **Clear Entry Points** - Document in CONTRIBUTING.md


