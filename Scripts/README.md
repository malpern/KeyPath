# Scripts

## Supported commands (recommended)
- `./build.sh` — Canonical build & sign entry (root)
- `./test.sh` — Run the full test suite (root)

## Scripts in this directory
- `build-and-sign.sh` - The implementation of the build process
- `run-tests-safe.sh` - The safe test runner implementation
- `uninstall.sh` - Uninstaller script
- `archive/` - Deprecated or historical scripts
- `lib/signing.sh` - Thin wrappers around codesign/notarytool/stapler with `KP_SIGN_DRY_RUN=1` for safe local runs; CI overrides hook into this.
- `test-installer-device.sh` - Opt-in device smoke for InstallerEngine (requires `KEYPATH_E2E_DEVICE=1`; non-destructive).

## Lint Scripts
- `lint-no-sleep.sh` - Disallows Task.sleep in wizard code (use readiness polling instead)
- `lint-facade-bypass.sh` - Detects direct subprocess/AppleScript calls in WizardAutoFixer that bypass the InstallerEngine façade ([Issue #47](https://github.com/malpern/KeyPath/issues/47))

## Testing
- `test.sh` (in root) - All tests
- `test-*.sh` (in Scripts/) - Individual test suites
- CI also runs:
  - `swift test --filter SigningPipelineTests` (verifies signing/notary wrappers surface failures and honor dry-run)
  - `swift test --filter InstallerEngineEndToEndTests` (ensures InstallerEngine executes plans and stops on broker failures)
  - `swift test --filter WizardAutoFixerFacadeTests` (façade parity tests - verifies all AutoFixActions route through InstallerEngine)
  - `swift test --filter WizardRecipeParityTests` (recipe consistency tests)
  - Optional/local: `KEYPATH_E2E_DEVICE=1 swift test --filter InstallerDeviceTests` or `./Scripts/test-installer-device.sh` for real-surface installer smoke

## Development Setup
Most development scripts have been moved to `archive/`.
