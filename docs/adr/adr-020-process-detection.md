# ADR-020: Process Detection Strategy (pgrep vs launchctl)

**Status:** Accepted
**Date:** November 2025

## Context

Two approaches exist for detecting running processes:
1. `launchctl` - queries launchd for service status
2. `pgrep` - searches process table by name

## Decision

Use different approaches for different scenarios.

### Use `launchctl` (Preferred for Our Services)

| Scenario | Why |
|----------|-----|
| Checking `com.keypath.kanata` status | Fast, reliable |
| Checking `com.keypath.karabiner-vhiddaemon` | No subprocess race conditions |

Already migrated in `SystemValidator`, `ServiceHealthChecker`.

### Use `pgrep` (Required for These Cases)

| Scenario | Why launchctl Can't Help |
|----------|--------------------------|
| External processes (Karabiner's `karabiner_grabber`) | Not our launchd service |
| Orphan detection | Finding kanata NOT managed by launchd |
| Post-kill verification | Checking if process died after `pkill` |
| Diagnostics | Enumerating ALL matching processes |

## Consequences

**Do not migrate remaining pgrep usages** - they exist for scenarios where launchctl cannot help.

## Related
- [ADR-022: No Concurrent pgrep](adr-022-no-concurrent-pgrep.md)
