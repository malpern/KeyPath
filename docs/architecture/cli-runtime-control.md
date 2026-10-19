# CLI runtime control

`keypath status|start|stop|restart` (and the same verbs under `keypath service`)
drive the driverless runtime from scripts and agents. Added 2026-10-19.

## Why the CLI asks the app

The driverless runtime is a session worker launched and supervised by the KeyPath
app. A separate CLI process cannot own that worker, and inspecting it from outside
means re-deriving the app's checks (owned report, nonce, listener ownership). So the
CLI asks the app, which already knows: `ServiceLifecycleCoordinator.currentRuntimeStatus()`.
The legacy daemon commands these replace were unregistered for that reason
(`docs/bugs/driverless-cli-command-surface.md`).

## Channel

- `RuntimeControl` (KeyPathCore): request/response types and the client.
- `RuntimeControlServer` (KeyPathAppKit): a Unix-domain stream socket at
  `~/Library/Application Support/KeyPath/control/runtime.sock`. The directory is
  0700 and checked to be a real directory owned by this user; the socket is created
  under umask 0177; every connection is refused unless `getpeereid` returns this
  process's uid. One JSON request line in, one JSON response line out, 64 KB cap,
  5 s read/write timeouts on the server side.
- Started from `CompositionRoot` in the normal app only. Session workers bypass
  `CompositionRoot`; one-shot probes are excluded explicitly.
- A socket file left by a crash is replaced; one a live instance answers on is left
  alone (the second instance logs and serves nothing).
- `RuntimeControlHandler` maps requests onto `RuntimeCoordinator.start/stop/restartKanata`,
  so CLI requests are serialized with UI, wake recovery and update operations, then
  reports `currentRuntimeStatusInternal()` after the operation.

## Contract

| Exit | Meaning |
|------|---------|
| 0 | done / running |
| 1 | not running, or the runtime refused or failed (`failure`, `lastError`) |
| 6 | the app is not running or did not answer (`--timeout`) |

`start` and `restart` launch the app (`open -g`) when it is not running and wait for
the socket; `stop` succeeds when the app is not running. `keypath://runtime/{start,stop,restart}`
runs the same handler with no result, for Shortcuts, Raycast and Hammerspoon.

## Doctor, setup and uninstall

- `doctor` runs `InstallerEngine().inspectSystem()` inside the app and maps
  `SystemFacade.issues(from:)` to `RuntimeControl.Issue`, so the CLI sees the same
  issues as `system inspect` but from the process that holds the permissions.
  `ready` = `SystemFacade.isOperational` and the runtime is running.
- `repair` runs the About window's repair (`InstallerEngine().run(intent: .repair,
  using: PrivilegeBroker())`), starts the runtime if it is not running, then answers
  with a doctor report. `keypath setup` (alias `repair`) loops: for each issue with
  `needsUser`, open its `settingsURL` once, poll `doctor` every 2 s, and repair again
  once nothing needs the user, until ready or `--wait` passes (exit 7).
- `uninstall` requires `confirmed: true` in the request (the CLI sends it only with
  `--yes`) and calls `RuntimeCoordinator.uninstall(deleteConfig: true)`, the same entry
  point as the Settings Uninstall dialog. It records that cleanup finished, without
  which `applicationShouldTerminate` refuses to quit. The control socket is withdrawn
  first (the backup cannot copy a socket) and restored if the uninstall fails. On
  success the app answers, then quits a second later. `--reset-permissions` runs
  `tccutil reset` for Accessibility, ListenEvent and PostEvent on `com.keypath.KeyPath`
  from the CLI *before* the uninstall: tccutil resolves the bundle id, which fails once
  the app is in the Trash.
- There is no separate install: the CLI ships inside the app, so first run is `setup`.

`Scripts/verify-installed-app.sh` remains the release-grade check because it verifies
process ownership and the TCP listener independently of the app's own report.
