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
- **Configuration**: User config at `~/Library/Application Support/KeyPath/keypath.kbd`

### Key Manager Classes
| Class | Responsibility |
|-------|---------------|
| `InstallerEngine` | **The Façade** - all install/repair/uninstall + system inspection |
| `KanataManager` | Runtime Coordinator - service orchestration (NOT ObservableObject) |
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

### Test Seams
- ❌ Never call real `pgrep` in tests → Tests will deadlock
- ✅ Use `KeyPathTestCase` base class (sets up `VHIDDeviceManager.testPIDProvider`)
- ✅ Keep tests fast (<5s total) - use backdated timestamps, not real sleeps

## 📜 Architecture Decision Records

Full records in [`docs/adr/`](docs/adr/README.md). Key decisions:

| ADR | Summary |
|-----|---------|
| [001](docs/adr/adr-001-oracle-pattern.md), [006](docs/adr/adr-006-apple-api-priority.md) | PermissionOracle - Apple API authoritative |
| [015](docs/adr/adr-015-installer-engine.md) | InstallerEngine is the façade for all install/repair |
| [023](docs/adr/adr-023-no-config-parsing.md) | Never parse Kanata configs - use TCP and simulator |
| [026](docs/adr/adr-026-validation-ordering.md) | Validate components before service status |
| [022](docs/adr/adr-022-no-concurrent-pgrep.md) | No concurrent pgrep in TaskGroups |
| [018](docs/adr/adr-018-helper-protocol-duplication.md) | HelperProtocol.swift must be identical in both locations |

## 📦 Feature Documentation

| Feature | Documentation |
|---------|--------------|
| RuleCollection Pattern | [`docs/architecture/rule-collection-pattern.md`](docs/architecture/rule-collection-pattern.md) |
| Action URI System | [`docs/ACTION_URI_SYSTEM.md`](docs/ACTION_URI_SYSTEM.md) |
| Window Management | [`docs/features/window-management.md`](docs/features/window-management.md) |

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
swift build                    # Development
./Scripts/build.sh             # Production (local, SKIP_NOTARIZE=1 for quick)
./Scripts/build-and-sign.sh    # Release (signed + notarized)
```

### Quick Deploy Shortcut
When the user says **"dd"**, immediately:
1. Run `SKIP_NOTARIZE=1 ./Scripts/build.sh` to build, sign, and deploy to `/Applications`
2. Respond with **"Eye eye Captain!"**

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
