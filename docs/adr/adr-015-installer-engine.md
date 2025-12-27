# ADR-015: InstallerEngine Façade

**Status:** Accepted
**Date:** November 2025

## Context

Installation and repair logic was scattered across multiple components:
- `WizardAutoFixer`
- `LaunchDaemonInstaller` (direct calls)
- `SystemStatusChecker`

This made it hard to understand the full installation flow and led to inconsistent behavior.

## Decision

Create `InstallerEngine` as the **unified façade** for all installation, repair, and system inspection operations.

## Interface

```swift
class InstallerEngine {
    // System inspection
    func inspectSystem() async -> SystemContext

    // Installation/repair
    func run(intent: InstallIntent) async -> InstallerReport
}

enum InstallIntent {
    case install
    case repair
    case uninstall
}
```

## Flow

```
inspectSystem() → makePlan() → execute() → InstallerReport
```

## What It Replaces

| Old | New |
|-----|-----|
| `WizardAutoFixer.fix*()` | `InstallerEngine.run(intent: .repair)` |
| `LaunchDaemonInstaller.install()` | `InstallerEngine.run(intent: .install)` |
| `SystemStatusChecker.check()` | `InstallerEngine.inspectSystem()` |

## Related
- [ADR-008: Validation Refactor](adr-008-validation-refactor.md)
- [ADR-017: Protocol Segregation](adr-017-protocol-segregation.md)
