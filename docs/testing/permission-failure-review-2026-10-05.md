# Last 12 unsuccessful attempts — October 5, 2026

This review counts the latest 12 nonzero `actualStatus` receipts, ordered by receipt completion timestamp, across the two latest completed Caps trials: `/private/tmp/keypath-caps-identity-live-01` (I) and `/private/tmp/keypath-caps-mutation-live-01` (M). Times are PDT. These are 12 attempts, not 12 separate bugs; UI misses and expected safety refusals are included because they consumed a cycle. Successful expected product refusals are not counted as failed tests. This is a recent-attempt inventory, not a census of all failures during the investigation.

## Inventory and causes

| # | Time | Receipt / result | Root cause and certainty | Resolution / remaining issue |
|---|---|---|---|---|
| 1 | 16:13:05 | I `rebootruntimeaction01`, status 1 | Confirmed caller error: Peekaboo rejected `--app` on `perform-action`. Command failed before the intended action. | Correct documented argument form used later. Compile checks cannot catch invalid CLI options; check the actual tool contract locally. |
| 2 | 16:16:47 | I `finalrebootobserve01`, status 1 | Confirmed safety refusal: cleanup required no app parent, but the inactive parent was still alive. A native Quit attempt had not retired it; why native Quit failed remains unproved. | Guard prevented premature environment cleanup. Exact inactive parent was later terminated and independently checked. |
| 3 | 16:16:49 | I `finalrebootquit01`, status 1 | Confirmed automation capability failure: `activateApplication` was not permitted on Peekaboo's menu route. This does not prove a KeyPath permission or runtime defect. | Menu action was not delivered through this route. Scoped process retirement completed cleanup. This route remains unreliable in this guest context. |
| 4 | 16:17:28 | I `finalrebootobserve02`, status 1 | Same live-parent cleanup guard as #2. Rechecking without establishing the prerequisite repeated the symptom. | No mutation; later verified retirement resolved prerequisite. |
| 5 | 16:18:13 | I `finalrebootobserve03`, status 1 | Same live-parent cleanup guard again. Confirmed repeated process mistake, not another infrastructure bug. | No mutation; later verified retirement resolved prerequisite. |
| 6 | 16:33:46 | M `connection02`, status 1 | Unresolved transport failure: stdout/stderr empty and both transfers unused/incomplete. A normal guest Local Network prompt was observed and allowed before connection03 passed, supporting a permission-related hypothesis, but the failed receipt alone does not establish causation. | Distinct read-only connection03 passed. Preserve this as unresolved rather than calling it a proven network fault. |
| 7 | 16:34:36 | M `install01`, status 1 | Confirmed wrapper refusal: “staging not verified.” High-confidence packaging diagnosis: the pinned ZIP contains 425 `__MACOSX` members that the pinned guest archive guard rejects. Child stderr was discarded, so the exact live failing assertion was lost. | New ZIP omitted metadata; normal payload bytes/modes and signature were verified unchanged; install02 passed. Future packaging must use the same metadata policy as installation. The original packaging helper still needs correction before reuse. |
| 8 | 16:36:20 | M `profile01`, status 79 | Confirmed sequencing error: helper read `keypath.kbd` before the app's first normal launch created it. This exact prerequisite was already documented. | Normal first launch created the default profile; later preparation passed. |
| 9 | 16:36:21 | M `consent-launch01`, status 79 | Duplicate of #8: dependent step ran despite the failed profile prerequisite. | Stop dependent steps on failure; use the established first-launch sequence. |
| 10 | 16:41:33 | M `im-notice01`, status 1 | Confirmed observation miss: UserNotificationCenter was running but had no window/dialog. The script assumed a notification existed. This is not evidence that Input Monitoring consent failed. | Used the actual Settings permission page; subsequent runtime verified Accessibility/Input Monitoring access and an active event tap. |
| 11 | 16:44:38 | M `checkpoint-launch01`, status 1 | Confirmed generated-code error: nested string escaping produced an unterminated Python literal. Parsing failed before guest experiment actions executed. | Raw string generation corrected; complete assembled guest source compiled before dispatch; launch02 passed. |
| 12 | 16:48:31 | M `marker-quit01`, status 1 | Same confirmed Peekaboo `activateApplication` permission failure as #3. Reusing the known failing menu route created another avoidable cycle. | Exact inactive parent termination, environment cleanup, canonical guest destruction and independent provider/USB checks passed. |

## What this says about our process

The most important problem is reuse of helpers without validating their actual assumptions against the current artifact and guest state. We already knew the first-launch/profile ordering and menu-route limitations, but repeated them. Review of source and hashes protected scope; it did not catch unsupported CLI arguments, generated-source escaping, or archive format mismatch. That is why more elaborate scope machinery alone has not improved iteration speed enough.

Seven attempts fall into repeated clusters: #2/#4/#5, #3/#12, and #8/#9. The repetition is our orchestration problem. The cleanup guard itself did the right thing. Two records also lost diagnostic detail: connection02 was empty, and the installer discarded child stderr. Those gaps force inference and extra reconciliation.

No attempt in this set establishes a fundamental driverless limitation. Separately, the product had delayed display of a known restoration refusal; the committed UI fix now has narrow live evidence: explicit Restart displayed the retained-record refusal within 8.806 seconds of the action receipt. Initial automatic-start checking still lasted roughly 130 seconds and remains a separate UX issue. Driverless still requires Accessibility and Input Monitoring.

## Minimum changes before another product trial

1. Use the documented sequence: install → normal first launch → normal consent → verified Quit/process absence → profile preparation → trial. Every dependent step stops when its prerequisite fails.
2. Before creating a VM, validate the actual final ZIP with the installation archive policy, compile the fully assembled guest source, and validate CLI arguments against the documented tool contract. Review the executed artifact, not only helper source.
3. After one menu-route permission error, use an established supported route and verify its postcondition. Do not keep retrying the same route or cleanup guard against unchanged state. Scoped inactive-process termination remains cleanup only, not acceptance of normal Quit.
4. Retain bounded, non-secret stage diagnostics and distinguish transport failure, observation miss, expected safety refusal, and product failure. Do not add another lab framework to achieve this.

These are small corrections to the existing runner and checklist. They should reduce wasted live cycles; no speed multiplier is claimed until measured.

## Latest successful test and cleanup scope

Signed `bd7809dc1` exercised a DEBUG-only termination seam after the HID write child returned and its response was parsed, before the mutation marker was removed. Observers found the selected Caps→F18 mapping applied, worker absent, and intent/marker unchanged. Same-parent explicit Restart refused recovery and retained those files. Bounded log tails contain no checkpoint diagnostic; boundary attribution relies on pinned source, guarded opt-in and observed effects. This is not child-in-flight death acceptance, fresh-parent recovery acceptance, or proof of automatic restoration.

The owned mutation lease `cbx_534d4ab710a5` was canonically destroyed after exact inactive-parent retirement and trial environment cleanup. Intent, marker, and profile were preserved until disposal; no unsafe manual restoration or journal clearing occurred. `destroy-result.json` has status 0 (with the known hydration-stop warning); `independent-provider-cleanup02.json` confirms provider absence, stopped retained template, detached ESP32, `ask` autoconnection and no permanent binding. No owned VM remains active.

Raw evidence is retained under I/M above; receipt filenames in the table have `-result.json` suffixes. Original failed receipts are unchanged.
