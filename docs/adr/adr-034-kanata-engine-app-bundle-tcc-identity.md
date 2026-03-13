# ADR-034: Kanata Engine.app Bundle for TCC Identity

**Status:** Accepted
**Date:** 2026-03-12
**Supersedes:** client_type=1 (path-based) aspects of ADR-033

## Context

KeyPath's kanata binary lived at `Contents/Library/KeyPath/kanata` inside the app bundle. macOS TCC tracked it with `client_type=1` (path-based identity). This worked but had two problems:

1. **Tahoe visibility** — Starting with macOS Tahoe 26.1+, path-based TCC entries (`client_type=1`) are invisible in System Settings > Privacy & Security. Users cannot see or manage the grant.
2. **File picker navigation** — When macOS prompts users to manually grant permissions via a file picker, users cannot navigate inside `.app` bundles to select a raw binary.

Karabiner-Elements solved the same problem by wrapping its core binary in a minimal `.app` bundle (`Karabiner-Core-Service.app`). This gives the binary a bundle identity that macOS recognizes as a first-class application.

## Decision

Wrap the kanata binary in **Kanata Engine.app** — a minimal `.app` bundle with no UI.

### Bundle Identity

| Property | Value |
|----------|-------|
| CFBundleIdentifier | `com.keypath.kanata-engine` |
| CFBundleName | `Kanata Engine` |
| LSUIElement | `true` (no Dock icon) |
| CFBundleExecutable | `kanata` |

### Bundle Layout

```
KeyPath.app/
  Contents/
    Library/
      KeyPath/
        Kanata Engine.app/
          Contents/
            MacOS/
              kanata          ← the actual binary
            Info.plist
            Resources/
              AppIcon.icns    ← KeyPath engine icon
        kanata                ← backward-compat symlink (one release)
```

### TCC Tracking

macOS TCC now tracks Kanata Engine.app by **bundle ID** (`client_type=0`):

| Before | After |
|--------|-------|
| `client_type=1`, `client=/Applications/KeyPath.app/Contents/Library/KeyPath/kanata` | `client_type=0`, `client=com.keypath.kanata-engine` |

Bundle ID entries appear in System Settings with proper name and icon, and survive app updates and path changes.

### Code Signing

Sign inside-out to satisfy Gatekeeper:

1. Sign `Kanata Engine.app` (inner bundle)
2. Sign `KeyPath.app` (outer bundle)

The outer bundle's signature covers the inner bundle. Both use the same Developer ID certificate.

### LaunchDaemon

The LaunchDaemon configuration is **unchanged**. `kanata-launcher.sh` still exec's into the kanata binary — the only difference is the binary's path is now inside `Kanata Engine.app/Contents/MacOS/kanata`.

### Migration

- A **backward-compatibility symlink** at `Contents/Library/KeyPath/kanata` points to `Kanata Engine.app/Contents/MacOS/kanata` for one release cycle, ensuring existing LaunchDaemon configs and scripts continue to work.
- `PermissionOracle` checks both bundle ID (`client_type=0`, `com.keypath.kanata-engine`) and legacy path (`client_type=1`) during the migration period. See [ADR-035](adr-035-bundle-id-tcc-detection-with-path-fallback.md).

## Consequences

### Positive
- TCC grants visible and manageable in System Settings on Tahoe+
- Users can select Kanata Engine.app in file pickers if manual granting is needed
- Bundle ID identity is stable across rebuilds, updates, and path changes
- Follows the same pattern proven by Karabiner-Elements

### Negative
- Slightly more complex build pipeline (inner bundle signing)
- One release of symlink migration complexity

## Related
- [ADR-033: Bundled Binary as Canonical Path](adr-033-bundled-binary-canonical-path.md) — binary is still bundled, just wrapped in .app
- [ADR-035: Bundle ID TCC Detection with Path Fallback](adr-035-bundle-id-tcc-detection-with-path-fallback.md) — detection strategy
- [ADR-016: TCC Database Reading](adr-016-tcc-database-reading.md) — how we read TCC
