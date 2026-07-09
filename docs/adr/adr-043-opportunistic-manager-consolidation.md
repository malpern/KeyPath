# ADR-043: Opportunistic Manager Consolidation

## Status

Accepted

## Date

2026-07-09

## Context

KeyPath's installer and runtime code evolved across several implementation
eras. Some responsibilities are now split across overlapping
Manager/Coordinator/Service types such as daemon registration, runtime
lifecycle, health checking, helper maintenance, privileged execution, and
system validation.

Phase 1 of installer reliability made the key behavior executable through
`probe -> snapshot -> classify -> plan -> execute -> verify`, but the older
object boundaries still exist around that flow. A broad "merge the managers"
refactor would create high churn during the stability window without directly
fixing a user-visible bug. At the same time, adding new forwarding layers or
parallel coordinators would preserve the 18-month pattern that made the repair
system hard to reason about.

## Decision

Consolidate overlapping installer/runtime managers opportunistically, not as a
standalone rewrite.

When a bug fix or feature naturally touches overlapping responsibilities across
Manager/Coordinator/Service types, prefer to move the touched responsibility
into the canonical owner and delete the now-redundant bridge or forwarding
method. Do this only when the local change already needs to cross that boundary
and the resulting ownership is clearer and testable.

Do not schedule broad manager-consolidation PRs whose primary goal is cleanup.
During the stability window, behavior-preserving consolidation is acceptable
only when it is attached to a concrete repair, reliability, testability, or
compile-boundary improvement.

## Guidance

- Keep `InstallerEngine` as the facade for install, repair, uninstall, and
  system inspection.
- Keep `SystemStateProvider` as the owner of live system evidence and raw probe
  access as those call sites migrate.
- Keep `ServiceLifecycleCoordinator` as the owner of Kanata start/stop/restart
  orchestration unless a later ADR replaces that boundary.
- When touching two overlapping types, ask whether one method can move to the
  owner that already owns the underlying evidence or side effect.
- Prefer deleting adapters, duplicated state reads, and pass-through methods
  over adding new coordination layers.
- Convert static test override seams to injected dependencies only when the
  touched code is already being changed for behavior or testability.

## Non-Goals

- No project-wide "merge all managers" refactor.
- No generic dependency/effects framework.
- No wizard UI rewrite as part of consolidation.
- No removal of lint ratchets before compiler/module boundaries enforce the
  same rule.

## Consequences

This keeps architectural pressure in the right direction without destabilizing
recent installer reliability work. The codebase should gradually lose old
era-layered abstractions as those areas are touched for real reasons, while
large, speculative cleanup remains out of scope.

The trade-off is that cleanup will be incremental and uneven. That is
intentional: local consolidation tied to a tested behavior change has a better
risk profile than a broad mechanical rewrite.
