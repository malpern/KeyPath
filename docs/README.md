# KeyPath Documentation

This directory contains all documentation for the KeyPath project.

## Files

- **[DEBUGGING_KANATA.md](DEBUGGING_KANATA.md)** - Comprehensive debugging guide for Kanata integration issues
- **[CONTEXT.md](CONTEXT.md)** - Project history and architectural evolution
- **[KANATA_SETUP.md](KANATA_SETUP.md)** - Setup instructions for Kanata integration
- **[KANATA_MACOS_SETUP_GUIDE.md](KANATA_MACOS_SETUP_GUIDE.md)** - macOS-specific setup guide
- **[SAFETY_FEATURES.md](SAFETY_FEATURES.md)** - Safety and security considerations

## Quick Links

- **Troubleshooting**: Start with [DEBUGGING_KANATA.md](DEBUGGING_KANATA.md)
- **Initial Setup**: See [KANATA_SETUP.md](KANATA_SETUP.md)
- **Project History**: Read [CONTEXT.md](CONTEXT.md)

## To-Do (current priorities)

- Route all Wizard auto-fix flows through `InstallerEngine` (remove direct subprocess/AppleScript paths).
- Add façade parity/regression tests to ensure UI/CLI auto-fix paths stay on the façade.
- Replace UI permission probes with async `PermissionOracle` checks (remove `Thread.sleep` polling).
- Remove BundledRuntimeCoordinator AppleScript install path once façade recipe exists.
- Update debug scripts to call `InstallerEngine` instead of ad-hoc `LaunchDaemonInstaller` logic.
- Drop `Scripts/archive/deprecated-tests` from active suite or delete the folder.
- Refresh or delete stale lint artifacts (`swiftlint-report.txt`, `lint_issues.json`).
