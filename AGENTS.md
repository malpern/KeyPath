# AGENTS.md

These instructions are the single source of truth for all agent sessions in this
repository, including Codex and Claude. Do not duplicate repo policy in
`CLAUDE.md`; update this file instead.

## Web Search Tooling
- Always use `web_search_request` for any web lookups.
- Never call the deprecated `tools.web_search` tool. Treat it as unavailable.
- Do not pass the CLI flag `--search`. Rely on the feature flag or config instead.

Rationale: older CLI/tooling may still expose `tools.web_search`, which prints a deprecation warning. Enforcing `web_search_request` avoids the warning and keeps behavior consistent.

## General
- KeyPath is a macOS keyboard remapping app built with SwiftUI and a Kanata
  backend using LaunchDaemon/privileged-helper architecture.
- User config: `~/.config/keypath/keypath.kbd`.
- Logs: `~/Library/Logs/KeyPath/keypath-debug.log`.
- Keep diffs minimal and focused. Preserve directory layout and script entry points.
- Update docs/tests when behavior or commands change.

### Bug Investigation
1. Check logs first (`~/Library/Logs/KeyPath/keypath-debug.log`).
2. Trace the full code path, including actor hops and async boundaries.
3. Fix both the proximate cause and the deeper cause.
4. Document durable bugs or architectural lessons in `docs/bugs/` or `docs/adr/`.

## Build, Deploy, and Release Workflow

Use the narrowest workflow that matches the task. Do not run the full notarized
release path for ordinary UI/code iteration.

### 1. Inner Loop: local development
Use for Swift/UI changes while iterating:
```bash
swift build
./Scripts/test-fast.sh --changed
python3 Scripts/check-accessibility.py
```

Notes:
- Use test filters aggressively while implementing. Prefer `./Scripts/test-fast.sh
  --changed` or a named area such as `./Scripts/test-fast.sh rules`,
  `./Scripts/test-fast.sh ui`, or `TEST_FILTER=SomeTests
  ./Scripts/run-tests-safe.sh` over full-suite reruns after every edit.
- Run `./Scripts/quick-deploy.sh` only when you need to inspect installed app
  behavior. It is not required for model/parser/service-only changes.
- `quick-deploy.sh` updates `/Applications/KeyPath.app`, re-signs locally, and
  restarts KeyPath only if it was running.
- It intentionally does **not** redeploy the privileged helper unless
  `KEYPATH_DEPLOY_HELPER=1` is set. Avoid helper redeploys during UI work.
- Use Poltergeist only for focused single-agent Swift/UI iteration:
  `poltergeist start`, edit, then `poltergeist wait keypath`. Stop it before
  release work, helper/service work, broad tests, or parallel agents.
- Near PR time, run the full safe gate once with `./Scripts/test-full.sh` (or
  `KEYPATH_SNAPSHOTS=1 ./Scripts/run-tests-safe.sh`). Do not run the full safe
  suite after every small edit.
- Before that final broad gate and before opening/watching a PR, fetch
  `origin/master` and confirm the branch is current:
  `git rev-list --left-right --count origin/master...HEAD` should report `0` as
  the first number. If not, rebase or merge first so CI and review run only once
  on a mergeable branch.
- Avoid notarized builds until after merge unless the task explicitly needs
  Developer ID/Gatekeeper behavior.
- SwiftFormat is pinned to 0.61.1 (`mise.toml`). Match the pin before formatting;
  a different version can reformat unrelated code.

### Worktree Hygiene (one thread ⇄ one worktree ⇄ one `.build`)

- Each concurrent agent/session works in its **own git worktree** with its own
  `.build`. Never point two threads at the same checkout.
- The **main worktree** (`/Users/malpern/local-code/keypath`) is
  **integration-only**: keep it on `master` for merging and pulling. Do NOT do
  feature work or run `swift build`/`swift test` there — that is the root cause
  of SwiftPM lock/CPU contention and cross-thread collisions.
- Create work in a fresh worktree:
  `git worktree add -b <branch> <path> master`; build and open the PR from it.
