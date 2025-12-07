# KeyPath Documentation

This directory contains all documentation for the KeyPath project.

## Release Milestones

KeyPath uses feature gating via release milestones:
- **R1 (Current Release):** Installer + Custom Rules only
  - Installation Wizard, Permissions, VHID Driver
  - LaunchDaemon, Privileged Helper
  - Custom Rules with Tap-Hold & Tap-Dance support
  - Config Generation, Hot Reload, Validation
- **R2 (Future Release):** Full features
  - Rule Collections (Vim, Caps Lock, Home Row Mods)
  - Live Keyboard Overlay
  - Mapper UI
  - Simulator Tab
  - Virtual Keys Inspector

See `FeatureFlags.swift` for technical details.

## Getting Started

**For Users:**
- **[KEYPATH_GUIDE.html](KEYPATH_GUIDE.html)** - Complete user guide (HTML, recommended)
- **[KEYPATH_GUIDE.adoc](KEYPATH_GUIDE.adoc)** - Complete user guide (AsciiDoc source)
- **[FAQ.md](FAQ.md)** - Frequently asked questions
- **[SAFETY_FEATURES.md](SAFETY_FEATURES.md)** - Safety and security considerations

**For Developers:**
- **[NEW_DEVELOPER_GUIDE.md](NEW_DEVELOPER_GUIDE.md)** - Start here if you're new to the codebase
- **[KANATA_MACOS_SETUP_GUIDE.md](KANATA_MACOS_SETUP_GUIDE.md)** - macOS-specific setup guide
- **[DEBUGGING_KANATA.md](DEBUGGING_KANATA.md)** - Comprehensive debugging guide for Kanata integration issues

## Architecture

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture guide and core principles
- **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** - Visual system architecture
- **[ACTION_URI_SYSTEM.md](ACTION_URI_SYSTEM.md)** - `keypath://` URL scheme documentation
- **[KANATA_OVERLAY_ARCHITECTURE.md](KANATA_OVERLAY_ARCHITECTURE.md)** - Live keyboard overlay design (R2 feature)
