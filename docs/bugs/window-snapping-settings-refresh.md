# Window Snapping settings refresh — 2026-10-12

Installed on Air. SHA-256 of main executable:
`da67cf9baed19b688e8f011b60afba6829b600d703a09b2cb44ee7fe1044a5e1`.

Compact header and activation row; native activation popover; shared SettingsCard and SettingsControlRow; Standard/Vim segments; eight position previews with readable labels and shortcuts; expandable display/Spaces/Undo reference. Reference remains readable while disabled. Removed static dependency prose from this detail panel. Preview actions never call the window-management runtime. Reduce Motion disables the preview transition.

Fixed configuration editing unexpectedly enabling a disabled Window Snapping rule. New regression test failed before the fix and passed after; all 21 prerequisite-resolution tests passed, zero warnings. Removed implicit pack installation from convention edits and preserved enable state in the canonical settings mutation. Accessibility identifier lint passed all 381 files; scoped SwiftFormat and diff checks passed.

Live QA exposed stale preview state after successful persistence. Pack detail now reads the observable view-model collection list rather than the unobserved coordinator storage. Rebuilt and confirmed Vim on reopen and immediate Standard badge updates after changing back. Air persisted state is Standard, Window Snapping off, matching original settings. Pointer preview, activation popover, and More shortcuts checked live. Full VoiceOver and keyboard-navigation coverage were not verified (Tab did not focus controls with current system settings).

Signed app verification passed, including owned driverless session and TCP readiness. Development build: notarization/stapling checks skipped. Original app retained at KeyPath-before-refresh.app. No release/PR created.
