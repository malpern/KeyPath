---
layout: default
title: Installation
description: Install KeyPath on macOS
permalink: /getting-started/installation/
---

# Installation

KeyPath requires macOS 15.0 (Sequoia) or later. It works on both Apple Silicon and Intel Macs.

## Download & Install

### Recommended: Download Release

1. Visit the [Releases page]({{ site.github_url }}/releases)
2. Download the latest `KeyPath.app` bundle
3. Move it to your Applications folder
4. Open KeyPath.app

### Build from Source

For developers who want to build from source:

```bash
# Clone the repository
git clone {{ site.github_url }}.git
cd KeyPath

# Build, sign, and install
./build.sh
```

The build script:
- Compiles the Swift package
- Signs all components with Developer ID
- Notarizes the app bundle
- Installs to `~/Applications/`
- Restarts the app

**Note:** For local iteration, skip notarization with `SKIP_NOTARIZE=1 ./build.sh`

## First Launch Setup

When you first launch KeyPath, the **Installation Wizard** guides you through setup:

### 1. Existing Kanata Config Detection

If you're already using Kanata, KeyPath automatically detects your config:

- **Running Kanata process** — finds the config from command-line args
- **Common locations** — checks `~/.config/kanata/`, `~/.config/keypath/`, and home directory
- **Common names** — looks for `kanata.kbd`, `config.kbd`

When found, KeyPath offers to use your existing config with one click. Your original file stays where it is — KeyPath creates a symlink and adds the include line it needs.

### 2. Permission Setup

KeyPath needs two macOS permissions:

- **Input Monitoring** — to detect key presses
- **Accessibility** — to send remapped keys

The wizard provides one-click access to System Settings for each.

### 3. Driver & Service Setup

KeyPath automatically:
- Installs the Karabiner VirtualHID driver (for system-level remapping)
- Configures LaunchDaemon services (remappings work at boot)
- Validates your setup and offers one-click fixes for issues

## System Requirements

- **macOS 15.0 (Sequoia) or later**
- **Apple Silicon or Intel Mac**

### Dependencies (Handled Automatically)

- **Kanata** - The remapping engine (bundled with app)
- **Karabiner VirtualHID Driver** - For system-level key events

The setup wizard automatically checks for these and helps you install them if needed.

## Troubleshooting Installation

### "KeyPath.app is damaged"

This usually means the app wasn't properly notarized or downloaded incorrectly.

**Solution:**
1. Remove the quarantine attribute: `xattr -d com.apple.quarantine /Applications/KeyPath.app`
2. Or download again from the Releases page

### Setup Wizard Won't Complete

If the wizard gets stuck:

1. Check the logs: `tail -f /var/log/com.keypath.kanata.stdout.log`
2. Use the "Fix Issues" button in the wizard
3. Restart the app and run the wizard again

### Permission Issues

If permissions aren't being detected:

1. Go to System Settings → Privacy & Security
2. Manually grant Input Monitoring and Accessibility
3. Restart KeyPath

## Uninstallation

To uninstall KeyPath:

1. Open KeyPath
2. Choose **File → Uninstall KeyPath…**
3. Confirm the admin prompt

This removes:
- LaunchDaemon services
- System binaries
- Configuration files
- Application bundle

## Next Steps

After installation, see [Your First Mapping]({{ '/getting-started/first-mapping' | relative_url }}) to create your first keyboard remapping.
