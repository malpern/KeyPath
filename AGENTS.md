# AGENTS.md

These instructions apply to all Codex sessions in this repository.

## Web Search Tooling
- Always use `web_search_request` for any web lookups.
- Never call the deprecated `tools.web_search` tool. Treat it as unavailable.
- Do not pass the CLI flag `--search`. Rely on the feature flag or config instead.

Rationale: older CLI/tooling may still expose `tools.web_search`, which prints a deprecation warning. Enforcing `web_search_request` avoids the warning and keeps behavior consistent.

## General
- Keep diffs minimal and focused. Preserve directory layout and script entry points.
- Update docs/tests when behavior or commands change.

## Architecture & Patterns

### InstallerEngine Façade
- **Use `InstallerEngine`** for ANY system modification task:
  - Installation: `InstallerEngine().run(intent: .install, using: broker)`
  - Repair/Fix: `InstallerEngine().run(intent: .repair, using: broker)`
  - Uninstall: `InstallerEngine().uninstall(...)`
  - System Check: `InstallerEngine().inspectSystem()`
- **Do NOT use**:
  - `KanataManager` for installation/repair (it's for runtime coordination only).
  - `LaunchDaemonInstaller` directly (it's an internal implementation detail).
  - `WizardAutoFixer` directly (superseded by Engine).

### Permissions
- **Always use `PermissionOracle.shared`**.
- Never call `IOHIDCheckAccess` directly.
- Never check TCC database directly.

### Testing
- **Mock Time**: Do not use `Thread.sleep`. Use `Date` overrides or mock clocks.
- **Environment**: Use `KEYPATH_USE_INSTALLER_ENGINE=1` (default now) for tests.

## Available External Tools

These CLI tools are available for agents to use on-demand. Do not add them as MCPs - just call them directly when needed.

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
# Example: AI-driven workflow
peekaboo see "What app is focused?"
open "keypath://layer/vim"
peekaboo type "Hello world"
peekaboo hotkey "cmd+s"
```

See `docs/LLM_VISION_UI_AUTOMATION.md` for detailed architecture.
