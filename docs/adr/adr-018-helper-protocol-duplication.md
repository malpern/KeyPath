# ADR-018: HelperProtocol XPC Duplication

**Status:** Accepted
**Date:** November 2025

## Context

`HelperProtocol.swift` exists as identical copies in two locations:
- `Sources/KeyPathAppKit/Core/HelperProtocol.swift`
- `Sources/KeyPathHelper/HelperProtocol.swift`

## Decision

Keep the duplication. This is **required by XPC architecture**.

## Why Duplicated?

XPC architecture requires the protocol compiled into both app and helper separately. They cannot share a module at runtime because the helper is a standalone Mach-O binary.

## Risk

If files diverge, XPC calls fail at runtime with selector-not-found errors.

## Mitigation

`HelperProtocolSyncTests` validates both files are identical. CI will fail if they diverge.

## When Modifying

1. Update BOTH files
2. Run `swift test --filter HelperProtocolSyncTests`
3. Ensure test passes before committing
