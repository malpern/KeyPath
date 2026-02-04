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

### Keyboard Visualization
- **Geometry follows selected `PhysicalLayout`** (user-selected layout ID).
- **Labels follow selected `LogicalKeymap`** (user-selected keymap).
- Do **not** add a UI toggle for this; treat it as a single consistent rule.

### Testing
- **Mock Time**: Do not use `Thread.sleep`. Use `Date` overrides or mock clocks.
- **Environment**: Use `KEYPATH_USE_INSTALLER_ENGINE=1` (default now) for tests.

### Accessibility (CRITICAL)
- **ALL interactive UI elements MUST have `.accessibilityIdentifier()`**
- **Required for:** Button, Toggle, Picker, and custom interactive components
- **Enforcement:** Pre-commit hook + CI check (currently warning only)
- **Verification:** Run `python3 Scripts/check-accessibility.py` before committing
- **See:** `ACCESSIBILITY_COVERAGE.md` for complete reference
- **Rationale:** Enables automation (Peekaboo, XCUITest) and ensures testability

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

**Workflow tip:** Run `poltergeist start` at session start. After any Swift file edit, the app automatically rebuilds, deploys to /Applications, and restarts. No manual steps needed.

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
poltergeist start                    # Ensure auto-rebuild is running
# ... make code changes ...
poltergeist wait keypath             # Wait for build to complete
peekaboo see "Is the KeyPath app running?" # Check UI state
open "keypath://layer/vim"           # Trigger keyboard action
peekaboo type "Hello world"          # Type into focused app
peekaboo hotkey "cmd+s"              # Save
```

**Recommended agent workflow:**
1. `poltergeist start` at session start (keeps builds fresh)
2. Make code edits
3. `poltergeist wait keypath` before testing
4. Use Peekaboo for UI verification
5. Use KeyPath URL scheme for keyboard actions

See `docs/LLM_VISION_UI_AUTOMATION.md` for detailed architecture.
