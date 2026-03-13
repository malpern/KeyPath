# ADR-035: Bundle ID TCC Detection with Path Fallback

**Status:** Accepted
**Date:** 2026-03-12

## Context

`PermissionOracle` previously queried the TCC database using `client_type=1` (path-based) to check whether kanata had been granted Accessibility and Input Monitoring permissions. With [ADR-034](adr-034-kanata-engine-app-bundle-tcc-identity.md), kanata is now wrapped in Kanata Engine.app, and new TCC grants use `client_type=0` (bundle ID: `com.keypath.kanata-engine`).

Two problems arise:

1. **Existing users** have path-based TCC entries from before the migration. These grants still work at the OS level but won't be found by a bundle-ID-only query.
2. **Tahoe 26.1+** makes path-based entries invisible in System Settings, so we want to nudge users toward the bundle ID grant over time.

## Decision

`PermissionOracle` queries TCC in a **two-step priority order**:

1. **Bundle ID query** (`client_type=0`, client = `com.keypath.kanata-engine`) — preferred
2. **Path fallback** (`client_type=1`, client = bundled binary path) — migration only

If either query returns `allowed=1`, the permission is considered granted. The path fallback will be removed after one release cycle.

### Detection Priority

```
┌─────────────────────────────────┐
│ Query client_type=0             │
│ (bundle ID: com.keypath.kanata-│
│  engine)                        │
│         │                       │
│    found? ──yes──► GRANTED      │
│         │                       │
│        no                       │
│         ▼                       │
│ Query client_type=1             │
│ (path: .../Kanata Engine.app/    │
│  Contents/MacOS/kanata)         │
│         │                       │
│    found? ──yes──► GRANTED      │
│         │        (+ flag for    │
│        no         re-grant)     │
│         ▼                       │
│     NOT GRANTED                 │
└─────────────────────────────────┘
```

When a permission is detected via the path fallback only, the wizard flags this for the user and can guide them to re-grant to the `.app` bundle so the entry becomes visible in System Settings.

### Why Not Path Only

- On Tahoe 26.1+, path-based entries are invisible in System Settings — users cannot verify or revoke them.
- Bundle ID is the standard macOS identity for applications. It survives app moves and renames.
- Path-based entries are fragile if the user relocates `KeyPath.app`.

### Relationship to ADR-006 (Apple API Priority)

The fundamental rule from [ADR-006](adr-006-apple-api-priority.md) is unchanged: `IOHIDCheckAccess()` is authoritative for the **calling process** (KeyPath.app itself).

TCC database reading (per [ADR-016](adr-016-tcc-database-reading.md)) remains necessary for checking **kanata's** grants because `IOHIDCheckAccess()` only reports on the calling process, not on other binaries. What changes here is **what we query for** in TCC — bundle ID instead of path — not **when or whether** we query.

## Consequences

### Positive
- Existing users with path-based grants are not broken during migration
- New grants use bundle ID, which is visible and manageable in System Settings
- Clean removal path: drop the path fallback after one release

### Negative
- Two TCC queries instead of one during the migration window
- Wizard needs a "re-grant" nudge flow for legacy path-based entries

## Related
- [ADR-034: Kanata Engine.app Bundle for TCC Identity](adr-034-kanata-engine-app-bundle-tcc-identity.md) — the bundle wrapper this detects
- [ADR-006: Apple API Priority](adr-006-apple-api-priority.md) — IOHIDCheckAccess remains authoritative for calling process
- [ADR-016: TCC Database Reading](adr-016-tcc-database-reading.md) — mechanism for reading TCC database
- [ADR-033: Bundled Binary as Canonical Path](adr-033-bundled-binary-canonical-path.md) — previous path-based approach
