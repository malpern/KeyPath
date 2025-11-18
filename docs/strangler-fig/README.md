# Strangler Fig Refactoring Documentation

This directory contains all documentation for the InstallerEngine façade refactoring using the [Strangler Fig Pattern](https://martinfowler.com/bliki/StranglerFigApplication.html).

## Overview

We're incrementally refactoring the installer code by building a new façade (`InstallerEngine`) around the existing code, then gradually migrating callers to use the façade. The old code remains until fully replaced.

## Documentation Structure

### Planning Documents (`planning/`)
- **`planning/facade-planning.md`** - Master plan with all phases and checkboxes
- **`planning/facade-planning-phase0-explained.md`** - Beginner-friendly explanation of Phase 0 steps

### Phase 0: Pre-Implementation Setup (`phase0/`) ✅ Complete
- **`phase0/PHASE0_SUMMARY.md`** - Summary of Phase 0 deliverables
- **`phase0/API_CONTRACT.md`** - Frozen API signatures (4 methods)
- **`phase0/TYPE_CONTRACTS.md`** - Type definitions (7 core types)
- **`phase0/CONTRACT_TEST_CHECKLIST.md`** - Test requirements
- **`phase0/BASELINE_BEHAVIOR.md`** - Current behavior documentation
- **`phase0/COLLABORATORS.md`** - Dependency list
- **`phase0/TEST_STRATEGY.md`** - Test approach
- **`phase0/OPERATIONAL_CONSIDERATIONS.md`** - Rollout strategy

### Future Phases
- Phase 1: Core Types & Façade Skeleton
- Phase 2: Implement `inspectSystem()`
- Phase 3: Implement `makePlan()`
- Phase 4: Implement `execute()`
- Phase 5: Implement `run()`
- Phase 6: Migrate Callers
- Phase 7: Refactor Internals
- Phase 8: Documentation & Cleanup

## Quick Start

1. **Read the master plan:** `planning/facade-planning.md`
2. **Understand Phase 0:** `phase0/PHASE0_SUMMARY.md`
3. **Review API contract:** `phase0/API_CONTRACT.md`
4. **Check type definitions:** `phase0/TYPE_CONTRACTS.md`

## Key Principles

- **Keep it boring and simple** - No over-engineering
- **YAGNI** - You Aren't Gonna Need It
- **Incremental** - Small steps, test frequently
- **Preserve behavior** - Don't break existing functionality
- **Strangler pattern** - New code wraps old, old code remains until replaced

## Status

**Current Phase:** Phase 0 ✅ Complete

**Next:** Phase 1 - Core Types & Façade Skeleton

## Related Documentation

- **Design Document:** `docs/InstallerEngine-Design.html` - High-level design
- **Architecture:** `docs/ARCHITECTURE.md` - System architecture (will be updated)

