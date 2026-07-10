# Installer transaction gate bypasses

## Problem

The installer transaction gate serialized the primary `run`, `execute`,
`runSingleAction`, and `uninstall` entry points, but two production paths could
still mutate installer-owned state outside that boundary:

- the hidden instant-uninstall menu command constructed `UninstallCoordinator`
  directly; and
- background conflict/orphan services called public privileged broker routes
  that did not acquire the installer transaction gate.

That left uninstall, Karabiner conflict repair, and orphan cleanup able to
overlap another install or repair transaction.

## Resolution

`InstallerEngine` now owns one reentrant transaction wrapper. Every public
mutating entry point uses it, including the direct privileged routes. Nested
operations in an already-owned installer task reuse the transaction instead of
deadlocking on a second acquire. The instant-uninstall shortcut now calls
`InstallerEngine.uninstall` and consumes its structured report.

## Regression protection

- A behavioral test starts two public privileged routes and proves the second
  cannot reach its broker while the first owns the transaction.
- Source ratchets require every public privileged route to use the shared
  wrapper and prevent the menu shortcut from constructing
  `UninstallCoordinator` directly.
- `UninstallCoordinator` is prohibited from starting a new installer run while
  it is executing inside the engine-owned uninstall transaction.

## Invariant

All production installer mutations enter through `InstallerEngine` and share
one transaction boundary. Registration, helper, driver, daemon, and uninstall
mutations must not add a separate public bypass.
