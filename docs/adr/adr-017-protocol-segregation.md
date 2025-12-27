# ADR-017: InstallerEngine Protocol Segregation (ISP)

**Status:** Accepted
**Date:** November 2025

## Context

InstallerEngine is consumed by multiple layers with different requirements:
- CLI layer needs @MainActor methods
- Wizard layer needs Sendable for concurrency
- Services layer needs throwing methods

## Decision

Three separate protocols exist for InstallerEngine - this is **intentional Interface Segregation**.

| Protocol | Methods | Consumer | Attributes |
|----------|---------|----------|------------|
| `InstallerEngineProtocol` | 4 | CLI layer | @MainActor |
| `WizardInstallerEngineProtocol` | 1 | Wizard layer | Sendable |
| `InstallerEnginePrivilegedRouting` | 3 | Services layer | throws |

## Why Separate?

1. **Zero method overlap** - Each consumer gets exactly what it needs
2. **Different Sendable/throwing requirements** - Can't unify without compromises
3. **Smaller test mocks** - Mock only what you use
4. **Interface Segregation Principle** - Clients shouldn't depend on methods they don't use

## Consequences

**Do not consolidate these protocols.** The separation is intentional.

## Related
- [ADR-015: InstallerEngine Façade](adr-015-installer-engine.md)
