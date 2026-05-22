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

Git guardrail hooks in `.claude/settings.json` block: commits on master, force-push to master, `reset --hard`, `clean -f`.

**Kanata fork safety:** The kanata submodule (`External/kanata`) tracks `keypath/bundled` on `malpern/kanata`. Treat `keypath/bundled` like master — **never force-push** to it. Before pushing to any remote branch in the fork, verify the push is a fast-forward: `git log --oneline <source>..<target>`. If commits would be lost, cherry-pick instead. The `main` branch in kanata-pr may diverge from `keypath/bundled` — they are NOT interchangeable.

## Build & Deploy

```bash
./build.sh                        # Canonical build (SKIP_NOTARIZE=1 for local dev)
./Scripts/quick-deploy.sh         # Fast debug deploy
swift test                        # All tests (~532 tests, <5s)
swiftformat Sources/ Tests/ --swiftversion 5.9
swiftlint --fix --quiet
```

**"dd"** → Run `SKIP_NOTARIZE=1 ./build.sh`, respond **"Eye eye Captain!"**
**"df"** → Run `./Scripts/quick-deploy.sh`, respond **"Eye eye Cap, fast deploying!"**

Test targets: `Tests/KeyPathTests/` (target: `KeyPathTests`). Files in `Tests/KeyPathAppKitTests/` are NOT compiled. Snapshot tests in `Tests/KeyPathSnapshotTests/`.

## Poltergeist (Auto-Deploy)

`poltergeist start` / `poltergeist stop`. **Stop before running parallel agents** — file change watchers cause SwiftPM lock contention.

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
