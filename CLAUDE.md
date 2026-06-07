# CLAUDE.md

KeyPath is a macOS keyboard remapping app (SwiftUI + Kanata backend, LaunchDaemon architecture).

## Architecture

```
KeyPath.app (SwiftUI) → InstallerEngine → LaunchDaemon/PrivilegedHelper
          ↓                    ↓
    KanataManager      SystemContext (State)
          ↓
   TCP/Runtime Control
```

| Class | Responsibility |
|-------|---------------|
| `InstallerEngine` | **The Facade** — all install/repair/uninstall + system inspection |
| `RuntimeCoordinator` | Service orchestration (NOT ObservableObject) |
| `ServiceLifecycleCoordinator` | **Start/stop/restart Kanata** — the ONLY entry point |
| `ServiceHealthChecker` | **Health checks** — the ONLY way to check if kanata is running |
| `ConfigReloadCoordinator` | TCP-based reload after rule changes |
| `KanataViewModel` | UI Layer (MVVM) — @Observable properties for SwiftUI |
| `PermissionOracle` | **CRITICAL** — Single source of truth for permissions |

User config: `~/.config/keypath/keypath.kbd`. Logs: `~/Library/Logs/KeyPath/keypath-debug.log`.

## Critical Rules

**PermissionOracle**: Apple APIs (IOHIDCheckAccess) ALWAYS take precedence over TCC database. See [ADR-001](docs/adr/adr-001-oracle-pattern.md), [ADR-006](docs/adr/adr-006-apple-api-priority.md).

**Validation order**: Conflicts → Components → Permissions → Service Status ([ADR-026](docs/adr/adr-026-validation-ordering.md)).

**Keyboard visualization**: Geometry follows `PhysicalLayout`, labels follow `LogicalKeymap`. No UI toggle.

## Anti-Patterns

- ❌ Never bypass `PermissionOracle.shared` or check permissions from root
- ❌ Don't use KanataManager for installation → Use `InstallerEngine`
- ❌ Don't manually call launchctl → Use `InstallerEngine`
- ❌ Don't roll your own `pgrep`/`launchctl` → Use `ServiceHealthChecker`
- ❌ Don't start/stop/restart kanata except via `ServiceLifecycleCoordinator`
- ❌ Don't send TCP reload directly → Use `ConfigReloadCoordinator.triggerConfigReload()`
- ❌ Don't skip TCP reload after config changes — causes stale config
- ❌ Don't call `SMAppService.status` in a hot path — synchronous IPC, blocks 10-30s
- ❌ Never call real `pgrep` in tests → deadlock. Use `KeyPathTestCase` base class
- ✅ Keep tests fast (<5s total) — use backdated timestamps, not real sleeps

## Bug Investigation

1. Check logs first (`~/Library/Logs/KeyPath/keypath-debug.log`)
2. Trace the full code path including actor hops and async boundaries
3. Fix both the proximate cause and the deeper cause
4. Document in `docs/bugs/`

## PR Workflow & Git Safety

Follow the invariants in [`docs/agent-pr-invariants.md`](docs/agent-pr-invariants.md). Step-by-step reference: [`docs/agent-pr-workflow.md`](docs/agent-pr-workflow.md).

**Key rule:** After merging a PR, always pull master and deploy from master before reporting done.

**Mandatory review gate:** Before creating any PR, run `/thermo-nuclear-swift-review` against the branch diff and address all findings. See Phase 2.5 in the workflow doc.

Git guardrail hooks in `.claude/settings.json` block: commits on master, force-push to master, `reset --hard`, `clean -f`.

**Kanata fork safety:** The kanata submodule (`External/kanata`) tracks `keypath/bundled` on `malpern/kanata`. Treat `keypath/bundled` like master — **never force-push** to it. Before pushing to any remote branch in the fork, verify the push is a fast-forward: `git log --oneline <source>..<target>`. If commits would be lost, cherry-pick instead. The `main` branch in kanata-pr may diverge from `keypath/bundled` — they are NOT interchangeable.

## Documentation

Two doc systems: `guides/` (user-facing, published to gh-pages) and `docs/` (developer-facing, master only).

**When to write docs:** Any user-visible feature needs a guide in `guides/`. Developer-only changes (refactors, internal APIs) go in `docs/` if they affect architecture or integration patterns.

**Publishing:** `guides/` content must be copied to the `gh-pages` branch to go live. Use `Scripts/publish-guides.sh` or manually copy changed files to the gh-pages worktree at `.worktrees/gh-pages`. The docs landing page (`docs.md` on gh-pages) must be updated to link new guides.

**Style:** Follow [`docs/help-content-philosophy.md`](docs/help-content-philosophy.md) — user goals first, no jargon, ASCII UI mockups. Guides need Jekyll frontmatter (layout, title, description, permalink).

## Build & Deploy

```bash
./build.sh                        # Canonical build (SKIP_NOTARIZE=1 for local dev)
./Scripts/quick-deploy.sh         # Fast debug deploy
./Scripts/release-doctor.sh       # Read-only release preflight
./Scripts/release-candidate.sh    # Signed/notarized post-merge testing
swift test                        # All tests (~532 tests, <5s)
swiftformat Sources Tests         # Uses pinned rules + swiftversion from .swiftformat
swiftlint --fix --quiet
```

### Workflow tiers

Use the narrowest workflow that matches the task:

