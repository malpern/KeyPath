# Script Surface Audit

This inventory records the reference audit required before pruning scripts. It
is a snapshot of the tracked `Scripts/` tree on July 12, 2026; the repository
and its workflow files remain the source of truth as the tree evolves.

## Supported surface by purpose

| Area | Tracked files | Purpose |
| --- | ---: | --- |
| `Scripts/` top level | 93 | Supported build, deploy, release, test-lane, verification, data-generation, and focused QA entry points |
| `Scripts/lab/` | 19 | Disposable VM admission, providers, scenarios, and lab support |
| `Scripts/ui-tests/` | 18 | UI automation suites and their shared helpers |
| `Scripts/test-scripts/` | 35 | Test-runner helpers grouped by config, system, TCP, validation, and oracle concerns |
| `Scripts/test-fixtures/` | 15 | Data and config inputs consumed by tests |
| `Scripts/lib/` | 8 | Shared shell libraries used by supported entry points |
| `Scripts/accessibility/` | 5 | Accessibility audit support |
| `Scripts/help-videos/` | 4 | Help-video capture support |
| `Scripts/tests/` | 2 | Script contract tests |

`Scripts/README.md` lists the recommended public entry points. Nested helpers
and fixtures are implementation details unless another process document says
otherwise.

## Archive inventory

The 58 files in `Scripts/archive/` were grouped by their stated purpose:

| Purpose | Count | Examples |
| --- | ---: | --- |
| Build variants and experiments | 13 | `build-fast.sh`, `build-xcode.sh`, `compile.sh` |
| Test runners and test experiments | 15 | `run-tests-direct.sh`, `test-smappservice-poc.sh` |
| Installer, sudoers, and service repair experiments | 9 | `apply-sudoers.sh`, `install-system.sh` |
| Diagnostics and log helpers | 8 | `diagnose-kanata.sh`, `correlate-logs.sh` |
| Development deploy/watch variants | 5 | `dev-deploy.sh`, `monitor-hot-reload.sh` |
| Repository setup and validation variants | 4 | `setup-git-hooks.sh`, `validate-project.sh` |
| Other historical utilities | 4 | narrowly scoped validation or permission utilities |

## Reference audit

The audit searched exact archived paths and script basenames in GitHub
workflows, documentation, guides, hooks, release/build scripts, Swift sources,
tests, package metadata, and repository instructions.

- `Scripts/archive/run-core-tests.sh` was the only archived script with an
  exact-path consumer: `docs/process/new-developer-guide.md`.
- `Tests/README.md` also advertised `run-core-tests.sh` without its directory.
- The runner was obsolete: it claimed a fixed 422-test suite, bypassed
  `run-tests-safe.sh`, implemented its own timeout and result parsing, and had
  no automation consumer. It was deleted after both documentation references
  were moved to `test-fast.sh --changed` and `test-full.sh`.
- No other exact archived paths are referenced by current repository content.
  Basename matches such as `diagnose-helper.sh` and `install-system.sh` resolve
  to supported scripts outside the archive and are not archive consumers.

## Retention decision

The other 57 archived scripts remain historical artifacts for now. Lack of an
in-repository reference does not prove that a diagnostic or recovery script has
no remaining forensic value. Delete further groups only in focused changes
that compare their behavior with the supported replacement and confirm that no
documented or external operator workflow still depends on them.
