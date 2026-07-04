# MacBook Air Local Test Loop

This workflow optimizes for fast, reliable feedback on the primary development
MacBook Air. Mac mini orchestration is intentionally deferred until local lane
measurements show a capacity problem that remote execution would actually solve.

## Default Loop

Run the smallest lane that covers the files you changed:

| Change type | Command |
| --- | --- |
| Core APIs, permissions, parser smoke coverage | `./Scripts/test-lane.sh smoke` |
| Core-only runtime, parser, and environment behavior | `./Scripts/test-lane.sh core-isolated` |
| Fast root-package model/parser/renderer logic | `./Scripts/test-lane.sh unit` |
| CLI commands, facades, output contracts, import/export | `./Scripts/test-lane.sh cli` |
| TCP, runtime coordinator, process, permissions, keyboard capture, system support | `./Scripts/test-lane.sh runtime` |
| AppKit UI/state, mappers, preferences, recommendations | `./Scripts/test-lane.sh appkit-ui` |
| AppKit config, packs, catalog, rule collections | `./Scripts/test-lane.sh appkit-config` |
| Broad AppKit-adjacent handoff check | `./Scripts/test-lane.sh appkit` |
| InstallerEngine, wizard, daemon lifecycle, health checks | `./Scripts/test-lane.sh installer` |
| Snapshot or visual output changes | `./Scripts/test-lane.sh snapshot` |
| Device/system installer surface | `KEYPATH_E2E_DEVICE=1 ./Scripts/test-lane.sh device` |
| Before a broad handoff or PR | `./Scripts/test-lane.sh full` |

Use `core-isolated` when the change is limited to public `KeyPathCore` runtime,
parser, or test-environment behavior and you want proof that the AppKit graph
does not compile. Use `unit` when you want broader root-package parser/model
coverage; it is still fast when warm, but it is not a build-isolated lane.

The `cli` lane is focused for test execution and log scope, but it is not
build-isolated yet. `KeyPathCLI` still depends on `KeyPathAppKit`, so clean CLI
product builds compile the app UI/resource graph. Treat CLI/AppKit decoupling
as target extraction work, not another filter tweak.

For very narrow debugging, override the lane filter:

```bash
KEYPATH_TEST_FILTER=SaveCoordinatorTests ./Scripts/test-lane.sh appkit
```

## Warm Cache Policy

The local named lanes `unit`, `cli`, `runtime`, `appkit-ui`, `appkit-config`,
`appkit`, `installer`, and `snapshot` reuse the normalized Swift module cache by
default. This is the right default for the MacBook Air edit-test loop.

The `full` lane keeps the stricter reset behavior by default. Override either
mode explicitly when needed:

```bash
KEYPATH_TEST_RESET_MODULE_CACHE=1 ./Scripts/test-lane.sh appkit
KEYPATH_TEST_RESET_MODULE_CACHE=0 ./Scripts/test-lane.sh full
```

## Measuring The Loop

Use the measurement wrapper when changing lane behavior or comparing cold/warm
feedback:

```bash
./Scripts/measure-local-loop.sh
./Scripts/measure-local-loop.sh --preset baseline
./Scripts/measure-local-loop.sh --clean-smoke smoke
./Scripts/measure-local-loop.sh --clean-core core-isolated
```

Reports are written under `.build/local-loop-measurements/`, with the latest
Markdown and TSV reports linked at:

```bash
.build/local-loop-measurements/latest.md
.build/local-loop-measurements/latest.tsv
```

Presets:

- `quick`: runs `smoke`.
- `baseline`: runs `smoke`, `core-isolated`, `unit`, and `appkit`.
- `full`: runs `smoke`, `core-isolated`, `unit`, `appkit`, and `full`.

Current MacBook Air reference measurements:

| Lane | Mode | Result |
| --- | --- | --- |
| `smoke` | warm | 2s, 12 tests, `appkit_in_log=0` |
| `core-isolated` | clean | 15s, 13 tests, `appkit_in_log=0` |
| `core-isolated` | warm | 2s, 13 tests, `appkit_in_log=0` |
| `unit` | warm | 8s, 329 tests, zero warning/error summary counts |

## Clean Summary Guardrail

The safe runner can fail a passing test lane when warning/error counts regress:

```bash
KEYPATH_TEST_ENFORCE_CLEAN_SUMMARY=1 ./Scripts/test-lane.sh full
```

This checks the summary counts for Swift warnings, module-cache warnings, app
warnings, and app errors. Duration is intentionally not enforced because local
timing varies with machine load. Override a threshold only for a deliberate
temporary baseline:

```bash
KEYPATH_TEST_ENFORCE_CLEAN_SUMMARY=1 \
KEYPATH_TEST_MAX_TEST_APP_WARNINGS=1 \
./Scripts/test-lane.sh full
```

## Debugging Noisy Failures

Use the quiet defaults first. If the failure needs app diagnostics, opt into
verbose logs for that run only:

```bash
KEYPATH_TEST_VERBOSE_LOGS=1 KEYPATH_TEST_FILTER=ConfigHotReloadServiceTests ./Scripts/test-lane.sh appkit
```

If a filtered lane passes but the full lane fails, treat that as either a broad
build/test-runner interaction or cross-target coupling. Preserve the focused
passing command in the issue or PR notes before escalating to broader runs.

Local lanes also default to hermetic test-mode behavior with
`KEYPATH_USE_SUDO=0`, even if passwordless sudo is configured on the machine.
This keeps the MacBook Air loop aligned with CI and prevents installer tests
from probing real system services unless a run explicitly asks for it:

```bash
KEYPATH_USE_SUDO=1 ./Scripts/test-lane.sh installer
KEYPATH_TEST_AUTO_SUDO=1 ./Scripts/test-lane.sh installer
```

## Build And UI Iteration

For app iteration rather than test verification, keep Poltergeist running:

```bash
poltergeist start
poltergeist wait keypath
```

Use this for deploy/relaunch feedback. Use the lane commands above for test
signal.