- After a PR merges, prune its worktree: `git worktree remove <path>`. It refuses
  when there is uncommitted work — that is a feature: inspect that work before
  deleting; never `--force`-remove blindly. Gate pruning on the **PR being
  merged**, not `git branch --merged` (squash-merges are not `master` ancestors,
  so that misreports them).

### PR Workflow & Git Safety

- Follow the invariants in `docs/process/agent-pr-invariants.md`. Step-by-step
  reference: `docs/process/agent-pr-workflow.md`.
- After merging a PR, always pull `master` and deploy from `master` before
  reporting done.
- Before creating any PR, run `./Scripts/review-gate.sh` against the branch
  diff and address findings. If local review tooling is unavailable, exit code
  2 means `remote review gate selected`; record that in the PR and do not merge
  until GitHub `claude-review` passes.
- Do not report missing local review tools as a PR issue. The actionable gate
  state is `remote review gate selected`; the GitHub `claude-review` check is
  the enforced reviewer in that path.
- Git guardrail hooks in `.claude/settings.json` block commits on `master`,
  force-pushes to `master`, `reset --hard`, and `clean -f`.

### Kanata Fork Safety

- The kanata submodule (`External/kanata`) tracks `keypath/bundled` on
  `malpern/kanata`. Treat `keypath/bundled` like `master`: never force-push it.
- Before pushing to any remote branch in the fork, verify the push is a
  fast-forward: `git log --oneline <source>..<target>`.
- If commits would be lost, cherry-pick instead. The `main` branch in
  `kanata-pr` may diverge from `keypath/bundled`; they are not interchangeable.

### Swift Build/Test Performance

- Prefer targeted tests while iterating:
  `swift test --filter <TestClassOrMethod>`
- Run full `swift test` before PR/merge, release-candidate work, or after
  broad/shared changes.
- Avoid running broad Swift builds/tests concurrently across worktrees. Before
  full test, release-candidate, or expensive build work, check for active Swift
  compiles:
  `pgrep -fl 'swift-test|swift-build|swift-frontend|swift-driver'`
- If another worktree/agent is compiling and you must continue, reduce local
  parallelism:
  `swift test --jobs 4`
  `swift build --jobs 4`
- Do not delete `.build` or run clean builds unless diagnosing cache/build-state
  problems; preserving incremental build products is usually faster.
- If a full suite stalls after compilation, triage it as a test failure/hang,
  not compile slowness. Capture the failing test name and log path in the
  handoff.

### 2. Release Candidate: signed local testing
Use after a PR is merged when `/Applications/KeyPath.app` should match a real
Developer ID/notarized build for manual testing:
```bash
git fetch --prune origin
git pull --ff-only origin master
./Scripts/release-candidate.sh
```

Run this from the intended `master` worktree. If another worktree owns `master`,
pull and deploy there instead of from the feature worktree.

Defaults:
- runs `./Scripts/release-doctor.sh --release-candidate` before the expensive build
- skips screenshot regeneration (`SKIP_SNAPSHOTS=1`)
- skips Peekaboo screenshot generation (`SKIP_PEEKABOO=1`)
- skips Sparkle archive/appcast generation (`SKIP_SPARKLE=1`)
- skips website publishing (`SKIP_WEBSITE=1`)
- deploys to `/Applications/KeyPath.app`
- runs installed-app verification

Use opt-ins only when needed:
```bash
./Scripts/release-candidate.sh --with-snapshots
./Scripts/release-candidate.sh --with-sparkle
./Scripts/release-candidate.sh --with-website
```

If local worktrees/builds are consuming disk, inspect generated artifacts with
`./Scripts/cleanup-local-build-artifacts.sh` and delete them only with
`./Scripts/cleanup-local-build-artifacts.sh --apply`.

### 3. Ship: public release artifacts
Use the public release script only when producing public distribution artifacts:
```bash
./Scripts/release-doctor.sh --ship
./Scripts/release.sh <version>
```

