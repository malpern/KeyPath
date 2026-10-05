# An enabled session tap can omit keyboard events

The isolated c6 guest experiment reached runtime readiness with its exact worker registered for flagsChanged (4096), while the requested mask was keyDown, keyUp, and flagsChanged (7168). The one root-context registration query occurred before target launch or hardware input. Enabled state alone therefore cannot establish that keyboard events are registered. This finding is specific to that observed worker; it does not prove that Input Monitoring is universally required.

The experimental build now records one worker-self registration query after enabling the tap, selecting only its own session/default tap rows. It distinguishes absence, multiple matches, API error, capacity overflow, and unexpected native ABI. Raw Accessibility and ListenEvent facts come through PermissionOracle; PostEvent reuses the worker's existing session capability snapshot. These are pre-tap startup facts, not simultaneous measurements. The experimental startup now refuses partial, ambiguous, unavailable or disabled registration before publishing running. It uses the existing failed shutdown path and does not impose a new unconditional ListenEvent permission rule. Normal builds retain their existing behavior.

CGGetEventTapList resets global tap latency extrema. The query limits entries to 128 but has no wall-time timeout. Reports omit other processes, event contents, and latency values. Older strict physical collectors require a separately reviewed schema update before using this report.

Validation: actual report and verbatim native ABI/query/classifier compiled and pure interpretation/strict decoding checks passed without executing permission or tap APIs. The complete experimental KeyPath product compiled using explicit Xcode 27 because pinned Xcode 26.6 is absent. Verified prebuilt Metal bytes were reused temporarily; the build plugin was restored byte for byte. Seven scoped Swift tests were authored; the full test target was not run. Focused pure admission, ABI, classifier and strict decoder checks passed, including the actual formatted source startup ordering. Independent source review accepted the experimental gate. Its live failure-path validation remains pending.

Signed build370ac271 was tested in disposable macOS26 guest cbx_1b29f29a3ebc, same boot1791161222/publicUID502/binary6c0182d3/config4cf78f9e. Three fresh worker generations gave matched worker-self and root-context registration evidence:

| Normal guest permission state | Worker | Registered mask | Raw AX/Post/Listen |
| --- | --- | --- | --- |
| Accessibility only | 2395 / C0D35B1C | 4096, modifiers only | granted/granted/denied |
| Input Monitoring enabled | 5068 / 79DB1C3C | 7168, full requested mask | granted/granted/granted |
| Input Monitoring revoked | 7731 / 4C8F7A92 | 4096, modifiers only | granted/granted/denied |

Receipts: `/private/tmp/keypath-370ac-1b29-noinput-0056/receipt.json`, `/private/tmp/keypath-370ac-1b29-im-noinput-0100/receipt.json`, `/private/tmp/keypath-370ac-1b29-revoked-noinput-0106/receipt.json`. All passed their no-input observation and cleanup predicates; profiles were bytewise restored. Exact target cleanup independently confirmed no product/target/stale report, held empty and modifiers zero. No fixture attachment or keyboard input occurred, so these are registration findings, not physical delivery or timeout acceptance. VM deletion, retained stopped template and detached fixture routing independently passed `/private/tmp/keypath-1b29-provider-cleanup-check.json`.

This reversible comparison supports Input Monitoring affecting keyboard registration in this guest. It does not prove a universal macOS requirement. Removing the Karabiner driver remains a simplification, but an Accessibility-only installer promise is unsupported here. Next: validate the experimental admission failure/full-mask paths in a fresh signed guest, then physical remapping, actual OS timeout and console transitions. Caps Lock and reduced-permission onboarding follow runtime stabilization.
