# ADR-019: Test Seams via TestEnvironment Checks

**Status:** Accepted
**Date:** November 2025

## Context

Production code has side effects that would disrupt test execution:
- Process spawning (`pgrep`)
- CGEvent taps
- Sound playback
- TCP connections
- Modal alerts
- Notification Center
- File watchers

Full dependency injection would require injecting many services for marginal benefit.

## Decision

Use `TestEnvironment.isRunningTests` checks (37 occurrences) to disable side effects during testing.

## What's Protected

| Side Effect | Why Disabled in Tests |
|-------------|----------------------|
| `pgrep` spawning | Deadlocks in parallel tests |
| CGEvent taps | No system access in CI |
| Sound playback | Annoying, slow |
| TCP connections | No Kanata in tests |
| Modal alerts | Block test execution |
| Notification Center | System integration |
| File watchers | Race conditions |

## Why Not Full DI?

Would require injecting: SoundManager, NotificationService, EventTapController, SafetyAlertPresenter, shell runners, TCP clients, etc. Massive refactoring for marginal benefit.

## Why This Is Safe

These checks guard **side effects**, not business logic. Core logic still executes and is tested.

## Escape Hatches

```bash
KEYPATH_FORCE_REAL_VALIDATION=1 swift test
```

## For New Code

Prefer injectable seams (like `VHIDDeviceManager.testPIDProvider`) over environment checks where practical. Use `TestEnvironment.isRunningTests` for UI/system side effects.
