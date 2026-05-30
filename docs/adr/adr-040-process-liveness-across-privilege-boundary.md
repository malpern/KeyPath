# ADR-040: Process Liveness and Signaling Across the Privilege Boundary

**Status:** Accepted
**Date:** 2026-05-30
**Context:** KeyPath.app runs **unprivileged**, while kanata runs as a **root LaunchDaemon** (Mode A: `kanata-launcher` registers via `SMAppService`, then exec's the bundled kanata as root). Any app-side code that *inspects* or *signals* the kanata process is crossing a privilege boundary, and POSIX behaves differently across that boundary in ways that are easy to get wrong — and easy to ship green, because unit tests that mock the syscall never exercise the real behavior.

This ADR was written after PR #645 (#625 part-1, "wait-for-exit before start") shipped — and was caught in review with — a liveness check that was wrong for exactly this boundary.

## The trap

`kill(pid, 0)` is the idiomatic "does this process exist?" probe. Its return value depends on the caller's privileges relative to the target:

| Result | `errno` | Meaning |
|--------|---------|---------|
| `0`    | —       | Process exists **and** you may signal it |
| `-1`   | `ESRCH` | No such process — it is **gone** |
| `-1`   | `EPERM` | Process **exists**, but you lack permission to signal it |

From the unprivileged app, probing the **root** kanata returns `EPERM` while it is alive. The naive check `kill(pid, 0) == 0` therefore reports the live root daemon as **dead** — the opposite of the truth.

## Decision

**1. Liveness across the boundary means `kill(pid, 0) == 0 || errno == EPERM`.** Only `ESRCH` means gone. Treating `EPERM` as dead is a bug; encode the alive-on-EPERM rule wherever the app probes a root-owned process.

**2. The app cannot terminate the root daemon — only launchd can.** App-side `kill(pid, SIGTERM/SIGKILL)` against root kanata returns `EPERM` and does nothing. The authoritative stop is `SMAppService.unregister()` (which tells launchd to tear the process down); app-side signals are best-effort and only effective against genuinely app-owned / non-root orphans. Code that "kills and waits" is, for the root daemon, really **waiting for launchd to finish** a teardown the app already requested — design and comment it as such, and always bound the wait + proceed rather than assuming the kill succeeded.

**3. A primitive that is mocked in tests must still be grounded against reality at least once.** The EPERM bug survived 21 green tests because the liveness check was injected via a test seam (`testLivenessProbe`) and the real `kill(pid,0)` branch was never executed. Test seams are for deterministic *control flow*; the underlying OS primitive needs its own grounding — a direct test against a known-alive pid (`getpid()`) and a known-dead pid, and/or manual verification against the running root daemon. See [[lifecycle-hotpath-real-verification]].

## Consequences

- Any future process-inspection helper (liveness polls, orphan detection, restart races) must apply the EPERM rule and must not assume app-side signals reach the daemon.
- Reviews of lifecycle / process code must include a **runtime-reality** lens: "what does this syscall actually return in the real root/unprivileged topology?" — not just static diff analysis.
- This is the signaling-side companion to the permissions rule in [ADR-001](adr-001-oracle-pattern.md) / [ADR-006](adr-006-apple-api-priority.md) ("never check permissions from root"): the privilege boundary changes the meaning of OS calls in both directions.

## Reference implementation

`ServiceLifecycleCoordinator.isProcessAlive(_:)` and `waitForKanataExitBeforeStart()` (#625 part-1).
