# KeyPath 1.0.0-beta1

## Highlights
- First public beta build with bundled Kanata engine and setup wizard.
- Faster splash (2.5s) and updated InstallerEngine-based service handling.

## Download
- **ZIP**: KeyPath.zip (signed & notarized)
- SHA256: `a73d8bae1bac476bcaa75c5852fc24c7fee4f34b262029a1d62388adf0462daa`

## Install Steps
1. Unzip, move `KeyPath.app` to `/Applications`, open once, grant permissions.
2. Start the keyboard service from the wizard.

## Known Issues / Callouts
- Auto-update via Sparkle is not live yet; manual ZIP updates.
- Intel builds are not packaged; Apple Silicon focus for this beta.

## Changelog
- Add Sparkle integration scaffolding (feed URL, menu item, UpdateService) — disabled pending first appcast.
- Bundle Kanata from source in `Contents/Library/KeyPath/kanata`.
- Scripts: build-and-sign now produces Sparkle artifacts when notarization is enabled.
- UI: splash duration reduced to 2.5s.