**Inner loop:** For normal Swift/UI iteration, prefer `swift build` and
`./Scripts/quick-deploy.sh`. Use Poltergeist only for focused single-agent
Swift/UI iteration: `poltergeist start`, edit, then `poltergeist wait keypath`.
`quick-deploy.sh` updates `/Applications/KeyPath.app`, re-signs locally, and
restarts KeyPath only if it was already running. It does not redeploy the
privileged helper unless `KEYPATH_DEPLOY_HELPER=1` is set.

**Release candidate:** After a PR is merged and manual testing needs a real
Developer ID/notarized app in `/Applications`, run:

```bash
git fetch --prune origin
git pull --ff-only origin master
./Scripts/release-candidate.sh
```

Run this from the intended `master` worktree. If another worktree owns `master`,
pull and deploy there instead of from the feature worktree.

This runs `./Scripts/release-doctor.sh --release-candidate`, defaults to
`SKIP_SNAPSHOTS=1`, `SKIP_PEEKABOO=1`, `SKIP_SPARKLE=1`, and `SKIP_WEBSITE=1`,
then runs installed-app verification. Opt into slower release work only when
needed:

```bash
./Scripts/release-candidate.sh --with-snapshots
./Scripts/release-candidate.sh --with-sparkle
./Scripts/release-candidate.sh --with-website
```

**Public ship:** Use the public release script only when producing public
distribution artifacts:

```bash
./Scripts/release-doctor.sh --ship
./Scripts/release.sh <version>
```

That path may bump versions, regenerate screenshots, create Sparkle artifacts,
notarize, staple, deploy, tag, create a GitHub release, and publish website help
content depending on environment flags. `Scripts/build-and-sign.sh` is the
lower-level artifact builder used by the release scripts.

**Installed verification:** After signed/notarized deploys, or when diagnosing a
local install, run:

```bash
./Scripts/verify-installed-app.sh
```

It checks code signature, Gatekeeper assessment, stapled notarization ticket,
KeyPath process, `system/com.keypath.kanata`, and TCP readiness on
`127.0.0.1:37001`. For non-notarized debug builds:

```bash
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

For trust-only diagnostics where KeyPath is not running yet:

```bash
CHECK_RUNTIME=0 ./Scripts/verify-installed-app.sh
```

**Release QA CLI:** For release-candidate and installed-app QA, use the CLI
inside the installed app:

```bash
/Applications/KeyPath.app/Contents/MacOS/keypath-cli
```

Do **not** use `.build/debug/keypath-cli` for release QA that validates or
applies config. The debug CLI resolves bundled Kanata relative to `.build/debug`
and expects `.build/debug/Contents/Library/KeyPath/Kanata Engine.app/...`, which
does not exist in a normal SwiftPM debug build. The installed CLI resolves the
bundled engine from `/Applications/KeyPath.app` and matches the deployed app
under test.

**SwiftFormat is pinned to 0.61.1** (`mise.toml`); `master` is a formatted fixed-point
for that version + `.swiftformat` config, so a run produces **no churn**. A different
version reformats unrelated code (see #634) — match the pin (`mise install` or
`brew install swiftformat` at 0.61.1) before formatting, and never bulk-reformat with
an unpinned version.

**"dd"** → Run `SKIP_NOTARIZE=1 ./build.sh`, respond **"Eye eye Captain!"**
**"df"** → Run `./Scripts/quick-deploy.sh`, respond **"Eye eye Cap, fast deploying!"**
**"ds"** → Development ship workflow for the current changes, end to end: branch off master → format/lint + commit → review gate → push + open PR → babysit CI → address feedback → merge → pull master → `./Scripts/release-candidate.sh` from master for signed/notarized manual testing. Follow [`docs/agent-pr-workflow.md`](docs/agent-pr-workflow.md) and its invariants; risk-tier the babysit (auto-merge mechanical PRs, full babysit for logic/hot-path). Public distribution is a separate explicit release: `./Scripts/release-doctor.sh --ship && ./Scripts/release.sh <version>`.

Test targets: `Tests/KeyPathTests/` (target: `KeyPathTests`). Files in `Tests/KeyPathAppKitTests/` are NOT compiled. Snapshot tests in `Tests/KeyPathSnapshotTests/`.

## Poltergeist (Auto-Deploy)

`poltergeist start` / `poltergeist stop`. Use it only for focused single-agent Swift/UI iteration. **Stop before running parallel agents, broad tests, helper/service work, or release builds** — file change watchers cause SwiftPM lock contention and surprise app restarts.

## Linear

Personal workspace (`malpern@gmail.com`) via `/linear-switch personal`. Smirkhealth (`micah@smirkhealth.com`) via `/linear-switch smirkhealth`. Restart Claude Code after switching.

## Deep-Dive References

Load these on demand — don't need them every session:

| Topic | Doc |
|-------|-----|
| Release process | [`docs/release-process.md`](docs/release-process.md) |
| Help content writing | [`docs/help-content-philosophy.md`](docs/help-content-philosophy.md) |
| Pack dependency system | [`docs/architecture/pack-dependency-system.md`](docs/architecture/pack-dependency-system.md) |
| Overlay/mapper/gallery data flow | [`docs/architecture/overlay-data-flow.md`](docs/architecture/overlay-data-flow.md) |
| Peekaboo UI automation | [`docs/LLM_VISION_UI_AUTOMATION.md`](docs/LLM_VISION_UI_AUTOMATION.md) |
| All architecture guides | [`docs/architecture/`](docs/architecture/) |
| All ADRs | [`docs/adr/README.md`](docs/adr/README.md) |
| Feature docs | [`docs/features/`](docs/features/) |
