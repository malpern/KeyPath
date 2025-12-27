# ADR-014: XPC Signature Mismatch Prevention

**Status:** Accepted
**Date:** 2024

## Context

When updating KeyPath, the app bundle's signature changes but the installed privileged helper may have the old signature. XPC connections fail silently or with cryptic errors.

## Decision

Implement robust app restart logic to prevent mismatched helpers.

## Implementation

1. On app launch, check if helper version matches app version
2. If mismatch detected, prompt user to reinstall helper
3. Helper installation includes version check
4. App restart after helper update ensures clean state

## Consequences

- Users may need to re-authenticate after app updates
- Version mismatch is detected early, not at runtime failure
- Clear error messages when mismatch occurs
