---
layout: default
title: "Running Scripts"
description: "Trigger shell scripts, AppleScript, Python, and more from your keyboard"
theme: parchment
permalink: /guides/script-execution/
---

# Running Scripts

KeyPath can run scripts when you press a key — shell scripts, AppleScript, Python, Ruby, Perl, or Lua. This lets you trigger custom automation from your keyboard: deploy a project, toggle system settings, control apps that don't have keyboard shortcuts, or anything else a script can do.

Script execution is powerful, so it's off by default and guarded by a confirmation system. This guide covers how to enable it, how to use it, and how the security model works.

---

## Enabling script execution

Scripts are disabled by default. To turn them on:

1. Open **KeyPath Settings**
2. Go to the **Script Execution** section
3. Toggle **Enable Script Execution**
4. Confirm in the security dialog

<!-- Screenshot: Settings showing the Script Execution toggle -->
![Screenshot — Script Execution settings]({{ '/images/help/placeholder-settings-script-execution.png' | relative_url }})

The confirmation dialog explains what scripts can do — run commands, access files, and make network requests. This is a one-time decision; you can disable it again at any time.

---

## Running your first script

Create a simple script:

```bash
#!/bin/bash
# ~/scripts/hello.sh
osascript -e 'display notification "Hello from KeyPath!" with title "Script"'
```

Make it executable:

```bash
chmod +x ~/scripts/hello.sh
```

Now trigger it from KeyPath using an action URI in your Kanata config:

```lisp
(push-msg "script:~/scripts/hello.sh")
```

Or test it from Terminal:

```bash
open "keypath://script/~/scripts/hello.sh"
```

The first time a script runs, KeyPath shows a confirmation dialog with the script path. You can check "Don't show again" to skip the dialog for future scripts.

<!-- Screenshot: Script confirmation dialog showing path and warning -->
![Screenshot — First-run script confirmation]({{ '/images/help/placeholder-script-confirmation.png' | relative_url }})

---

## Supported script types

KeyPath detects the script type by file extension and runs it with the appropriate interpreter:

| Extension | Interpreter | Notes |
|-----------|------------|-------|
| `.sh` | `/bin/bash` | Standard shell scripts |
| `.bash` | `/bin/bash` | Explicit Bash scripts |
| `.zsh` | `/bin/zsh` | Zsh scripts (macOS default shell) |
| `.py` | `/usr/bin/python3` | Python 3 (probes common paths) |
| `.rb` | `/usr/bin/ruby` | Ruby (ships with macOS) |
| `.pl` | `/usr/bin/perl` | Perl (ships with macOS) |
| `.lua` | `/usr/local/bin/lua` | Lua (Homebrew or manual install) |
| `.scpt` | Compiled AppleScript | Pre-compiled AppleScript bundles |
| `.applescript` | Text AppleScript | Plain-text AppleScript source |

Scripts without a recognized extension are executed directly (must be executable).

---

## AppleScript integration

AppleScript is particularly useful because it can control other Mac apps:

```applescript
-- ~/scripts/toggle-dark-mode.applescript
tell application "System Events"
    tell appearance preferences
        set dark mode to not dark mode
    end tell
end tell
```

```lisp
;; In your Kanata config:
(push-msg "script:~/scripts/toggle-dark-mode.applescript")
```

More examples:

```applescript
-- Open a specific URL in Safari
tell application "Safari" to open location "https://github.com"

-- Resize the frontmost window
tell application "System Events"
    tell process (name of first application process whose frontmost is true)
        set size of window 1 to {1200, 800}
    end tell
end tell

-- Toggle Do Not Disturb (macOS 12+)
do shell script "shortcuts run 'Toggle Focus'"
```

---

## Practical examples

### Deploy a project

```bash
#!/bin/bash
# ~/scripts/deploy.sh
cd ~/Projects/myapp
git push origin main
osascript -e 'display notification "Deployed!" with title "Deploy"'
```

### Toggle Bluetooth

```bash
#!/bin/bash
# ~/scripts/toggle-bluetooth.sh
if blueutil --power | grep -q "1"; then
    blueutil --power 0
    osascript -e 'display notification "Bluetooth off" with title "Bluetooth"'
else
    blueutil --power 1
    osascript -e 'display notification "Bluetooth on" with title "Bluetooth"'
fi
```

### Open a project in your editor

```bash
#!/bin/bash
# ~/scripts/open-project.sh
open -a "Visual Studio Code" ~/Projects/myapp
```

### Quick note to clipboard

```python
#!/usr/bin/env python3
# ~/scripts/timestamp-clip.py
import subprocess, datetime
ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
subprocess.run(["pbcopy"], input=ts.encode())
```

---

## The URI format

Two equivalent ways to reference a script:

| Context | Syntax | Example |
|---------|--------|---------|
| Kanata config | Shorthand | `script:~/scripts/hello.sh` |
| Deep link | Full URI | `keypath://script/~/scripts/hello.sh` |

Tilde (`~`) is expanded to your home directory. Paths with spaces work when URL-encoded in the full URI format.

---

## Security model

Script execution has three layers of protection:

### 1. Global toggle

Script execution is off by default. Nothing runs until you explicitly enable it in Settings. You can disable it at any time to block all script execution instantly.

### 2. First-run confirmation

The first time any script runs, KeyPath shows a confirmation dialog:

```
  ┌─────────────────────────────────────────────────┐
  │  ⚠️  Script Execution                           │
  │                                                  │
  │  ~/scripts/hello.sh                              │
  │                                                  │
  │  This script can:                                │
  │  • Execute system commands                       │
  │  • Read and write files                          │
  │  • Access the network                            │
  │  • Control other applications                    │
  │                                                  │
  │  ☐ Don't show this warning again                 │
  │                                                  │
  │          [ Cancel ]  [ Run Script ]              │
  └─────────────────────────────────────────────────┘
```

Check "Don't show again" only if you trust all scripts you'll run. This bypasses the dialog for future scripts.

### 3. Execution log

KeyPath logs every script execution — path, timestamp, success/failure, and any errors. View the log in **Settings > Script Execution > View Execution Log**.

<!-- Screenshot: Execution log showing recent script runs -->
![Screenshot — Script execution log]({{ '/images/help/placeholder-script-execution-log.png' | relative_url }})

### What scripts can't do

- Scripts run with your user permissions — they can't do anything you couldn't do in Terminal
- Scripts have a 60-second timeout — long-running processes are killed
- Scripts don't have access to KeyPath's internal state beyond what the action URI system provides

---

## Using scripts with keyboard shortcuts

The most common pattern: bind a script to a key on a navigation layer or through the Quick Launcher.

### On a navigation layer

```lisp
;; In your Kanata config, on the nav layer:
(push-msg "script:~/scripts/deploy.sh")
```

### Through the CLI

```bash
# Trigger a script directly
open "keypath://script/~/scripts/hello.sh"
```

### Through Shortcuts or Siri

Use the "Send KeyPath Action" Shortcut with the URI `keypath://script/~/scripts/hello.sh`.

---

## Related guides

- **[Action URI Reference]({{ '/guides/action-uri-reference/' | relative_url }})** — Full reference for all `keypath://` action types
- **[Command Line]({{ '/guides/cli/' | relative_url }})** — CLI reference
- **[Siri & Shortcuts]({{ '/guides/siri-and-shortcuts/' | relative_url }})** — Trigger scripts via Shortcuts
- **[Packs & Layers]({{ '/guides/packs/' | relative_url }})** — Set up layers to bind scripts to keys
