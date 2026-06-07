---
name: keypath-cli
description: >
  Configure KeyPath keyboard remapping via the keypath CLI. Use when the user
  wants to remap keys, add shortcuts, configure tap-hold or home row mods,
  install/uninstall packs, manage layers, import from Karabiner, or control
  the KeyPath service. Triggers on: remap key, keyboard shortcut, tap-hold,
  home row mods, caps lock remap, key mapping, layer, pack install, Kanata,
  keypath CLI, keyboard configuration.
metadata:
  author: KeyPath Team
  version: "1.0"
---

Use the `keypath` CLI to manage keyboard remapping. Always prefer the CLI over
editing config files directly.

## Output Mode

- Always pass `--json` when you need to parse the result
- When piped (non-TTY), output is JSON automatically
- Use `--quiet` to suppress stderr decoration (spinners, progress)
- Use `--dry-run` to preview any mutation before committing
- For system install/repair, use the app-bundled CLI or the app-installed
  `/usr/local/bin/keypath-cli` shim. Standalone debug/Homebrew formula binaries
  are not authoritative for bundle-relative helper assets.

## Command Reference

### Status & Health
```bash
keypath service status --json       # Full system health check
keypath service start               # Start Kanata service and verify runtime health
keypath service stop                # Stop Kanata service and verify it stopped
keypath service restart             # Restart Kanata service; may fail if macOS requires authorization
keypath service reload              # Reload config without restart
```

### Rules (Custom Key Remaps)
```bash
keypath rule list --json            # List all custom rules
keypath rule add <input> --action key=<output>  # Simple remap
keypath rule add <input> --action key=<tap> --behavior tap-hold --hold <hold> --timeout 200  # Tap-hold
keypath rule remove <input> --apply # Remove and reload
keypath rule enable <input> --apply # Enable a disabled rule
keypath rule disable <input>        # Disable without removing
keypath rule show <input> --json    # Show rule details
keypath rule ensure <input> <output> [--hold <hold>] --apply  # Idempotent: create or no-op
keypath rule ensure --from-file rules.json --apply  # Batch: ensure multiple rules atomically
```

### Batch Ensure (Preferred for Agents)
Create a JSON file with an array of rule specs, then apply all at once:
```json
[
  {"input": "caps", "output": "esc"},
  {"input": "a", "output": "a", "hold": "lctl", "timeout": 200},
  {"input": "s", "output": "s", "hold": "lalt", "timeout": 200}
]
```
```bash
keypath rule ensure --from-file rules.json --apply --json
```
Returns `{created, updated, unchanged}` counts plus per-rule actions. Only one config
regeneration at the end (not N times).

### Rule Mutations — Canonical Workflow
After any rule change, apply and verify:
```bash
keypath rule add caps --action key=esc --on-conflict replace
keypath config apply --json         # Returns changeset with all active rules/collections
keypath service status --json       # Verify system is operational
```

### Collections (Built-in Rule Sets)
```bash
keypath collection list --json      # List all collections with enabled status
keypath collection enable <name>    # Enable a collection
keypath collection disable <name>   # Disable a collection
keypath collection show <name> --json
```

### Packs (Gallery Packs)
```bash
keypath pack list --json            # All packs with install status
keypath pack show <slug> --json     # Pack details, bindings, dependencies
keypath pack install <slug> --apply # Install and reload
keypath pack install <slug> --setting holdTimeout=200 --apply  # With quick settings
keypath pack uninstall <slug> --apply
keypath pack configure <slug> --setting holdTimeout=250 --apply  # Update settings
```

Pack names use slugs: `vim-navigation`, `home-row-mods`, `caps-lock-to-escape`, etc.

### Layers
```bash
keypath layer list --json           # List defined layers
keypath layer create <name>         # Create a new layer
keypath layer switch <name>         # Switch active layer
keypath layer delete <name>
```

### Config Management
```bash
keypath config show                 # Show current config file
keypath config path                 # Print config file path
keypath config check --json         # Validate config (returns configPath, configBytes, error details)
keypath config apply --json         # Regenerate + reload (returns changeset with active rules/collections)
```

### System Management
```bash
keypath system inspect --json             # Check system state, repair plan, and issues
keypath system install --dry-run --json   # Preview installation work and blockers
keypath system repair --dry-run --json    # Preview repair work and manual permission actions
keypath system repair --open-permissions  # Open System Settings for permission blockers
keypath system repair                     # Fix auto-repairable services and components
keypath system uninstall                  # Remove all services
```

Permission repair boundary: the CLI can diagnose missing Accessibility/Input
Monitoring grants and open the matching System Settings pane, but macOS still
requires the user to approve those permissions manually.

### Import/Export
```bash
keypath export all --json           # Export all collections
keypath export collection <name> --json
keypath import collection < file.json
keypath import karabiner < karabiner.json  # Migrate from Karabiner-Elements
```

### Discovery
```bash
keypath help-topics schemas         # List all action types and behaviors
keypath help-topics examples        # Common usage examples per noun
keypath completions values pack     # List completable pack slugs
keypath completions values collection  # List collection names
keypath completions values rule     # List rule input keys
keypath completions values layer    # List layer names
```

## Conflict Resolution

Use `--on-conflict` for declarative handling:
- `fail` (default) — error if rule exists
- `replace` — overwrite existing rule
- `skip` — no-op if rule exists
- `merge` — merge compatible behaviors

For idempotent operations, use `--on-conflict replace`.

## Error Handling

Exit codes:
| Code | Meaning |
|------|---------|
| 0 | Success |
| 2 | Usage error (bad arguments) |
| 3 | Validation error |
| 4 | Conflict |
| 5 | Not found |
| 6 | Service unreachable |
| 7 | Permission blocked |
| 8 | Kanata config invalid |

When an error includes a `hint` field, it contains a runnable command to fix the issue.

## Important Rules

- After any mutation, run `keypath config apply --json` then verify with `keypath service status --json`
- Use `--dry-run` before destructive operations
- Use `--on-conflict replace` for idempotent updates
- Never use `keypath service logs --follow` — it blocks indefinitely
- Pack-managed collections cannot be toggled independently — uninstall the pack first
- The `simulate` command requires the bundled `kanata-simulator` binary — skip if not installed
- Use `keypath simulate a b --json` for simple tap sequences
- Use `keypath simulate --raw 'd:f t:100 d:j t:50 u:j t:50 u:f' --json` for overlapping press/release timelines such as Home Row Mods opposite-hand QA
- Use `keypath simulate --sim-file ./scenario.sim --json` for reusable raw simulator scripts
