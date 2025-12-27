# ADR-021: Conservative Timing for VHID Driver Installation

**Status:** Accepted
**Date:** November 2025

## Context

The "fix Karabiner driver" operation takes ~11 seconds. This seems slow but is intentional.

## Timing Breakdown

`VHIDDeviceManager.downloadAndInstallCorrectVersion()`:

| Step | Operation | Sleep | Purpose |
|------|-----------|-------|---------|
| 1 | `systemextensionsctl uninstall` | 2s | Wait for DriverKit extension removal |
| 2 | `installer -pkg` (admin prompt) | 2s | Wait for pkg postinstall scripts |
| 3 | Post-install settle | 3s | Allow DriverKit extension registration |
| 4 | `activate` command | 2s | Wait for manager activation |

**Total:** ~9s of sleeps + ~2s command execution = ~11s

## Why Not Optimize?

1. **Rare operation**: Driver install happens once per machine, or on Kanata major version upgrades (yearly)

2. **Reliability over speed**: DriverKit extension loading is asynchronous and timing varies by:
   - SSD speed (especially on older Macs or VMs)
   - System load (Spotlight indexing, Time Machine, etc.)
   - macOS version (DriverKit behavior differs across versions)

3. **No reliable completion signal**: `systemextensionsctl` and `installer` return before async work completes

4. **Failure cost is high**: A race condition here leaves the user with a broken driver requiring manual intervention

## Alternatives Considered and Rejected

| Alternative | Why Rejected |
|-------------|--------------|
| Poll-based verification | DriverKit has no reliable API to poll |
| Reduce sleeps by 50% | Caused intermittent failures on slower machines |
| Skip uninstall for same version | Doesn't help upgrades; risks corrupted state |

## Decision

Keep conservative 9s of sleeps + ~2s command execution. User sees progress UI during this time. The 11 seconds ensures reliability across all supported hardware configurations.
