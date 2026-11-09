# ADR-047: Pre-Release Cleanup Before the First Session-Runtime Release

**Status:** Accepted
**Date:** 2026-11-08
**Amends:** [ADR-043](adr-043-opportunistic-manager-consolidation.md),
[ADR-045](adr-045-retire-privileged-runtime-stack.md)

## Context

KeyPath has no real users yet, public releases are paused, and the product
targets only the latest macOS (27). The codebase still carries:

- the retired privileged stack (helper, daemon, VirtualHID, launchd
  registration), about 99 source files that mention it;
- the 1.0.1 upgrade path ADR-045 required before removing that stack;
- branches for macOS 15 and 26, because the package minimum is macOS 15;
- two permission sets, KeyPath's and "Kanata's", which in the session runtime
  describe the same app, plus an Input Monitoring concept nothing now needs
  (see `docs/bugs/2026-11-08-input-monitoring-not-required-on-macos27.md`);
- about 47 places that switch between the session and privileged backends.

ADR-043 forbids cleanup PRs whose main goal is cleanup, and ADR-045 keeps
migration code until a tested 1.0.1 upgrade path exists. Both rules protect
users who do not exist yet. Removing this code costs least now: nothing ships
between steps, and nothing needs backward compatibility.

## Decision

Until the first session-runtime public release, deliberate cleanup PRs are
allowed. Each removes code made unreachable or unnecessary by the session
runtime or by the macOS 27 minimum.

1. Raise the minimum macOS to 27 and delete branches for earlier versions.
2. Remove the retired privileged stack, including the 1.0.1 upgrade path and
   legacy detection. ADR-045's Upgrade Constraint is withdrawn: KeyPath will not
   support upgrading from 1.0.1. A Mac with 1.0.1 components must remove them
   by hand (see git history for `LegacyPrivilegedRuntimeCleanup` and its label
   and path lists).
3. Merge KeyPath's and the runtime's permission sets into one, and remove the
   Input Monitoring concept. (Done: `PermissionOracle.Snapshot` holds KeyPath's
   Accessibility grant and the runtime's key-access report; see the follow-up in
   `docs/bugs/2026-11-08-input-monitoring-not-required-on-macos27.md`.)
4. Collapse manager and coordinator layers that existed only to switch between
   backends. (Done: `KanataRuntimeBackend` is gone and the session runtime is
   the only path; the VirtualHID/Karabiner-driver fields left `ComponentStatus`,
   `HealthStatus` and the CLI status/inspect JSON; the `KeyPathDaemonLifecycle`
   target was deleted, its external-Kanata detection moving to
   `KanataProcessDetector` in KeyPathAppKit; the launcher path, runtime
   identity/freshness, and orphaned `kanata.entitlements` were removed; the
   managed lab lane supports macOS 27 only.)

Each step is its own PR, is merged and deployed to the mini and the Air before
the next starts, keeps CI green, and removes its tests with its code.

## Consequences

- ADR-043's "no cleanup PRs" rule is suspended for these four steps and returns
  after the first session-runtime release.
- ADR-045's decision stands; its Upgrade Constraint and the #1353 upgrade path
  are superseded. #1353 should be closed as won't-fix.
- Anyone who installed 1.0.1 and later installs a session-runtime build gets no
  automatic cleanup. That is accepted because there are no such users.
