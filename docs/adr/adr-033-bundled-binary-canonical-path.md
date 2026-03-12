# ADR-033: Bundled Binary as Canonical Kanata Path

**Status:** Accepted
**Date:** 2026-03-11
**Supersedes:** Portions of ADR-032 (system binary preference)

## Context

KeyPath previously installed a copy of the kanata binary to `/Library/KeyPath/bin/kanata` via a privileged helper. This "system binary" served as the canonical TCC identity — users granted Input Monitoring and Accessibility permissions to this stable path. The concern was that app bundle paths would change across rebuilds, invalidating TCC entries.

## Decision

**The bundled binary at `/Applications/KeyPath.app/Contents/Library/KeyPath/kanata` is now the canonical path.** The system binary at `/Library/KeyPath/bin/kanata` is no longer installed.

## Rationale

### TCC Stability Mechanism

macOS TCC uses **path-based lookup** (`client_type=1`) for CLI binaries. The TCC entry is keyed to the full executable path. We validated that:

1. **`quick-deploy.sh` rebuilds** preserve TCC entries — the binary at `/Applications/KeyPath.app/Contents/Library/KeyPath/kanata` retains its grants after `cp -R` deployment.
2. **Full `build.sh` rebuilds** (sign + notarize) also preserve TCC entries — the Developer ID code signature identity is stable across builds from the same signing certificate.
3. The path `/Applications/KeyPath.app/Contents/Library/KeyPath/kanata` is **just as stable** as `/Library/KeyPath/bin/kanata` because the app is always deployed to `/Applications/KeyPath.app`.

### Benefits

- Eliminates ~1900 lines of system binary installer code
- Removes the `installBundledKanataBinaryOnly` privileged helper operation (reduced attack surface)
- Removes the wizard's "Kanata Engine Setup" page (simpler install flow)
- No more path fragmentation between what the daemon executes and what users grant permissions to
- The `kanata-launcher.sh` script no longer needs to prefer a system binary

### Migration

Users who previously granted TCC permissions only to `/Library/KeyPath/bin/kanata` (and not the bundled path) will need to re-grant permissions. The `PermissionOracle` includes a migration fallback that checks the legacy system path for TCC entries when the bundled binary is not found.

The `removeSystemKanataBinary()` method is retained in the uninstall path for one release to clean up legacy installs.

## Consequences

- All path resolution returns the bundled binary path
- `KanataRuntimeHost.systemCorePath` is deprecated (returns `bundledCorePath`)
- `WizardSystemPaths.kanataSystemInstallPath` is deprecated (use `bundledKanataPath`)
- Future maintainers should NOT re-add a system binary copy; TCC stability is ensured by the stable `/Applications/KeyPath.app` install location
