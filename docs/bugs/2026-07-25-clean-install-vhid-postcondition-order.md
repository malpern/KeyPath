# VHID activation must not require later runtime services

## Symptom

On a fresh managed macOS 15 clone, the installer activated the bundled DriverKit
virtual HID extension successfully, then stopped before installing KeyPath's
runtime service plists. A second supported installer pass succeeded.

## Root cause

`activateVirtualHIDManager()` enforced the aggregate VHID-services
postcondition. That postcondition requires the VHID daemon and manager services
to be installed, loaded, healthy, and correctly configured. The clean-install
plan intentionally installs those runtime services in a later recipe, so the
activation recipe was checking state it did not own and the plan had not yet
created.

## Invariant

The activation operation verifies the DriverKit extension outcome it owns. The
later runtime-service installation and VHID repair operations continue to
enforce the full VHID-services postcondition before reporting success.

`PrivilegedOperationsRouterTests` pins both sides of the boundary: activation
does not require absent future services, and activation still fails when the
driver postcondition itself is unsatisfied. `PostconditionLintTests` pins the
operation-to-postcondition classification.