This path may bump versions, regenerate screenshots, create Sparkle artifacts,
notarize, staple, deploy, tag, create a GitHub release, and publish website help
content depending on environment flags. It is intentionally slower than the
release-candidate path. `release.sh` runs `release-doctor.sh --ship`
automatically unless explicitly skipped for script debugging. Do not use
`--skip-notarize` for public releases. `Scripts/build-and-sign.sh` is the
lower-level artifact builder used by the release scripts.

### 4. Installed app verification
After any signed/notarized deploy, or when diagnosing a local install:
```bash
./Scripts/verify-installed-app.sh
```

It verifies:
- code signature
- Gatekeeper assessment
- stapled notarization ticket
- KeyPath process
- `system/com.keypath.kanata` launchd job
- TCP readiness on `127.0.0.1:37001`

For non-notarized local debug builds, skip distribution trust checks:
```bash
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

For trust-only diagnostics where KeyPath is not running yet:
```bash
CHECK_RUNTIME=0 ./Scripts/verify-installed-app.sh
```

### 5. Release QA CLI
For release-candidate and installed-app QA, use the CLI inside the installed app:
```bash
/Applications/KeyPath.app/Contents/MacOS/keypath-cli
```

Do **not** use `.build/debug/keypath-cli` for release QA that validates or
applies config. The debug CLI resolves bundled Kanata relative to `.build/debug`
and expects `.build/debug/Contents/Library/KeyPath/Kanata Engine.app/...`, which
does not exist in a normal SwiftPM debug build. The installed CLI resolves the
bundled engine from `/Applications/KeyPath.app` and matches the deployed app
under test.

### Short Commands

- `dd`: run `SKIP_NOTARIZE=1 ./build.sh`, then respond `Eye eye Captain!`
- `df`: run `./Scripts/quick-deploy.sh`, then respond `Eye eye Cap, fast deploying!`
- `ds`: development ship workflow for the current changes, end to end: branch
  off `master`, format/lint, commit, run the review gate, push and open PR,
  babysit CI, address feedback, merge, pull `master`, then run
  `./Scripts/release-candidate.sh` from `master` for signed/notarized manual
  testing. Public distribution is a separate explicit release:
  `./Scripts/release-doctor.sh --ship && ./Scripts/release.sh <version>`.

Test targets: `KeyPathTests` (`Tests/KeyPathTests/`), `KeyPathSmokeTests`,
`KeyPathSnapshotTests`, and `KeyPathLayoutTracerTests`.

## Architecture & Patterns

### Responsibility Map

| Class | Responsibility |
|-------|----------------|
| `InstallerEngine` | The facade for all install, repair, uninstall, and system inspection |
| `RuntimeCoordinator` | Service orchestration; not an `ObservableObject` |
| `ServiceLifecycleCoordinator` | Start, stop, and restart Kanata |
| `ServiceHealthChecker` | Health checks and service state evidence |
| `ConfigReloadCoordinator` | TCP-based reload after rule changes |
| `KanataViewModel` | UI layer with observable properties for SwiftUI |
| `PermissionOracle` | Single source of truth for permissions |

### InstallerEngine Façade
- **Use `InstallerEngine`** for ANY system modification task:
  - Installation: `InstallerEngine().run(intent: .install, using: broker)`
  - Repair/Fix: `InstallerEngine().run(intent: .repair, using: broker)`
  - Uninstall: `InstallerEngine().uninstall(...)`
  - System Check: `InstallerEngine().inspectSystem()`
- **Do NOT use**:
  - `KanataManager` for installation/repair (it's for runtime coordination only).
  - `WizardAutoFixer` (deleted — call `InstallerEngine.runSingleAction()` directly).

### Opportunistic Manager Consolidation
- When a change naturally spans overlapping Manager/Coordinator/Service types,
  prefer moving the touched responsibility into the existing canonical owner and
  deleting the redundant bridge instead of adding another forwarding layer.
- Do not create broad "merge the managers" cleanup PRs. Consolidate only when
  already touching the area for a concrete behavior, reliability, testability,
  or compile-boundary improvement. See
  [ADR-043](docs/adr/adr-043-opportunistic-manager-consolidation.md).

### Permissions
- **Always use `PermissionOracle.shared`** for permission checks.
- Never call `IOHIDCheckAccess` directly **outside of PermissionOracle**.
- Never check TCC database directly **outside of PermissionOracle**.
- **Exception**: `PermissionOracle` itself uses `IOHIDCheckAccess` and TCC as its
  internal implementation (see [ADR-001](docs/adr/adr-001-oracle-pattern.md) and
  [ADR-016](docs/adr/adr-016-tcc-database-reading.md)). Apple APIs are
  authoritative; TCC is a fallback for `.unknown` results only.

### Keyboard Visualization
- **Geometry follows selected `PhysicalLayout`** (user-selected layout ID).
- **Labels follow selected `LogicalKeymap`** (user-selected keymap).
- Do **not** add a UI toggle for this; treat it as a single consistent rule.

### Service Lifecycle Invariants
- For installer/repair changes, use
  `docs/process/installer-repair-state-matrix.md` as the review checklist.
- **Mutating installer actions must be postcondition-verified before returning success.**
  - Any action that can stop/restart/re-register Kanata must verify runtime readiness (`running + TCP responding`) or explicit pending-approval state before reporting success.
- **Stale SMAppService recovery bypasses generic install throttle.**
  - If state is `.enabled` but launchd cannot load/run the daemon, recovery install/register logic must run even inside the normal throttle window.
- **Registration is not liveness.**
  - Treat `SMAppService.status == .enabled` as registration metadata only; never infer runtime health from it without process + TCP evidence.
- **Helper responsiveness is not helper freshness.**
  - After helper deploys or helper behavior changes, verify version/path or force
    the unregister/register repair path instead of treating an XPC response as
    proof that the running helper is current.
- **Stale diagnostics must not outrank current runtime state.**
  - Log-derived input-capture issues only apply to a live current runtime. If
    Kanata is missing or stopped, install/start runtime services first.

### Lifecycle and Health Anti-Patterns

- Do not manually call `launchctl` for install/repair paths; use
  `InstallerEngine`.
- Do not roll your own `pgrep`/`launchctl` health checks; use
  `ServiceHealthChecker`.
- Do not start, stop, or restart Kanata except through
  `ServiceLifecycleCoordinator`.
- Do not send TCP reloads directly; use
  `ConfigReloadCoordinator.triggerConfigReload()`.
- Do not skip TCP reload after config changes; that causes stale config.
- Do not call `SMAppService.status` in a hot path; it is synchronous IPC and can
  block for 10-30 seconds.
- Do not call real `pgrep` in tests; use `KeyPathTestCase` base class.

### Testing
- **Mock Time**: Do not use `Thread.sleep`. Use `Date` overrides or mock clocks.
- **Environment**: Use `KEYPATH_USE_INSTALLER_ENGINE=1` (default now) for tests.
- Use the narrowest meaningful test command during iteration; prefer
  `swift test --filter <TestClassOrMethod>` for focused changes.
- Run full `swift test` before PR/merge when practical, but do not leave hung
  suites running. If a full run times out or stalls in an unrelated test, report
  the failing test and keep targeted validation for the current change.

### Accessibility (CRITICAL)
- **ALL interactive UI elements MUST have `.accessibilityIdentifier()`**
- **Required for:** Button, Toggle, Picker, and custom interactive components
- **Enforcement:** Pre-commit hook + CI check (currently warning only)
- **Verification:** Run `python3 Scripts/check-accessibility.py` before committing
- **See:** `ACCESSIBILITY_COVERAGE.md` for complete reference
- **Rationale:** Enables automation (Computer Use, XCUITest, legacy Peekaboo) and ensures testability

## Documentation

Two doc systems exist:
- `guides/`: user-facing, published to `gh-pages`.
- `docs/`: developer-facing, `master` only.

Any user-visible feature needs a guide in `guides/`. Developer-only changes go
in `docs/` when they affect architecture or integration patterns.

Publishing: `guides/` content must be copied to the `gh-pages` branch to go
live. Use `Scripts/publish-guides.sh` or manually copy changed files to the
`gh-pages` worktree at `.worktrees/gh-pages`. The docs landing page
(`docs.md` on `gh-pages`) must be updated to link new guides.

Style: follow `docs/process/help-content-philosophy.md` -- user goals first, no
jargon, ASCII UI mockups. Guides need Jekyll frontmatter.

## Available External Tools

These CLI tools are available for agents to use on-demand. Do not add them as MCPs - just call them directly when needed.

### Poltergeist (Auto-Deploy)
Watches source files, auto-builds, deploys to /Applications, and restarts. Install: `brew install steipete/tap/poltergeist`

| Command | Purpose |
|---------|---------|
| `poltergeist start` | Start watching and auto-deploying (~2s per change) |
| `poltergeist status` | Check build status |
| `poltergeist logs` | View build output |
| `poltergeist stop` | Stop watching |
| `poltergeist wait keypath` | Block until build completes |

**Workflow tip:** Use `poltergeist start` only during focused single-agent app/UI iteration. After any watched Swift file edit, it runs `./Scripts/quick-deploy.sh`, deploys to `/Applications`, and restarts. Stop it before release builds, helper/service work, broad tests, or parallel agents.

### Computer Use (Preferred UI QA)

Use Computer Use for agent-driven UI testing and release QA. It reads the
macOS accessibility tree, can click accessible controls, and validates the same
automation hooks we need for 1.0 QA. Prefer Computer Use over Peekaboo unless
the user explicitly asks for Peekaboo or Computer Use is unavailable.

### Peekaboo (UI Automation)
macOS screenshots and GUI automation. Install: `brew install steipete/tap/peekaboo`

| Command | Purpose |
|---------|---------|
| `peekaboo see "prompt"` | Screenshot + AI analysis |
| `peekaboo click --element-id X` | Click by element ID |
| `peekaboo type "text"` | Enter text |
| `peekaboo scroll up/down` | Scroll |
| `peekaboo app launch Safari` | App control |
| `peekaboo window maximize` | Window management |
| `peekaboo menu "File > Save"` | Menu interaction |

### KeyPath (Keyboard Control)
Trigger via URL scheme:
```bash
open "keypath://layer/vim"           # Switch layer
open "keypath://launch/Safari"       # Launch app
open "keypath://window/left"         # Snap window
open "keypath://fakekey/nav-mode/tap" # Trigger virtual key
```

### Composing Tools
```bash
# Example: AI-driven development workflow
poltergeist start                    # Optional for focused single-agent UI iteration
# ... make code changes ...
poltergeist wait keypath             # Wait for build to complete
peekaboo see "Is the KeyPath app running?" # Check UI state
open "keypath://layer/vim"           # Trigger keyboard action
peekaboo type "Hello world"          # Type into focused app
peekaboo hotkey "cmd+s"              # Save
```

**Recommended agent workflow when Poltergeist is useful:**
1. Confirm no other agents/worktrees are doing builds.
2. `poltergeist start` for focused Swift/UI iteration.
3. Make code edits.
4. `poltergeist wait keypath` before testing.
5. Use Computer Use for UI verification.
6. `poltergeist stop` before release work, helper/service work, broad tests, or handing off.

See `docs/guides/llm-vision-ui-automation.md` for detailed architecture.

## Deep-Dive References

Load these on demand; do not treat them as required reading for every session.

| Topic | Doc |
|-------|-----|
| Release process | `docs/process/release-process.md` |
| Installer repair state matrix | `docs/process/installer-repair-state-matrix.md` |
| Help content writing | `docs/process/help-content-philosophy.md` |
| Pack dependency system | `docs/architecture/pack-dependency-system.md` |
| Overlay/mapper/gallery data flow | `docs/architecture/overlay-data-flow.md` |
| UI automation | `docs/guides/llm-vision-ui-automation.md` |
| Architecture guides | `docs/architecture/` |
| ADRs | `docs/adr/README.md` |
| Feature docs | `docs/features/` |
