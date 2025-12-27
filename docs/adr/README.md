# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant design decisions in KeyPath.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](adr-001-oracle-pattern.md) | Oracle Pattern for Permission Detection | Accepted |
| [ADR-006](adr-006-apple-api-priority.md) | Apple API Priority in Permission Checks | Accepted |
| [ADR-008](adr-008-validation-refactor.md) | Stateless Validation via SystemValidator | Accepted |
| [ADR-009](adr-009-service-extraction-mvvm.md) | Service Extraction & MVVM Pattern | Accepted |
| [ADR-013](adr-013-tcp-without-auth.md) | TCP Communication Without Authentication | Accepted |
| [ADR-014](adr-014-xpc-signature-mismatch.md) | XPC Signature Mismatch Prevention | Accepted |
| [ADR-015](adr-015-installer-engine.md) | InstallerEngine Façade | Accepted |
| [ADR-016](adr-016-tcc-database-reading.md) | TCC Database Reading for Sequential Permission Flow | Accepted |
| [ADR-017](adr-017-protocol-segregation.md) | InstallerEngine Protocol Segregation (ISP) | Accepted |
| [ADR-018](adr-018-helper-protocol-duplication.md) | HelperProtocol XPC Duplication | Accepted |
| [ADR-019](adr-019-test-seams.md) | Test Seams via TestEnvironment Checks | Accepted |
| [ADR-020](adr-020-process-detection.md) | Process Detection Strategy (pgrep vs launchctl) | Accepted |
| [ADR-021](adr-021-vhid-timing.md) | Conservative Timing for VHID Driver Installation | Accepted |
| [ADR-022](adr-022-no-concurrent-pgrep.md) | No Concurrent pgrep Calls in TaskGroups | Accepted |
| [ADR-023](adr-023-no-config-parsing.md) | No Config File Parsing - Use TCP and Simulator | Accepted |
| [ADR-024](adr-024-icons-emphasis.md) | Custom Key Icons and Emphasis via push-msg | Partial |
| [ADR-025](adr-025-config-management.md) | Configuration Management - One-Way Write | Accepted |
| [ADR-026](adr-026-validation-ordering.md) | System Validation Ordering | Accepted |

## Key Decisions Summary

### Permission System
- **ADR-001/006**: `PermissionOracle` is the single source of truth. Apple APIs are authoritative; TCC database is fallback only.

### Installation & Repair
- **ADR-015**: `InstallerEngine` is the unified façade for all install/repair/uninstall operations.
- **ADR-026**: Always validate components exist BEFORE checking service status.

### Configuration
- **ADR-023**: Never parse Kanata config files directly. Use TCP and simulator.
- **ADR-025**: JSON stores are source of truth; config file is generated output.

### Testing
- **ADR-019**: Use `TestEnvironment.isRunningTests` for side-effect guards.
- **ADR-022**: Never call pgrep-spawning functions concurrently in TaskGroups.
