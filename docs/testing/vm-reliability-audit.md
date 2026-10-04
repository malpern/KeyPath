## Follow-through — October 4, 2026, 14:12 UTC

Reusable experimental vm-lab branch now includes live-validated public account/home, pinned usable Python, typed transport diagnostics and journaled restart support; canonical main remains unchanged. Frozen setup failures and reconciliation receipts are retained. Separate session/tools reconciliation still needs integration. Provider255 cause and the extra unrequested guesthalt remain unknown. Do not attribute either to hostneverSleep.

New actual harness faults were fixed at their source: targetJSON semanticbooleans serialized as integers (typedproducerd853527,60serializationchecks), read-only255 transport failures (explicit15-call retryadapter00065f2f4; writes/inputunchanged), and securefield select-all cleanup (boundedknownnonsecretBackspaceclear7675d1536). Full D8 physical campaign subsequently passed with independent profile/process/allup cleanup. None of these demonstrates a product permission failure.

[External VM-guide review](https://github.com/steipete/agent-scripts/blob/main/skills/vm-lab/SKILL.md) informed shared UI docs386d846. A host screenshot immediately found unrelated prltoolsdnetworkmodal covering a semanticallyactive target; dismissing the prompt independently restored an unobstructed testwindow. Add critical-transition visual checks alongside fresh target/process state, distinguish headless from GUI ScreenRecordingattribution, and use private short script launchers. Retain vm-lab lease controls and ESP32 physical proof.

# Disposable VM reliability audit — October 4, 2026

This is a source and record review, not a new physical product trial. Times are UTC unless marked Pacific.

The recurring cost comes from lessons that remain documentation or experimental
adapters rather than a reusable lab contract. Some failures were genuine product
integration defects; others were guest prerequisites, observation formats or
uncertain command responses. These need different fixes.

## Current evidence boundary

The latest accepted full parent campaign is the October 4 11:28:59 receipt for
signed product `88e6674e1`: physical remap, actual Secure Input passthrough,
distinct resumed worker and generated output release after worker crash while
physical q remained held. Initial and resumed canonical readiness were verified.
The last killed-worker report is a pre-crash running/held ledger, not graceful
shutdown evidence. Process absence and original profile restoration were checked.
See [plan](permission-reduction-plan.md), 11:38 checkpoint, and receipt
`/private/tmp/keypath-parent-readiness-harness/evidence/session-runtime/parent-campaign-1791113339.json`
(SHA256 `b681db3d6cb9715aae656bf3166d996d1f30e5a658551b97dc3854edd4dc9349`).

No physically held-Control Secure Input/D8 acceptance, actual OS sleep/wake,
actual tap timeout or console departure/return acceptance follows from that pass.
Old lease `8833` was destroyed before its deadline. Root reports a separate fresh
`ef2006f9` lease; old lease/boot receipts cannot authorize it. This review made no
guest, host, UI, fixture or credential actions.

## Recurrence matrix

| Failure | Dated evidence | Implemented fix and remaining gap |
| --- | --- | --- |
| Missing home after account creation | Oct 4: old `8833` home-result records explicit home creation and verification. Fresh `ef2006f9` has a new missing-home completion intent at **12:11:47**; root separately reports home ownership verified after reboot at12:19. Both frozen observers unconditionally `lstat(home)` at line51, while their create operation at179–192 runs `sysadminctl -addUser` without `createhomedir`. | **Implemented:** guarded one-off home completion and truthful observed-state reconciliation. **Gap:** the reusable creation protocol still cannot represent “owned account exists, home absent” as a valid partial result. Copying the old observer reproduced the failure; do not replay account creation or invent its exit status. |
| Guest Python/tools | Oct 4 **04:22**: fresh `13eda` bootstrap lacked usable Python/CLT/Homebrew. Later D8 source needed a framework-Python correction even after the lesson was documented. | **Implemented experimentally:** signed PSF framework Python, full pinned Peekaboo CLI/dylib/app bundle and tools-only bootstrap. **Gap:** canonical lab does not guarantee these prerequisites, and old harnesses still assumed `/usr/bin/python3`, which can launch a CLT installer. |
| Normal desktop and Automation | Oct 4 **05:00**: native username delivery was unreliable; **05:06**: an unexpected reboot required fresh login/Setup Assistant. `13eda` app switching failed despite AX/SR; later `8833` normal System Events consent and app switching passed. | **Implemented/verified:** exact full-name login route, normal Setup Assistant completion, Permissions checklist brought forward through Dock, separate Automation consent. **Gap:** no common admission result proves actual intended console, completed setup and working app switching. Reboot initiators remain unknown. |
| Artifact and permission identity | Oct 3 handoff already distinguished manifest source commit from binary provenance. Oct 4 **05:20**: Settings showed ON while the actual capability process reported false; a fresh post-authentication process later reported AX/effective input true. | **Implemented experimentally:** strict signed staging, receipt-bound account/boot/PID/nonce/hash guards, direct capability proof. **Gap:** canonical runtime promotion remains separate; another app copy's screenshot, tool grants or old process report cannot stand in for product capability. |
| Process queries and line framing | Oct 4 **11:18 checkpoint**: raw `ps` output contained LF while shell substitution removed it, refusing readiness. **12:03 checkpoint**: multi-column process capture discarded the actual D8 parent; separate wide fields matched it. | **Implemented:** narrow LF handling, separate executable/UID/arguments queries and explicit pre/post guards; inert regressions. **Gap:** shared observation formatting is not consolidated. Mocked outputs had missed real macOS/provider formatting. |
| Transport255 and uncertain mutation | Oct 3 **23:42**: crash trial refused on read-only transport255. Oct 4: two parent attempts refused before input; **11:55** parent-start response failed but delayed parent/worker appeared; **12:01** preflight failed before setup. | **Implemented:** staged receipts, independent cleanup and selected read-only diagnostics. **Gap:** outer SSH versus provider/guest255 is still unclassified. Failed response does not prove no mutation; launch reconciliation must precede any new launch. No automatic mutation replay. |
| Product lifecycle and sleep | Oct 3 **23:32**: legacy VHID polling stopped valid driverless input. Oct 4: AppDelegate completion failed, then worker LaunchServices completion failed; signed88 ultimately passed the full parent campaign. Sleep first returned wrapper79 without underlying result; later actual request returned71/NotPermitted, no cycle. | **Implemented:** backend-scoped safety polling, genuine AppKit startup completion, canonical parent readiness and preserved OS-command diagnostics. **Open:** actual timeout/console transitions. Sleep is an observed platform refusal consistent with the recorded sleep-disabled flag; provider suspend is not replacement proof. |
| Lease deadlines | Oct 4 **06:17**: `f9cd` was destroyed before the earliest provider expiry. By **10:41**, exact-binary review established `keep=true` bypasses that provider expiry predicate. `8833` was still destroyed before the actual lab deadline **12:06:38**. | **Implemented/documented:** distinction between provider printed idle deadline and hard lab authorization expiry. **Gap:** admission should expose that distinction clearly, without treating keep=true as a lab extension or universal provider guarantee. |

## Host awake policy versus guest sleep

The user deliberately keeps the mini awake for remote availability. That host
policy is preserved. It is not an established cause of the guest's refusal:
the guest separately exposed `/defaults/sleep-disabled=1`, while its user-level
`SleepDisabled=No` did not exclude that platform flag. Apple's published kernel
loads the device-tree property separately from user-disabled sleep. The observed
flag is consistent with the rejected guest request, but who supplied it and
exact running-kernel equivalence remain unproven. Do not change host sleep policy
or count provider suspension as guest OS sleep/wake acceptance.

## Why fixes keep being rediscovered

The canonical lab guide explicitly says experimental adapter commands are not
available in clean main. Its durable follow-ups still include promotion of the
account adapter and tools-only route. Documentation was promoted; runtime was
not. Each fresh lease therefore repeats prerequisites and manual verification.

Freezes protect source/signature provenance, but lease-specific scripts repeat
account, boot, deadline, artifact and dependency pins. A small correction produces
another worktree copy, manifest refresh, independent review and execution packet.
The final no-fixture timing packet required seventeen verified pins and still
produced no samples because transport failed. Manual orchestration and repeated
dependency audits consume the same finite lease time needed for physical tests.

Inert checks are valuable but did not establish real guest Python availability,
provider framing, complete process-query behavior, normal consent or AppKit
launch completion. Generic wrapper errors also hid underlying command results,
forcing a second diagnostic packet before the actual blocker could be classified.
These are concrete contract gaps, not evidence that every guarded test is slow.

## Changes made during this audit

The shared lab guide now documents the repeated account/home defect and corrects
stale parent-campaign summaries. A reusable, lease-parameterized **source-only**
[account/home helper](../../Scripts/experiments/session-runtime/public-account-home/README.md)
separates account observation from home completion, records a one-shot claim,
and reconciles lost responses without mutation replay. Ten regression tests
passed. Its actual transport and durable-journal adapters still require
integration and live validation; it is not yet a canonical vm-lab command.
The fresh guest home was repaired separately, not through this new helper.

## Proposed durable work — not implemented by this audit

1. **Typed admission and command results first.** Distinguish unavailable tools,
   incomplete owned home/setup, missing Automation when that route is used, stale identity, actual guard
   refusal, outer SSH failure, provider failure and unknown mutation outcome.
   Persist bounded nonsecret stage/return-code evidence. Unknown launch outcomes
   require owned-process reconciliation; mutations remain one-shot.
2. **Promote one reviewed lab adapter.** Share the account/home state model,
   selected-query/framing code, usable Python/tools inventory, current identity
   receipt and normal desktop/selected-automation postconditions. Preserve original QA,
   real credential restrictions, foreign-resource guards and exact cleanup.
3. **Freeze source; parameterize attempts through validated data receipts.** Keep
   source/dependency/signature hashes immutable. Supply fresh lease/provider,
   account, boot, deadline and artifact tuples as data instead of copying a new
   executable script for each lease. Retain unique operation journals and review
   actual source changes, not repeated literal substitutions.
4. **Use two explicitly different lanes.** A proposed prepared-runtime lane has
   verified tools and ordinary desktop/automation readiness for repeat product
   safety tests. A proposed pristine-installer lane retains clean first-run/TCC
   behavior for installer and onboarding acceptance. Neither lane's results may
   claim the other's first-run behavior. Complete one no-input readiness smoke
   check before admitting physical campaign input.

## Primary local references

- Shared lab [automation lessons](/Users/malpern/local-code/vm-lab/docs/automation-lessons.md): tools, session, Automation, power and promotion sections. The opening summary now distinguishes the later accepted parent campaign from earlier standalone evidence.
- [Permission reduction plan](permission-reduction-plan.md): dated October 4 checkpoints for discovery, transport, parent acceptance, framing, startup and sleep refusal.
- [Permission exploration handoff](/private/tmp/keypath-permission-footprint/docs/testing/permission-exploration-handoff.md): historical guest preparation and current lease checkpoint.
- `/private/tmp/keypath-public-guest-bootstrap-883343c6/guest_observer.py` and `/private/tmp/keypath-public-guest-bootstrap-ef2006f9/guest_observer.py`: `_user` and `guest_main` account creation, repeated missing-home contract.
- `/private/tmp/keypath-883343c6-home-result.txt` and `/private/tmp/keypath-ef2006f9-create-home-intent.json`: old completion versus fresh completion intent. Intent alone is not completion evidence.

Preserve temporary receipts until selected evidence is archived durably. This audit does not replace live acceptance, authorize mutation replay or declare proposed canonical lab features available.
