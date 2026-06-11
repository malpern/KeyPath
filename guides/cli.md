---
layout: default
title: "Command Line"
description: "Control KeyPath from Terminal with the keypath CLI"
theme: parchment
header_image: header-cli.png
permalink: /guides/cli/
---

# Command Line

KeyPath includes a CLI tool (`keypath-cli`) for managing your keyboard from Terminal. Opening KeyPath.app remains the primary way to launch KeyPath; the CLI is a separate terminal entry point.

For DMG installs, open KeyPath and choose **File > Install Command Line Tool**. That installs:

```bash
keypath-cli
```

The installed command points at the signed CLI inside `/Applications/KeyPath.app`, which is required for system install and repair commands that use bundled helper assets.

You can also run the bundled CLI directly:

```bash
/Applications/KeyPath.app/Contents/MacOS/keypath-cli system inspect
```

All commands support `--json` for machine-readable output, making them easy to use in scripts, Shortcuts, and automation tools.

---

## Quick reference

### Service control

```bash
keypath status                    # System health check
keypath start                     # Start the remapping service
keypath stop                      # Stop the remapping service
keypath restart                   # Restart the service
keypath logs                      # Show recent service logs
keypath service reload            # Hot-reload config without restart
```

### Layers

```bash
keypath layer list                # List all layers
keypath layer current             # Show the active layer
keypath layer switch nav          # Switch to a layer
keypath layer create window       # Create a new layer
keypath layer rename nav arrow    # Rename a layer
keypath layer delete window       # Delete a layer and its rules
```

### Key remapping

```bash
keypath remap caps_lock esc       # Remap a key (shortcut)
keypath unmap caps_lock           # Remove a mapping (shortcut)

keypath rule add caps_lock esc                    # Add a rule
keypath rule add --layer nav h left               # Layer-specific rule
keypath rule add --type tap-hold caps_lock esc lctl  # Tap-hold rule
keypath rule ensure caps_lock esc                 # Idempotent add
keypath rule list                                 # List all rules
keypath rule show caps_lock                       # Show a rule's details
keypath rule enable caps_lock                     # Enable a rule
keypath rule disable caps_lock                    # Disable a rule
keypath rule remove caps_lock                     # Remove a rule
```

### Collections

```bash
keypath collection list           # List all rule collections
keypath collection show "My Rules"  # Show collection details
keypath collection create "Gaming"  # Create a new collection
keypath collection enable "Gaming"  # Enable a collection
keypath collection disable "Gaming" # Disable a collection
keypath collection rename "Gaming" "FPS"  # Rename
keypath collection reorder "Gaming" 0     # Move to top
keypath collection duplicate "My Rules"   # Duplicate
keypath collection delete "Gaming"        # Delete
```

### Packs

```bash
keypath pack list                 # List available packs
keypath pack show vim-navigation  # Show pack details
keypath pack install vim-navigation  # Install a pack
keypath pack uninstall vim-navigation  # Uninstall
keypath pack configure vim-navigation --set key=value  # Configure
```

### Configuration

```bash
keypath config show               # Print the generated .kbd config
keypath config path               # Print the config file path
keypath config check              # Validate config with kanata --check
keypath config apply              # Regenerate config and reload
```

### Import / Export

```bash
keypath import karabiner ~/karabiner.json   # Import from Karabiner
keypath import collection rules.json        # Import a collection
keypath export all                          # Export all collections
keypath export collection "My Rules"        # Export one collection
```

### System

```bash
keypath system inspect                    # Inspect system state and repair plan
keypath system install --dry-run          # Preview installation work and blockers
keypath system repair --dry-run           # Preview repair work and manual permission actions
keypath system repair --open-permissions  # Open System Settings for permission blockers
keypath system repair                     # Fix auto-repairable services and components
keypath system uninstall                  # Remove everything
```

`system repair` can repair service/helper/component problems that KeyPath can
control. macOS permissions such as Accessibility and Input Monitoring still
require user approval; the CLI reports those as manual issues and can open the
appropriate System Settings pane with `--open-permissions`.

### Simulation

```bash
keypath simulate "caps h"         # Simulate a key sequence
```

---

## JSON output

Every command supports `--json` for machine-readable output:

```bash
keypath status --json
keypath layer current --json
keypath rule list --json
keypath layer list --json
```

This makes the CLI a first-class integration point for scripts, Shortcuts, Hammerspoon, and any other automation tool.

### Scripting examples

Check if service is running:

```bash
if keypath status --json | jq -e '.kanataRunning' > /dev/null 2>&1; then
    echo "KeyPath is running"
fi
```

Get the current layer in a script:

```bash
LAYER=$(keypath layer current)
echo "Active layer: $LAYER"
```

Conditional logic based on layer:

```bash
LAYER=$(keypath layer current)
case "$LAYER" in
    nav)    echo "Navigation mode" ;;
    window) echo "Window management mode" ;;
    base)   echo "Default mode" ;;
esac
```

### AppleScript

Use the CLI from AppleScript to query KeyPath state:

```applescript
-- Get the current layer
set currentLayer to do shell script "/usr/local/bin/keypath layer current"

-- Conditional logic based on layer
if currentLayer is "nav" then
    display notification "Navigation layer active" with title "KeyPath"
end if

-- Check if service is running
try
    do shell script "/usr/local/bin/keypath status --json"
    -- service is reachable
on error
    -- service is down
end try
```

Send actions to KeyPath from AppleScript:

```applescript
-- Launch an app through KeyPath
do shell script "open 'keypath://launch/Obsidian'"

-- Switch layers
do shell script "/usr/local/bin/keypath layer switch nav"
```

### Hammerspoon

Use the CLI alongside the [KeyPath.spoon]({{ '/guides/hammerspoon/' | relative_url }}):

```lua
-- Query current layer via CLI (synchronous)
local layer = hs.execute("/usr/local/bin/keypath layer current"):gsub("%s+$", "")

-- Get all layers as JSON
local output = hs.execute("/usr/local/bin/keypath layer list --json")
local layers = hs.json.decode(output)
```

For reactive layer-change events, use the Spoon's `onLayerChange` callback instead of polling the CLI.

---

## Shell completions

Install tab completions for your shell:

```bash
keypath completions install        # Auto-detect shell
keypath completions install-man    # Install man pages
```

Or generate completions manually:

```bash
keypath completions zsh > ~/.zsh/completions/_keypath
keypath completions bash > /etc/bash_completion.d/keypath
keypath completions fish > ~/.config/fish/completions/keypath.fish
```

---

## Help

```bash
keypath --help                     # Top-level help
keypath rule --help                # Help for a subcommand group
keypath help-topics examples       # Curated workflow examples
keypath help-topics examples rule  # Examples for a specific topic
keypath help-topics schemas        # JSON schema discovery
```

---

## Related guides

- **[Siri & Shortcuts]({{ '/guides/siri-and-shortcuts/' | relative_url }})** — Voice control and Shortcuts automations
- **[Hammerspoon]({{ '/guides/hammerspoon/' | relative_url }})** — Layer-aware desktop automation
- **[Action URI Reference]({{ '/guides/action-uri-reference/' | relative_url }})** — Deep link reference for `keypath://` URIs
