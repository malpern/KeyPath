# AGENTS.md

These instructions apply to all Codex sessions in this repository.

## Web Search Tooling
- Always use `web_search_request` for any web lookups.
- Never call the deprecated `tools.web_search` tool. Treat it as unavailable.
- Do not pass the CLI flag `--search`. Rely on the feature flag or config instead.

Rationale: older CLI/tooling may still expose `tools.web_search`, which prints a deprecation warning. Enforcing `web_search_request` avoids the warning and keeps behavior consistent.

## General
- Keep diffs minimal and focused. Preserve directory layout and script entry points.
- Update docs/tests when behavior or commands change.

## Architecture & Patterns

### InstallerEngine Façade
- **Use `InstallerEngine`** for ANY system modification task:
  - Installation: `InstallerEngine().run(intent: .install, using: broker)`
  - Repair/Fix: `InstallerEngine().run(intent: .repair, using: broker)`
  - Uninstall: `InstallerEngine().uninstall(...)`
  - System Check: `InstallerEngine().inspectSystem()`
- **Do NOT use**:
  - `KanataManager` for installation/repair (it's for runtime coordination only).
  - `LaunchDaemonInstaller` directly (it's an internal implementation detail).
  - `WizardAutoFixer` directly (superseded by Engine).

### Permissions
- **Always use `PermissionOracle.shared`**.
- Never call `IOHIDCheckAccess` directly.
- Never check TCC database directly.

### Testing
- **Mock Time**: Do not use `Thread.sleep`. Use `Date` overrides or mock clocks.
- **Environment**: Use `KEYPATH_USE_INSTALLER_ENGINE=1` (default now) for tests.


## Semantic Line Breaks (SemBr)
- Write and preserve semantic line breaks in prose (docs, comments). Break at sentence or clause boundaries, not fixed width.
- Do not reflow SemBr text with formatters; configure tools to respect existing line breaks or leave prose untouched.

## Sparkle Releases

When cutting a new release:

1. **Increment `CFBundleVersion`** (integer) in `Sources/KeyPathApp/Info.plist`
2. **Run `./build.sh`** — produces `dist/sparkle/KeyPath-X.Y.Z.zip` + `.sig` + `.appcast-entry.xml`
3. **Upload to GitHub Releases** with `gh release create`
4. **Update `appcast.xml`** — paste the generated entry (newest first)
5. **Create `docs/releases/X.Y.Z.html`** — styled release notes for Sparkle dialog
6. **Update `WhatsNewView.featuresForVersion()`** — add features for post-update dialog

**Version scheme:**
- `CFBundleShortVersionString` = display version (`1.0.0-beta2`)
- `CFBundleVersion` = integer for Sparkle (`2`)

See CLAUDE.md "Sparkle Auto-Updates" section for full details.
