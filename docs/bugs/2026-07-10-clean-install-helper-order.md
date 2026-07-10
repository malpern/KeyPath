# Clean install must establish the helper before privileged recipes

## Symptom

After a verified uninstall, `keypath-cli system install` attempted to restart the
Karabiner daemon before installing the privileged helper. Both the restart and
runtime-recovery XPC calls timed out after 30 seconds, so execution stopped and
never reached the helper-install recipe.

## Root cause

`InstallerDecisionPipeline` emitted service and component actions before
`.installPrivilegedHelper`. Recipe execution correctly follows the declared plan
and stops on its first failure, so a missing XPC endpoint made the later helper
recipe unreachable.

## Invariant

For install and repair intents, an absent or unhealthy helper must produce the
first recipe. Every later component, activation, conflict-resolution, and service
recipe may route through `PrivilegeBroker` and therefore depends on that helper.

`InstallerEnginePlanTests` pins this ordering for both clean install and repair.
