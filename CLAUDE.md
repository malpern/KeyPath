# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features a SwiftUI frontend and a LaunchDaemon architecture for reliable system-level key remapping.

## High-Level Architecture

```
KeyPath.app (SwiftUI) → InstallerEngine → LaunchDaemon/PrivilegedHelper
          ↓                    ↓
    KanataManager      SystemContext (State)
          ↓
   TCP/Runtime Control
```

### Core Components
- **KeyPath.app**: SwiftUI application with Liquid Glass UI (macOS 15+)
- **InstallerEngine**: Unified façade for installation, repair, and system inspection
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **Configuration**: User config at `~/.config/keypath/keypath.kbd`

### Key Manager Classes
| Class | Responsibility |
|-------|---------------|
| `SystemInspector` | **Pure function** - SystemContext → (WizardSystemState, [WizardIssue]) |
| `WizardRouter` | **Pure function** - state + issues → WizardPage (sole routing logic) |
| `InstallerEngine` | **The Façade** - all install/repair/uninstall + system inspection |
| `RuntimeCoordinator` | Runtime Coordinator - service orchestration (NOT ObservableObject) |
| `ServiceLifecycleCoordinator` | **Start/stop/restart Kanata** - the ONLY entry point for service lifecycle |
| `KanataDaemonService` | **LaunchDaemon lifecycle** - register/unregister via SMAppService, status polling |
| `ServiceHealthChecker` | **Health checks** - the ONLY way to check if kanata is running (launchctl + TCP) |
| `ConfigReloadCoordinator` | **Config reload** - TCP-based reload after rule changes, safety checks |
| `KanataViewModel` | UI Layer (MVVM) - @Published properties for SwiftUI |
| `ConfigurationService` | Config file management |
| `PermissionOracle` | **🔮 CRITICAL** - Single source of truth for permissions |

## 🔮 PermissionOracle (CRITICAL - DO NOT BREAK)

**THE FUNDAMENTAL RULE: Apple APIs ALWAYS take precedence over TCC database**

1. **APPLE APIs** (IOHIDCheckAccess) → **AUTHORITATIVE**
   - `.granted` / `.denied` → TRUST THIS RESULT
   - `.unknown` → Proceed to TCC fallback
2. **TCC DATABASE** → Fallback for `.unknown` cases only

See [ADR-001](docs/adr/adr-001-oracle-pattern.md) and [ADR-006](docs/adr/adr-006-apple-api-priority.md).

## 🎯 Validation Architecture

**Validation is pull-based via `InstallerEngine.inspectSystem()`**:
```swift
let engine = InstallerEngine()
let context = await engine.inspectSystem() // Pure value struct
if context.permissions.inputMonitoring != .granted { ... }
```

**Validation Order** (see [ADR-026](docs/adr/adr-026-validation-ordering.md)):
1. Conflicts → 2. Components → 3. Permissions → 4. Service Status

## 🚫 Critical Anti-Patterns

### Permission Detection
- ❌ Never bypass `PermissionOracle.shared`
- ❌ Never check permissions from root process

### Service Management
- ❌ Don't use KanataManager for installation → Use `InstallerEngine`
- ❌ Don't manually call launchctl → Use `InstallerEngine`
- ❌ Don't mark Kanata healthy from restart-window timing alone
- ❌ Don't return installer action success before runtime readiness (`running + TCP responding`) is verified
- ✅ Treat `SMAppService.status == .enabled` as registration state, not runtime liveness

### Health Checks & Service Lifecycle
- ❌ Don't roll your own `pgrep`/`launchctl` to check if kanata is running → Use `ServiceHealthChecker`
- ❌ Don't call `KanataDaemonService.isDaemonRunning()` directly from UI/coordinator code → Use `ServiceHealthChecker.checkKanataServiceHealth()`
- ❌ Don't start/stop/restart kanata from anywhere except `ServiceLifecycleCoordinator`
- ❌ Don't send TCP reload commands directly → Use `ConfigReloadCoordinator.triggerConfigReload()`
- ❌ Don't skip TCP reload after config file changes — this causes kanata to run stale config

### Test Seams
- ❌ Never call real `pgrep` in tests → Tests will deadlock
- ✅ Use `KeyPathTestCase` base class (sets up `VHIDDeviceManager.testPIDProvider`)
- ✅ Keep tests fast (<5s total) - use backdated timestamps, not real sleeps

### Watchdog / Timeout Handlers
- ❌ Never use a specific service identifier (e.g., `.component(.kanataService)`) in generic timeout catch blocks — it creates false alerts for the wrong service
- ❌ Never call `SMAppService.status` repeatedly in a hot path — it does synchronous IPC and can block for 10-30+ seconds under load
- ✅ Cache `isHelperInstalled()` and `getHelperVersion()` results within a single validation cycle
- ✅ Use `.validationTimeout` for generic watchdog failures

