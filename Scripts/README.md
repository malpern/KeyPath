# Scripts

## Supported commands (recommended)
- `./Scripts/quick-deploy.sh` — Incremental local dev (fast, deploys to /Applications; run `./build.sh` once first).
- `./build.sh` — Canonical build & sign entry (root). Use `SKIP_CODESIGN=1` to bypass signing for local dev.
  - Release builds now fail if Sparkle EdDSA signing cannot be produced for the update archive.
  - For local-only testing, set `ALLOW_UNSIGNED_SPARKLE=1` to continue without an EdDSA signature.
- `./test.sh` — Run the full test suite (root)
- `./Scripts/run-installer-reliability-matrix.sh` — Automated installer reliability matrix + diagnostic artifact bundle (`test-results/installer-reliability/latest`).
- `./Scripts/repro-duplicate-keys.sh` — CPU-load repro harness for duplicate keypress detection (filters navigation keys by default). Supports `--auto-type osascript` or `--auto-type peekaboo` for deterministic automated keystroke generation, and continuously samples Kanata process metrics (CPU%, memory, threads, priority).

## Scripts in this directory
- `build-and-sign.sh` - The implementation of the build process
- `run-tests-safe.sh` - The safe test runner implementation
- `run-installer-reliability-matrix.sh` - Runs installer scenario lanes and writes `matrix-summary.md` + `matrix-results.json`
- `uninstall.sh` - Uninstaller script
- `archive/` - Deprecated or historical scripts
- `lib/signing.sh` - Thin wrappers around codesign/notarytool/stapler with `KP_SIGN_DRY_RUN=1` for safe local runs; CI overrides hook into this.
- `test-installer-device.sh` - Opt-in device smoke for InstallerEngine (requires `KEYPATH_E2E_DEVICE=1`; non-destructive).

## Testing
- `test.sh` (in root) - All tests
- `test-*.sh` (in Scripts/) - Individual test suites
- CI also runs:
  - `swift test --filter SigningPipelineTests` (verifies signing/notary wrappers surface failures and honor dry-run)
  - `swift test --filter InstallerEngineEndToEndTests` (ensures InstallerEngine executes plans and stops on broker failures)
  - `./Scripts/run-installer-reliability-matrix.sh` (pre/during/post install lanes + inspect snapshot artifact)
  - Optional/local: `KEYPATH_E2E_DEVICE=1 swift test --filter InstallerDeviceTests` or `./Scripts/test-installer-device.sh` for real-surface installer smoke

## Development Setup
Most development scripts have been moved to `archive/`.
