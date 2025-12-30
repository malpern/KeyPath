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
| [ADR-001]({{ '/adr/adr-001-oracle-pattern' | relative_url }}) | Oracle Pattern for Permission Detection | Accepted |
| [ADR-006]({{ '/adr/adr-006-apple-api-priority' | relative_url }}) | Apple API Priority in Permission Checks | Accepted |
| [ADR-008]({{ '/adr/adr-008-validation-refactor' | relative_url }}) | Stateless Validation via SystemValidator | Accepted |
| [ADR-009]({{ '/adr/adr-009-service-extraction-mvvm' | relative_url }}) | Service Extraction & MVVM Pattern | Accepted |
| [ADR-013]({{ '/adr/adr-013-tcp-without-auth' | relative_url }}) | TCP Communication Without Authentication | Accepted |
| [ADR-014]({{ '/adr/adr-014-xpc-signature-mismatch' | relative_url }}) | XPC Signature Mismatch Prevention | Accepted |
| [ADR-015]({{ '/adr/adr-015-installer-engine' | relative_url }}) | InstallerEngine Façade | Accepted |
| [ADR-016]({{ '/adr/adr-016-tcc-database-reading' | relative_url }}) | TCC Database Reading for Sequential Permission Flow | Accepted |
| [ADR-017]({{ '/adr/adr-017-protocol-segregation' | relative_url }}) | InstallerEngine Protocol Segregation (ISP) | Accepted |
| [ADR-018]({{ '/adr/adr-018-helper-protocol-duplication' | relative_url }}) | HelperProtocol XPC Duplication | Accepted |
| [ADR-019]({{ '/adr/adr-019-test-seams' | relative_url }}) | Test Seams via TestEnvironment Checks | Accepted |
| [ADR-020]({{ '/adr/adr-020-process-detection' | relative_url }}) | Process Detection Strategy (pgrep vs launchctl) | Accepted |
| [ADR-021]({{ '/adr/adr-021-vhid-timing' | relative_url }}) | Conservative Timing for VHID Driver Installation | Accepted |
| [ADR-022]({{ '/adr/adr-022-no-concurrent-pgrep' | relative_url }}) | No Concurrent pgrep Calls in TaskGroups | Accepted |
| [ADR-023]({{ '/adr/adr-023-no-config-parsing' | relative_url }}) | No Config File Parsing - Use TCP and Simulator | Accepted |
| [ADR-024]({{ '/adr/adr-024-icons-emphasis' | relative_url }}) | Custom Key Icons and Emphasis via push-msg | Partial |
| [ADR-025]({{ '/adr/adr-025-config-management' | relative_url }}) | Configuration Management - One-Way Write | Accepted |
| [ADR-026]({{ '/adr/adr-026-validation-ordering' | relative_url }}) | System Validation Ordering | Accepted |
| [ADR-027]({{ '/adr/adr-027-app-specific-keymaps' | relative_url }}) | App-Specific Keymaps via Virtual Keys | Accepted |

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

## Reading ADRs

Each ADR follows a standard format:

1. **Status** - Current state (Accepted, Proposed, Deprecated)
2. **Context** - What problem are we solving?
3. **Decision** - What did we decide?
4. **Consequences** - What are the trade-offs?

ADRs are living documents. They can be updated as we learn more or circumstances change.
