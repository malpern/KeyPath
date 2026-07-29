# Startup reload during runtime replacement

## Problem

Rule collection bootstrap can persist the generated configuration and begin a
TCP reload while app startup is replacing a stale Kanata runtime. The old
runtime may acknowledge the reload, then close the connection when privileged
stale-process recovery terminates it. KeyPath previously treated that expected
transport loss as a settled reload failure, producing an error sound, a
`Reload delayed: Connection failed: Connection closed` toast, and a transient
`No TCP` badge while the replacement runtime became ready.

## Resolution

`ServiceLifecycleCoordinator` now exposes its intentional start/stop transition
state to `ConfigReloadCoordinator`. A network failure inside that exact window
is classified as pending, does not post the user-facing failure notification,
and schedules one bounded retry after the transition ends and runtime health is
restored. Validation failures and network failures outside an intentional
transition remain visible failures.

The overlay uses the canonical runtime startup grace period and whether it has
previously observed a live connection to show `Starting…` or `Restarting…`.
After the grace period, a settled disconnection still shows `No TCP`.

## Invariant

Expected transport churn caused by an intentional runtime replacement is a
pending lifecycle state, not a configuration failure. User-facing TCP errors
must represent failures that persist outside the startup/restart grace window.
