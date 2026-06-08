# Scripts

## Supported commands (recommended)
- `./Scripts/quick-deploy.sh` — Incremental local dev (fast, deploys to /Applications; run `./build.sh` once first).
- `./Scripts/release-doctor.sh` — Read-only preflight for signed/notarized release-candidate or public ship builds.
- `./Scripts/release-candidate.sh` — Signed/notarized post-merge manual-testing build; skips snapshots, Sparkle, and website publishing by default.
- `./build.sh` — Canonical build & sign entry (root). Use `SKIP_CODESIGN=1` to bypass signing for local dev.
  - Release builds now fail if Sparkle EdDSA signing cannot be produced for the update archive.
  - For local-only testing, set `ALLOW_UNSIGNED_SPARKLE=1` to continue without an EdDSA signature.
- `./Scripts/release.sh <version>` — Public distribution release flow. Run `./Scripts/release-doctor.sh --ship` first.
- `./Scripts/cleanup-local-build-artifacts.sh` — Dry-run cleanup of generated `.build`/`dist`/test artifacts across local worktrees. Add `--apply` to delete.
- `./test.sh` — Run the full test suite (root)
- `./Scripts/test-lane.sh <lane>` — Run a named SwiftPM test lane (`smoke`,
  `unit`, `appkit`, `installer`, `snapshot`, `device`, or `full`).
- `./Scripts/run-installer-reliability-matrix.sh` — Automated installer reliability matrix + diagnostic artifact bundle (`test-results/installer-reliability/latest`).
- `./Scripts/repro-duplicate-keys.sh` — CPU-load repro harness for duplicate keypress detection (filters navigation keys by default). Supports `--auto-type osascript` or `--auto-type peekaboo` for deterministic automated keystroke generation, and continuously samples Kanata process metrics (CPU%, memory, threads, priority).

## Scripts in this directory
- `build-and-sign.sh` - The implementation of the build process
- `release-doctor.sh` - Read-only preflight for signing, notarization, Sparkle, website, watcher, and runtime state.
- `release-candidate.sh` - Post-merge signed/notarized local build wrapper with fast defaults.
- `release.sh` - Public release wrapper for versioned distribution artifacts.
- `cleanup-local-build-artifacts.sh` - Safe local disk cleanup helper for generated build artifacts.
- `run-tests-safe.sh` - The safe test runner implementation
- `run-installer-reliability-matrix.sh` - Runs installer scenario lanes and writes `matrix-summary.md` + `matrix-results.json`
- `uninstall.sh` - Uninstaller script
- `archive/` - Deprecated or historical scripts
- `lib/signing.sh` - Thin wrappers around codesign/notarytool/stapler with `KP_SIGN_DRY_RUN=1` for safe local runs; CI overrides hook into this.
- `lib/deploy-lock.sh` - Shared cross-worktree lock for scripts that mutate `/Applications/KeyPath.app`.
- `test-installer-device.sh` - Opt-in device smoke for InstallerEngine (requires `KEYPATH_E2E_DEVICE=1`; non-destructive).

## Testing
- `test.sh` (in root) - All tests
- `test-*.sh` (in Scripts/) - Individual test suites
- `./Scripts/test-lane.sh smoke` - Fast sanity lane across core parsing,
  permissions, installer planning, CLI, and layout tracer tests.
- `./Scripts/test-lane.sh unit` - Pure or mostly pure model/parser/renderer
  tests.
- `./Scripts/test-lane.sh appkit` - UI-adjacent app logic, services, packs,
  config, mappers, and rule collection tests.
- `./Scripts/test-lane.sh installer` - InstallerEngine, wizard, daemon/service
  lifecycle, and health-check tests.
- `./Scripts/test-lane.sh snapshot` - Visual snapshot tests; sets
  `KEYPATH_SNAPSHOTS=1`.
- `KEYPATH_E2E_DEVICE=1 ./Scripts/test-lane.sh device` - Opt-in real-system
  installer smoke.
- `./Scripts/test-lane.sh full` - Full safe SwiftPM test suite.
- `./Scripts/run-tests-safe.sh` - CI-style safe test runner. Defaults to quiet
  app logs (`KEYPATH_LOG_LEVEL=3`) and prints build/test timing plus log size.
  Set `KEYPATH_TEST_VERBOSE_LOGS=1` for debug-level app diagnostics during a
  noisy test investigation.
- CI also runs:
  - `swift test --filter SigningPipelineTests` (verifies signing/notary wrappers surface failures and honor dry-run)
  - `swift test --filter InstallerEngineEndToEndTests` (ensures InstallerEngine executes plans and stops on broker failures)
  - `./Scripts/run-installer-reliability-matrix.sh` (pre/during/post install lanes + inspect snapshot artifact)
  - Optional/local: `KEYPATH_E2E_DEVICE=1 swift test --filter InstallerDeviceTests` or `./Scripts/test-installer-device.sh` for real-surface installer smoke

## Development Setup
Most development scripts have been moved to `archive/`.
