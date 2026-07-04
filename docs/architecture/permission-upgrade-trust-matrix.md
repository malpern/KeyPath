# Permission + Upgrade Trust Matrix

This document defines the runtime decision model used to avoid unnecessary permission churn
and wizard loops across normal app upgrades.

## Goals

- Keep Accessibility and Input Monitoring grants stable across normal in-place upgrades.
- Avoid byte-for-byte kanata comparisons that cause false positive reinstalls.
- Escalate only when trust or permission state is genuinely risky.

## Decision Outcomes

1. `silentContinue`
- No repair action.
- Used when system state is already healthy and trusted.

2. `softRepair`
- Run `InstallerEngine().run(intent: .repair, using: broker)`.
- Used for recoverable runtime/component drift (helper/services/components not ready).

3. `hardRepair`
- Do not attempt automatic repair; require guided user action (wizard/settings).
- Used for blocking permission states or trust failures that cannot be auto-granted.

## Trust Policy

Kanata trust checks must prefer signer identity over raw bytes.

Required baseline:
- Code signature verifies as Developer ID.
- Team identifier matches KeyPath’s bundled trusted identity.
- Signing identifier matches bundled identity when available.

Unknown trust state (identity metadata unreadable):
- Log warning with reason code.
- Do not force reinstall by default to avoid false triggers.

## Upgrade Behavior

Pre-update:
- Run soft repair only when services/helper are currently active and need a controlled stop.
- Otherwise continue silently.

Post-update:
- If blocking permissions are detected (`PermissionOracle`), mark hard repair.
- If helper/components/services are unhealthy, run soft repair.
- If everything is healthy, continue silently.

## Reason Code Logging

All escalations should log a reason code for diagnosability, e.g.:
- `reason_code=team_mismatch`
- `reason_code=identifier_mismatch`
- `reason_code=components_not_ready`
- `reason_code=kanata_permissions_blocking`