### Apple Framework IPC
- ❌ Don't assume `SMAppService.status` is fast — it's synchronous IPC to the ServiceManagement daemon
- ❌ Don't call `nonisolated async` actor methods repeatedly if they do synchronous blocking IPC — each call involves actor hop + thread scheduling + IPC round-trip
- ✅ Call once, cache locally, pass the result down

## 🐛 Bug Investigation Protocol

When investigating runtime bugs (false alerts, service failures, unexpected state):

1. **Check actual logs first** — `~/Library/Logs/KeyPath/keypath-debug.log` has timestamped evidence. Don't theorize before reading logs.
2. **Trace the full code path** — Follow the issue from UI trigger back through the call chain to the data source. Map every actor hop and async boundary.
3. **Identify ALL layers** — Most bugs have a proximate cause (wrong identifier) and a deeper cause (redundant IPC). Fix both.
4. **Verify the theory against timestamps** — Align log timestamps with code paths to confirm which calls are slow vs. fast.
5. **Document in `docs/bugs/`** — Write up the root cause chain, evidence, and fixes for future reference.

Past investigations: [`docs/bugs/`](docs/bugs/)

## ⌨️ Keyboard Visualization Principle
- **Geometry follows selected `PhysicalLayout`** (user-selected layout ID).
- **Labels follow selected `LogicalKeymap`** (user-selected keymap).
- Do **not** expose a UI toggle for this; treat it as a single consistent rule.

## 📜 Architecture Decision Records

Full records in [`docs/adr/`](docs/adr/README.md). Key decisions:

| ADR | Summary |
|-----|---------|
| [001](docs/adr/adr-001-oracle-pattern.md), [006](docs/adr/adr-006-apple-api-priority.md) | PermissionOracle - Apple API authoritative |
| [015](docs/adr/adr-015-installer-engine.md) | InstallerEngine is the façade for all install/repair |
| [023](docs/adr/adr-023-no-config-parsing.md) | Never parse Kanata configs - use TCP and simulator |
| [026](docs/adr/adr-026-validation-ordering.md) | Validate components before service status |
| [031](docs/adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md) | Installer success requires verified runtime readiness; stale recovery bypasses throttle |
| [022](docs/adr/adr-022-no-concurrent-pgrep.md) | No concurrent pgrep in TaskGroups |
| [018](docs/adr/adr-018-helper-protocol-duplication.md) | HelperProtocol.swift must be identical in both locations |

## 📦 Feature Documentation

| Feature | Documentation |
|---------|--------------|
| RuleCollection Pattern | [`docs/architecture/rule-collection-pattern.md`](docs/architecture/rule-collection-pattern.md) |
| Action URI System | [`docs/ACTION_URI_SYSTEM.md`](docs/ACTION_URI_SYSTEM.md) |
| Window Management | [`docs/features/window-management.md`](docs/features/window-management.md) |

## 📖 Help Content Philosophy

Help articles live in `Sources/KeyPathAppKit/Resources/*.md` and render in the in-app Help Browser (`HelpBrowserView.swift`). All help content follows this layered structure:

### Content hierarchy (this order matters)

1. **User goals and problems first** — Every article opens with the problem the user has, not the feature name. "Stop reaching for the Dock" not "Action URI System". "Every shortcut forces your fingers off the home row" not "Home row mods turn keys into dual-role keys."
2. **KeyPath UI and how to accomplish the goal** — Show the user how to do it in the app. Use ASCII mockups labeled as screenshots, reference actual tab names, buttons, and pickers. Step-by-step instructions tied to what they see on screen.
3. **Mechanical keyboard context (secondary)** — Introduce insider concepts (layers, tap-hold, Kanata variants, Chordal Hold, etc.) only after the user understands what they're trying to accomplish and how to do it in KeyPath. Position these in "Advanced" or "Technical Details" sections near the end.
4. **Rich external resources** — Every article ends with curated links to community references, tool docs, learning resources, and hardware. Use `↗` suffix for external links.

### Content rules

- **Titles are user goals**, not feature names: "Shortcuts Without Reaching" not "Home Row Mods", "One Key, Multiple Actions" not "Tap-Hold & Tap-Dance", "Launching Apps" not "Action URIs"
- **Cross-links use goal-oriented names** throughout all articles
- **ASCII UI mockups** labeled as "Screenshot — [description]:" show actual KeyPath UI (inspector tabs, pickers, drawers, rule editors) — not just keyboard diagrams
- **Watercolor header images** (`header-*.png`) at top of each article, rendered with `mix-blend-mode: multiply` on parchment background
- **Watercolor divider images** (`decor-divider.png`) between sections, blending into background (no white boxes)
- **Internal links** use `help:resource-name` scheme (e.g., `[Shortcuts Without Reaching](help:home-row-mods)`)
- **Technical reference docs** (like Action URI Reference) are separate from user-facing guides

### Anti-patterns to avoid

