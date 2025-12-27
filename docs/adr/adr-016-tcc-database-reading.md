# ADR-016: TCC Database Reading for Sequential Permission Flow

**Status:** Accepted
**Date:** 2024

## Context

The wizard needs to guide users through Accessibility and Input Monitoring permissions one at a time. Without pre-flight detection, starting Kanata would trigger both system permission dialogs simultaneously, creating a confusing UX.

## Decision

Read the TCC database (`~/Library/Application Support/com.apple.TCC/TCC.db`) to detect Kanata's permission state before prompting. This is a read-only operation used as a UX optimization.

## Why Not "Try and See"?

- `IOHIDCheckAccess()` only works for the calling process (KeyPath), not for checking another binary (Kanata)
- Starting Kanata to probe permissions triggers simultaneous AX+IM prompts
- PR #1759 to Kanata proved daemon-level permission checking is unreliable (false negatives for root processes)

## Why This Is Acceptable

| Concern | Mitigation |
|---------|------------|
| Read-only | Not modifying TCC - Apple's guidance is about preventing writes/bypasses |
| Graceful degradation | Falls back to `.unknown` if TCC read fails (no FDA) |
| GUI context | Runs in KeyPath app (user session), not daemon |
| UX requirement | Sequential permission prompts are essential for user comprehension |

## Apple Policy

macOS protects TCC.db with Full Disk Access. Read access with user-granted FDA is allowed. Writes require Apple-only entitlements and are effectively blocked. Our usage is read-only.

## Alternative Considered

Contributing `--check-permissions` to Kanata upstream. Rejected because:
- Maintainer has no macOS devices
- `IOHIDCheckAccess` doesn't work correctly from daemon context anyway

## Related
- [ADR-006: Apple API Priority](adr-006-apple-api-priority.md)
