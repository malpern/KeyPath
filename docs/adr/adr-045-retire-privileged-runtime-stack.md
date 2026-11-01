# ADR-045: Retire the Privileged Runtime Stack

**Status:** Accepted
**Date:** 2026-10-31

## Context

Kanata now runs in an unprivileged user-session runtime.
`KanataRuntimeBackend.selected` always returns `.session`, and the release build
does not ship the privileged helper, the launcher, or a LaunchDaemon plist.
`verify-release-signing-contract.sh` fails if they return.

The stack that session runtime replaced is still in the repository: the helper
and launcher targets, `HelperManager`, `PrivilegedOperationsRouter`,
`KanataDaemonManager`, `KanataDaemonService`, `HelperMaintenance`,
`ServiceBootstrapper`, `VHIDDeviceManager`, `PlistGenerator`, the Karabiner
wizard page, and their tests. Most of it cannot run in a current build, but it
still costs CI time and misleads readers. Code and docs called the session
runtime an experiment, so nothing recorded whether the old stack would return.

The latest public release, 1.0.1, predates the session runtime and does ship the
helper and daemon. Its users have privileged components installed.

## Decision

The session runtime is the product. The privileged stack is retired and will not
return as a supported backend or a fallback. If a driver option is ever proposed,
it starts from a new ADR, using git history as reference.

Remove the stack in stages. Removal is the concrete justification ADR-043
requires: it is deletion of unreachable code, not a manager merge.

## Upgrade Constraint

Do not delete code that migration needs until the first public session-runtime
release has a tested path for Macs coming from 1.0.1.

Today the session runtime refuses to start beside a running legacy daemon and
tells the user to stop it, but the app offers no way to do that:
`InstallerEngine` refuses privileged recipes and `SessionUninstallCoordinator`
does no privileged cleanup. That path must cover at least the kanata daemon, the
helper registration, and telling the user what remains of the VirtualHID driver.
It must be tested on a clean VM that starts from 1.0.1.

Keep legacy detection after the rest is removed for as long as 1.0.1 installs may
upgrade directly.

## Consequences

- `AGENTS.md` and architecture docs describe the session runtime. ADRs written
  for the daemon remain as history and carry a note saying so.
- "Experimental" and "driverless build" wording in code and error strings stays
  until the stage that touches it, then goes.
- ADR-040's `EPERM` lesson still applies to any legacy-daemon detection.
- ADR-013's accepted risk needs review, because the TCP endpoint now fronts a
  process holding Accessibility and Input Monitoring.
- Removal order: unreachable wizard pages and actions, then routers and managers,
  then the helper and launcher targets and their scripts. Each stage keeps CI
  green and removes its tests with the code.
