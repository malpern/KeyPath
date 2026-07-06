# ADR-041: Installer Identity Stability Contract

## Status

Accepted

## Date

2026-07-06

## Context

Workstream 4 of the installer reliability plan prevents repair demand at the
source. For KeyPath's macOS stack, accidental identity drift is not cosmetic:

- TCC grants depend on the Kanata Engine bundle identity.
- SMAppService and launchd cache launch constraints and associated bundle
  identity for privileged jobs.
- The LaunchDaemon shell and helper designated requirements can survive updates
  in ways that make unregister/register appear successful while launchd still
  evaluates stale constraints.

ADR-032, ADR-033, and ADR-034 established the stable Kanata runtime identity.
This ADR pins the concrete release contract for the signed artifacts and source
plists that implement that identity.

## Decision

Treat the following values as release-gated compatibility contracts. Changing
any value requires a migration plan and explicit review of TCC, SMAppService,
and launchd LWCR blast radius.

| Component | Canonical path | Stable identity | Designated requirement |
|-----------|----------------|-----------------|------------------------|
| Kanata Engine | `/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata` | bundle ID and signing identifier `com.keypath.kanata-engine` | `identifier "com.keypath.kanata-engine" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99` |
| Privileged helper | `/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper` | bundle ID, launchd label, Mach service, and signing identifier `com.keypath.helper` | `identifier "com.keypath.helper" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99` |
| Kanata daemon shell | `/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher` | LaunchDaemon label `com.keypath.kanata`, `BundleProgram` `Contents/Library/KeyPath/kanata-launcher`, associated bundle ID `com.keypath.KeyPath`, signing identifier `kanata-launcher` | `identifier "kanata-launcher" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99` |

The daemon plist is not itself code signed. The release contract verifies the
plist values and the signed daemon shell executable; the outer app signature
seals the embedded plist as part of the bundle.

The helper constant change in this decision is intentionally behavioral.
`KeyPathConstants.Bundle.helperID` previously used
`com.keypath.KeyPath.Helper`, while the helper plist, Mach service, signed
binary, `HelperManager`, and installer diagnostics already used
`com.keypath.helper`. The only Swift call sites for that constant are the
`installPrivilegedHelper` and `reinstallPrivilegedHelper` installer recipes, so
the change aligns those recipes with the shipped helper service ID.
The repair implementation itself delegates to `HelperMaintenance`, which already
unregisters, bootouts, and removes `com.keypath.helper` artifacts using
`HelperManager.helperPlistName` / `HelperManager.helperBundleIdentifier`; the
recipe `serviceID` is recipe metadata and logging context, not a separate
old-label cleanup implementation. Current runtime source contains no
`com.keypath.KeyPath.Helper` literal outside this ADR and its ratchet test.

## Enforcement

- `Tests/KeyPathTests/Lint/IdentityStabilityContractTests.swift` is the CI
  ratchet for source metadata, canonical paths, release-gate wiring, and this
  ADR's pinned values.
- `Scripts/verify-identity-contract.sh --source` runs from
  `Scripts/release-doctor.sh`.
- `Scripts/verify-identity-contract.sh --app "$APP_BUNDLE"` runs from
  `Scripts/build-and-sign.sh` after signing and before notarization.

If the designated-requirement check fails while signing identifier, authority,
and team identifier checks still pass, first compare the raw
`codesign -d -r- --verbose=4` output. A future Xcode/macOS toolchain could
reformat the requirement string without changing the underlying identity. Treat
that as a release-tooling migration: confirm no identity value drifted, then
update the pinned strings, this ADR, and the ratchet test in the same PR.

## Consequences

### Positive

- Accidental re-signing, bundle-ID, launchd-label, or path drift fails before it
  can invalidate user permissions or strand launchd on stale constraints.
- Future identity changes must declare their migration story instead of slipping
  through packaging edits.
- The helper identity is now aligned with the shipped helper plist and signed
  executable: `com.keypath.helper`. Installer helper repair recipes now pass
  that shipped service ID instead of the stale `com.keypath.KeyPath.Helper`
  value.

### Negative

- Developer ID certificate/team changes now require updating tests, this ADR,
  and release verification in the same migration PR.
- The current daemon shell signing identifier remains `kanata-launcher`, which
  is stable but filename-derived. Renaming the shell is therefore a breaking
  identity change unless the release process intentionally pins a new explicit
  signing identifier with migration notes.
