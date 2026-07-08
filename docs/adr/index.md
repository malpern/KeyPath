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
| [ADR-029](/adr/adr-029-eliminate-fake-key-layer-notifications) | Eliminate Fake Key Layer Notifications via Native LayerChange | Proposed |
| [ADR-030](/adr/adr-030-insights-companion-app) | Separate Activity Logging and AI Features into KeyPath Insights Companion App | Accepted |
| [ADR-031](/adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement) | Kanata Service Lifecycle Invariants and Postcondition Enforcement | Accepted |
| [ADR-032](/adr/adr-032-macos-kanata-runtime-identity) | Stable App-Bundled Runtime Identity for macOS Kanata Input Capture | Proposed |
| [ADR-033](/adr/adr-033-bundled-binary-canonical-path) | Bundled Binary as Canonical Kanata Path | Accepted |
| [ADR-034](/adr/adr-034-kanata-engine-app-bundle-tcc-identity) | Kanata Engine.app Bundle for TCC Identity | Accepted |
| [ADR-035](/adr/adr-035-bundle-id-tcc-detection-with-path-fallback) | Bundle ID TCC Detection with Path Fallback | Accepted |
| [ADR-036](/adr/adr-036-per-device-key-mappings) | Per-Device Key Mappings via Conditional Switch Wrapping | Accepted |
| [ADR-037](/adr/adr-037-dynamic-os-key-labels) | Dynamic OS-Driven Key Labels (System Keymap) | Accepted |
| [ADR-038](/adr/adr-038-extension-file-splitting) | Extension-File Splitting for Large Types | Accepted |
| [ADR-039](/adr/adr-039-key-conflict-resolution-principles) | Key Conflict Detection and Resolution Principles | Accepted |
| [ADR-040](/adr/adr-040-process-liveness-across-privilege-boundary) | Process Liveness and Signaling Across the Privilege Boundary | Accepted |
| [ADR-041](/adr/adr-041-installer-identity-stability-contract) | Installer Identity Stability Contract | Accepted |
| [ADR-042](/adr/adr-042-executable-installer-state-classification) | Executable Installer State Classification | Accepted |

## Key Decisions Summary

### Permission System
- **ADR-001/006**: `PermissionOracle` is the single source of truth. Apple APIs are authoritative; TCC database is fallback only.

### Installation & Repair
- **ADR-015**: `InstallerEngine` is the unified façade for all install/repair/uninstall operations.
- **ADR-026**: Always validate components exist BEFORE checking service status.
- **ADR-031**: Installer success requires verified runtime readiness (`running + TCP`) or explicit pending approval.
- **ADR-040**: kanata is a root LaunchDaemon; app-side process liveness treats `EPERM` from `kill(pid,0)` as alive.
- **ADR-041**: Installer identity values for kanata, helper, and daemon shell are release-gated contracts.
- **ADR-042**: The installer repair state matrix is executable; CLI, menu-bar, and wizard consumers share row/action vocabulary.

### Configuration
- **ADR-023**: Never parse Kanata config files directly. Use TCP and simulator.
- **ADR-025**: JSON stores are source of truth; config file is generated output.

### Testing
- **ADR-019**: Use `TestEnvironment.isRunningTests` for side-effect guards.
- **ADR-022**: Never call pgrep-spawning functions concurrently in TaskGroups.
- **ADR-040**: OS primitives hidden behind seams need at least one grounding test against real runtime behavior.

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
