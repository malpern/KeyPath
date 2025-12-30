---
layout: default
title: Installation
description: Install KeyPath on macOS
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

When you first launch KeyPath, the **Installation Wizard** will guide you through:

### 1. Permission Setup

KeyPath needs two macOS permissions:

- **Input Monitoring** - To detect key presses
- **Accessibility** - To send remapped keys

The wizard provides one-click access to System Settings for each permission.

### 2. Driver Installation

KeyPath automatically installs the Karabiner VirtualHID driver if needed. This driver enables system-level keyboard remapping.

### 3. Service Configuration

KeyPath sets up LaunchDaemon services to run Kanata at the system level. This ensures remappings work at boot time and survive app restarts.

### 4. System Validation

The wizard validates your setup and provides one-click fixes for common issues.

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

After installation, see [Your First Mapping](/getting-started/first-mapping) to create your first keyboard remapping.
