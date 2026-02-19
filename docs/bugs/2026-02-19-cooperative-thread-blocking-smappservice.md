# Cooperative Thread Blocking: SMAppService.status

**Date:** 2026-02-19
**Severity:** Latent reliability risk (contributes to watchdog timeouts)
**Status:** Investigated, partial fix in place

## Problem

`SMAppService.status` is a synchronous property that does IPC with the ServiceManagement daemon. When called from `nonisolated async` functions or async contexts, it blocks a cooperative thread. Swift's cooperative thread pool is limited (typically equal to CPU core count), so blocking one thread reduces capacity for all other async work.

This is a contributing factor to the 47-second helper health stall documented in `2026-02-19-false-kanata-service-stopped-alert.md`.

## Existing Mitigation

`KanataService.evaluateStatus()` already uses the correct pattern — wrapping `SMAppService.status` in `Task.detached` to move the blocking IPC off the cooperative pool:

```swift
let smStatusTask = Task.detached(priority: .utility) {
    Self.fetchSMStatus()
}
let smStatus = await smStatusTask.value
```

This runs every 2 seconds and works correctly.

## Findings: High-Priority Call Sites

These are on hot paths or have multiple callers:

| Call Site | File | Context | Frequency | Notes |
|-----------|------|---------|-----------|-------|
| `isHelperInstalled()` | HelperManager+Status.swift:24 | `nonisolated async` | 7+ callers | Blocks cooperative thread |
| `getHelperHealth()` | HelperManager+Status.swift:211 | actor async | startup + periodic | Calls .status directly, then again via isHelperInstalled |
| `WizardHelperPage.checkApprovalStatus()` | WizardHelperPage.swift:525 | async, Timer poll | every 2s while visible | Also bypasses smServiceFactory test seam |
| `helperNeedsLoginItemsApproval()` | HelperManager+Status.swift:13 | sync, called from async | wizard navigation | Blocks caller's thread |
| `refreshManagementState()` | KanataDaemonManager.swift:115 | `nonisolated async` | config hot reload | Reactive |

## Findings: Low-Priority Call Sites (one-time operations)

These are installation, migration, or diagnostic paths — they block briefly but only run once:

- `KanataDaemonManager.registerDaemon()` — up to 5 .status calls during registration (blocks MainActor)
- `HelperManager+Installation.installHelper()` — up to 6 .status calls
- `UninstallCoordinator.unregisterSMAppServiceDaemons()` — single call
- `HelperMaintenance.unregisterHelperIfPresent()` — 3 calls
- `BlessDiagnostics.run()` — diagnostic only

## Test Seam Bypasses

Three call sites construct `SMAppService.daemon()` directly instead of using `smServiceFactory`, making them untestable with mock services:

- `WizardHelperPage.checkLoginItemsApprovalNeeded()` (line 504)
- `WizardHelperPage.checkApprovalStatus()` (line 525)
- `HelperMaintenance.unregisterHelperIfPresent()` (line 164)

## Recommended Fix (when prioritized)

Apply the existing `Task.detached` pattern to the high-priority call sites. The lowest-effort approach: add a shared utility to `HelperManager`:

```swift
nonisolated static func fetchSMStatusDetached() async -> SMAppService.Status {
    await Task.detached(priority: .utility) {
        smServiceFactory(helperPlistName).status
    }.value
}
```

Then replace `svc.status` with `await Self.fetchSMStatusDetached()` in the 5 high-priority call sites. Low-priority one-time operations can stay as-is — the blocking is brief and infrequent.

## Why Not Fix Now

The immediate false-alert bug is fixed (wrong watchdog identifier + redundant calls). The cooperative thread blocking is a latent issue that makes stalls *possible* under adverse conditions, but the reduced call count (from 5 to 3 per `getHelperHealth()`) significantly lowers the risk. The right time to fix this is when we see another stall in logs, or as part of a broader Swift concurrency cleanup.
