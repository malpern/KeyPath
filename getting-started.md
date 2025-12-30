---
layout: default
title: Getting Started
description: Install KeyPath and create your first keyboard remapping
---

# Getting Started

Welcome to KeyPath! This guide will help you install KeyPath and create your first keyboard remapping in minutes.

## Installation

### Option 1: Download Release (Recommended)

1. Download the latest release from the [Releases page]({{ site.github_url }}/releases)
2. Open `KeyPath.app`
3. Follow the setup wizard

The wizard will guide you through:
- **Permission Setup** - Grants Input Monitoring and Accessibility permissions
- **Driver Installation** - Installs Karabiner VirtualHID driver if needed
- **Service Configuration** - Sets up LaunchDaemon services
- **System Validation** - Verifies everything is working correctly

### Option 2: Build from Source

```bash
git clone {{ site.github_url }}.git
cd KeyPath
./build.sh
```

The build script automatically compiles, signs, notarizes, and installs to `~/Applications/`.

## First Launch

When you first launch KeyPath, the **Installation Wizard** will:

1. Check for required permissions
2. Detect and resolve conflicts with other remappers
3. Install missing components (drivers, binaries)
4. Configure system services

The wizard handles all technical setup automatically and provides one-click fixes for common issues.

## Create Your First Mapping

1. **Record Input**: Click the record button next to "Input Key"
   - Press a single key (e.g., Caps Lock)
   - Or a key combo (e.g., Cmd+Space)
   - Or a sequence (e.g., press A, then B, then C)

2. **Record Output**: Click the record button next to "Output Key"
   - Press what you want it to do (e.g., Escape)
   - Or a combo (e.g., Cmd+C for copy)
   - Or type multiple keys (e.g., "hello world")

3. **Save**: Click Save - your mapping is now active!

Your remapping is active immediately—no restart, no manual service management, no file editing.

## Already Using Kanata?

If you're already using Kanata on macOS, KeyPath can run your existing configuration with minimal changes. See the [Migration Guide](/migration/kanata-users) for details.

**Quick path:** Copy your config to `~/.config/keypath/keypath.kbd`, add `(include keypath-apps.kbd)` at the top, and run the setup wizard.

## Next Steps

- **[Your First Mapping](/getting-started/first-mapping)** - Detailed walkthrough
- **[Tap-Hold & Tap-Dance](/guides/tap-hold)** - Advanced key behaviors
- **[Action URI System](/guides/action-uri)** - Trigger actions via URL scheme
- **[Window Management](/guides/window-management)** - App-specific keymaps

## Troubleshooting

### KeyPath Won't Start?

1. **Check macOS version** - Requires macOS 15.0 (Sequoia) or later
2. **Run setup wizard** - Go to File → Run Setup Wizard
3. **Check logs** - View system logs: `tail -f /var/log/com.keypath.kanata.stdout.log`

### Keys Not Remapping?

1. **Check status indicator** - Look for green checkmarks in the app
2. **Verify permissions** - Ensure permissions granted in System Settings
3. **Use Fix Issues** - Click "Fix Issues" button in the app for automated fixes

For more help, see the [FAQ](/faq) or [Debugging Guide](/guides/debugging).
