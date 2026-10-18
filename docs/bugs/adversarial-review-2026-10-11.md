# KeyPath adversarial review — 2026-10-11

Scope: current `design/driverless-caps-ui` checkout, including its existing uncommitted work. Three isolated reviewers covered lifecycle/HID/reload, configuration/Rust admission/persistence, and onboarding/permissions/activity history. Parent independently checked reports and reviewed launcher routing/uninstall boundaries.

## Confirmed and fixed issues (regressions reproduced before fixes)

| ID | Priority | Bug | Failing evidence |
|---|---|---|---|
| A1 | P1 | Legacy admission misses chord-v2, overrides, and startup aliases, allowing unsupported output to terminate runtime | Rust legacy-session tests: 7 failed, 2 passed |
| A2 | P1 | Activity append replaces unreadable or malformed existing history | Three preservation tests fail |
| A3 | P1 | Concurrent activity appends lose batches; reset can resurrect in-flight history | Controlled overlapping append and reset tests fail |
| A4 | P2 | Shortcuts never start after initial permission refusal followed by a grant | Permission recovery test fails |
| A5 | P2 | Partial hotkey monitor startup leaks local monitor on retry | Partial monitor test fails |
| A6 | P2 | Edit during unhealthy startup is never delivered to runtime | Deferred reload test fails |
| A7 | P1 | Invalid application PID can reach process-group/broadcast signal call | Injected stop signal test fails for -1/0/negative IDs; SDK edge, no live broadcast attempted |
| A8 | P2 | Full folder links lose absolute root; shorthand paths corrupt punctuation | Two real temporary-folder dispatch tests fail |
| A9 | P2 | Generated notifications lack URI separator and do not encode values | Generator-to-parser round-trip test fails |
| A10 | P2 | Caps remap plus ordinary generated custom layer is rejected | Real bridge generated-layer eligibility test fails |
| A11 | P1 | Stale health reply can undo manual Stop; deferred retry can continue after Stop | Intent race and stop-during-retry tests fail |

## Fixes

- Runtime output admission now checks global chord actions and their inputs. Opaque overrides and startup aliases are conservatively refused, matching the managed-Caps policy; safe ordinary mappings and chords remain covered positively.
- Activity storage serializes complete mutation transactions across encryption awaits. Read/decryption/UTF-8/JSON failures preserve original bytes and propagate to the caller, which retains its buffer.
- Hotkey startup retries on application activation after consent and independently installs only missing monitor handles. Stop removes the activation observer.
- Reloads retain pending startup edits, check lifecycle intent across async work, and cancel quietly after manual Stop. Explicit onboarding recovery remains supported.
- Shutdown never sends signals to zero or negative PID targets. Tests use an injected signal sender, never real process-group signals.
- File actions preserve absolute roots and literal shorthand path punctuation. Notification generation emits a parseable URI and percent-encodes values. The editor and legacy migration now share the payload parser, including support for historical notification syntax.
- Generated Caps layers use explicit base fallbacks, while arbitrary unsafe raw transparency remains rejected. The historical golden was reviewed and updated. Rollback coverage now uses unsupported media output rather than rejecting newly supported Caps layers.

## Excluded

- Input Monitoring wizard navigation concern: insufficient reproduction evidence.
- Activity-history startup waiting for explicit access: intentional documented design.
- Device selection refusal after topology change: intentional conservative ownership policy.
- BackupManager validation weakness: no active production call path established during this review.

## Validation

- All 3 reviewers finished; root independently inspected each accepted report.
- Reproduction logs capture failing assertions before source fixes, including deterministic actor suspension and injected OS boundaries.
- Focused Swift validation: 137 tests passed; follow-up shared-parser validation: 73 passed.
- Rust bridge: 20 tests passed, including 9 independently reported admission cases.
- Python verification tools: 24 tests passed under Homebrew Python 3.14 (the system Python 3.9 lacks required datetime.UTC).
- Accessibility: 380 source files passed identifier checks.
- Final full Swift suite: **5,426 passed**, exit 0, zero compiler warnings.
- Opt-in screenshot snapshots and physical VM acceptance were not rerun for this review. The previous physical acceptance results remain historical evidence, not validation of this new build.

## Signed build and local installation

- Developer ID signed build completed successfully; deep/strict signature verification passed. This is a local test build and was not notarized or published.
- Packaged bridge accepts the supported mapping control and rejects unsupported chord, override, and startup-alias outputs.
- Archive SHA-256: `3f8d9373d27d830679e31ded58d7b8ce2b1832d13a38ea3f5ef25bb321023423`.
- Air normal Back Up and Uninstall completed. Backup: `/Users/malpern/Downloads/KeyPath-Uninstall-Backup-75075F9C-D5D8-4F08-AFCB-7F094859726E`.
- Installed `/Applications/KeyPath.app`; executable matches the reviewed archive and signature verification passed.
- Fresh Welcome screen visually verified: Get Started above the privacy text, removed permissions paragraph absent. Left at Welcome for the user. This checks clean app onboarding state with existing macOS permission grants, not fresh TCC acceptance.

## Overall assessment

The codebase has useful ownership boundaries, substantial regression coverage, and careful configuration journals and rollback behavior. The main defects found were cross-actor transaction races, stale lifecycle intent, output validation outside the main action tree, and encoding/decoding boundaries. These are behavior gaps that happy-path tests did not cover. The reviewed findings are repaired; this review is not proof that the entire project is bug-free.

The review preserves the pre-existing dirty checkout. It does not publish a release, open a PR, or commit unrelated work.