- ❌ **Don't lead with jargon** — "Hyper key", "tap-hold-release-keys", "deflayer", "CAGS layout" should never be the first thing a user reads in a section
- ❌ **Don't write feature-centric content** — "KeyPath supports 4 tap-hold variants" is engineer-speak. Write "Here's how to make one key do two things" instead
- ❌ **Don't skip the UI** — If there's a button, tab, slider, or picker involved, show it (ASCII mockup or step-by-step). Don't just say "configure it in settings"
- ❌ **Don't make the user learn Kanata to use KeyPath** — Kanata config syntax belongs in the "From Kanata" switching guide and technical references, not in user-facing how-to articles
- ❌ **Don't mix UI guides with technical references** — App launching UI guide and Action URI deep-link reference are separate articles, not one article trying to serve both audiences
- ❌ **Don't use stale tab/button names** — The UI has specific names: "Custom Rules" tab, "Key Mapper" tab, "Launchers" tab, "Add Shortcut" button, gear icon for settings shelf. Use the real names.
- ❌ **Don't rely solely on watercolor illustrations** — They set the aesthetic tone but don't teach. Use ASCII mockups of the actual KeyPath UI to show what the user will see

## 🤖 External Tools: Peekaboo for UI Automation

For AI-driven UI automation (screenshots, clicks, typing, scrolling), use **Peekaboo** alongside KeyPath. KeyPath handles keyboard remapping; Peekaboo handles GUI automation. Unix philosophy - compose small tools.

**Installation:**
```bash
brew install steipete/tap/peekaboo
```

**Available Commands:**
| Command | Purpose |
|---------|---------|
| `peekaboo see` | Screenshot + AI analysis ("What buttons are visible?") |
| `peekaboo click` | Click by element ID, label, or coordinates |
| `peekaboo type` | Enter text with pacing options |
| `peekaboo scroll` | Scroll in any direction |
| `peekaboo hotkey` | Trigger keyboard shortcuts |
| `peekaboo app` | Launch, quit, switch apps |
| `peekaboo window` | Move/resize/focus windows |
| `peekaboo menu` | Interact with app menus |

**Composing with KeyPath:**
```bash
# Take screenshot, analyze, then trigger KeyPath action
peekaboo see "Find the search field"
open "keypath://layer/vim"  # Switch to vim layer
peekaboo type "search query"
```

**Why not build our own?** Peekaboo uses the same AX/CGS APIs we have, but with 25+ polished tools. steipete maintains it actively. See `docs/LLM_VISION_UI_AUTOMATION.md` for architecture details.

## Build Commands

```bash
./Scripts/quick-deploy.sh      # Incremental local dev (fast, deploys to /Applications)
./build.sh                     # Canonical build (sign + notarize; SKIP_NOTARIZE=1 for faster local)
./Scripts/build-and-sign.sh    # Release (signed + notarized, legacy entry)
```

### Quick Deploy Shortcuts
When the user says **"dd"**, immediately:
1. Run `SKIP_NOTARIZE=1 ./build.sh` to build, sign, and deploy to `/Applications`
2. Respond with **"Eye eye Captain!"**

When the user says **"df"**, immediately:
1. Run `./Scripts/quick-deploy.sh` for a fast debug deploy to `/Applications`
2. Respond with **"Eye eye Cap, fast deploying!"**

## Linear Workspace Management

KeyPath development uses Linear for issue tracking with two workspaces:
- **Personal**: malpern@gmail.com (linear-personal MCP server)
- **Smirkhealth**: micah@smirkhealth.com (linear-smirkhealth MCP server)

### Switching Workspaces
Use the `/linear-switch` skill to change workspaces:

```bash
/linear-switch personal      # Switch to Personal workspace
/linear-switch smirkhealth   # Switch to Smirkhealth workspace
/linear-switch status        # Check current workspace
```

**Note**: After switching, you must restart Claude Code by typing `/exit` and starting a new session for the change to take effect.

### Manual Terminal Commands
Alternatively, use these terminal commands directly:
```bash
linear-personal      # Activate Personal workspace
linear-smirkhealth   # Activate Smirkhealth workspace
linear-which         # Show current workspace
```

Full documentation: `~/.claude/LINEAR_SWITCHING.md`

### Poltergeist (Auto-Deploy)
```bash
poltergeist start    # Watch + auto-deploy on save (~2s)
poltergeist stop     # Stop watching
```

**IMPORTANT: Stop Poltergeist before running parallel agents!**

Poltergeist watches for file changes and triggers builds. When multiple agents write files simultaneously, this causes SwiftPM lock contention (only one build at a time allowed).

**Parallel Agent Workflow:**
```bash
# 1. Stop auto-build to prevent lock contention
poltergeist stop

# 2. Launch parallel agents (they edit code without building)
# ... agents work simultaneously ...

# 3. Manual verification after all agents complete
swift build && swift test

# 4. Commit & push
git add -A && git commit && git push

# 5. Resume auto-deploy for normal dev work
poltergeist start
```

## Test Commands

```bash
swift test
KEYPATH_USE_SUDO=1 swift test   # With sudo (requires ./Scripts/dev-setup-sudoers.sh)
```

## Code Quality

```bash
swiftformat Sources/ Tests/ --swiftversion 5.9
swiftlint --fix --quiet
```
