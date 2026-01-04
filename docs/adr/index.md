---
layout: default
title: Architecture Decision Records
description: Significant design decisions in KeyPath
---

# Architecture Decision Records

This section documents significant architectural decisions in KeyPath. Each ADR describes the context, decision, and consequences.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](/adr/adr-001-oracle-pattern) | Oracle Pattern for Permission Detection | Accepted |
| [ADR-006](/adr/adr-006-apple-api-priority) | Apple API Priority in Permission Checks | Accepted |
| [ADR-008](/adr/adr-008-validation-refactor) | Stateless Validation via SystemValidator | Accepted |
| [ADR-009](/adr/adr-009-service-extraction-mvvm) | Service Extraction & MVVM Pattern | Accepted |
| [ADR-013](/adr/adr-013-tcp-without-auth) | TCP Communication Without Authentication | Accepted |
| [ADR-014](/adr/adr-014-xpc-signature-mismatch) | XPC Signature Mismatch Prevention | Accepted |
| [ADR-015](/adr/adr-015-installer-engine) | InstallerEngine Façade | Accepted |
| [ADR-016](/adr/adr-016-tcc-database-reading) | TCC Database Reading for Sequential Permission Flow | Accepted |
| [ADR-017](/adr/adr-017-protocol-segregation) | InstallerEngine Protocol Segregation (ISP) | Accepted |
| [ADR-018](/adr/adr-018-helper-protocol-duplication) | HelperProtocol XPC Duplication | Accepted |
| [ADR-019](/adr/adr-019-test-seams) | Test Seams via TestEnvironment Checks | Accepted |
| [ADR-020](/adr/adr-020-process-detection) | Process Detection Strategy (pgrep vs launchctl) | Accepted |
| [ADR-021](/adr/adr-021-vhid-timing) | Conservative Timing for VHID Driver Installation | Accepted |
| [ADR-022](/adr/adr-022-no-concurrent-pgrep) | No Concurrent pgrep Calls in TaskGroups | Accepted |
| [ADR-023](/adr/adr-023-no-config-parsing) | No Config File Parsing - Use TCP and Simulator | Accepted |
| [ADR-024](/adr/adr-024-icons-emphasis) | Custom Key Icons and Emphasis via push-msg | Partial |
| [ADR-025](/adr/adr-025-config-management) | Configuration Management - One-Way Write | Accepted |
| [ADR-026](/adr/adr-026-validation-ordering) | System Validation Ordering | Accepted |
| [ADR-027](/adr/adr-027-app-specific-keymaps) | App-Specific Keymaps via Virtual Keys | Accepted |
| [ADR-028](/adr/adr-028-unified-sf-symbols) | Unified SF Symbol Resolution via SystemActionInfo | Accepted |

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

### UI & Icons
- **ADR-024**: Key emphasis and custom icons via push-msg protocol.
- **ADR-028**: `SystemActionInfo.allActions` is the single source of truth for SF symbols.

## Reading ADRs

Each ADR follows a standard format:

1. **Status** - Current state (Accepted, Proposed, Deprecated)
2. **Context** - What problem are we solving?
3. **Decision** - What did we decide?
4. **Consequences** - What are the trade-offs?

ADRs are living documents. They can be updated as we learn more or circumstances change.
