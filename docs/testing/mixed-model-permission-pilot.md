# Mixed-model permission investigation pilot

Started 2026-10-03 23:50 UTC following the user's explicit resume instruction.
This chat is the orchestrator. No separate user-visible thread was created.
Workers received bounded task packets instead of the full conversation. Root
retains gate decisions, source integration and hardware-operation ownership transfer.

| Packet | Model / effort | Outcome | Root verification |
| --- | --- | --- | --- |
| Checkpoint/evidence audit | Luna low | Correct test counts, repeat proof and unaccepted interrupted build identified. | Compared actual evidence/checkpoint; clarified that f33beacf is product source, not an executable hash, and later HEAD includes docs. |
| Home-row snapshot triage | Luna medium | Unchanged view/test/references and identical 52 px dimension difference confirmed; cause unproven. Time-bounded after prolonged investigation. | Full rerun reproduced only these three snapshots; no reference overwrite or baseline-pass claim. |
| Frozen checkpoint build | Luna low | Build/signature/archive succeeded on 3e042fef. | Independently checked signature and hashes; retained as checkpoint only after safety review found fixes. |
| Crash safety review | Sol high | Found five material recovery/acceptance gaps. | Root traced ledger freshness, read/kill ordering, dead-worker stop, key-up publication and physical-hold proof. |
| Bounded crash correction | Sol high | Corrected gaps, documented durable bug, 8 targeted tests passed. | Root reviewed diff and actual test log, committed 8fd1320b; full main target then passed all 4,314 tests. |
| Default-profile eligibility analysis | Luna medium, two-minute limit | Located missing eligibility assertion in canonical generated-profile test and existing validator entry points. | Root inspected parser whitelist and generation test. Still requires actual generated-profile execution. |
| Final signed build | Luna low | Reviewed-source build/signature/archive succeeded on 8fd1320b. | Root independently checked exact signature/source/binary/archive hashes before staging. |
| Final physical parent campaign | Luna medium | All four cases passed on reviewed binary9f0e3435. | Root independently verified exact physical hold/release timing and trace; separate cleanup audit below. |
| Parent cleanup evidence audit | Luna low, read-only and parallel to reboot | Correctly distinguished killed-worker durable ledger from live-process evidence; identified missing byte-verification of profile restoration and process scan completion. | Root added explicit process success sentinel and bytewise restored-profile comparison to the next campaign. First campaign restoration remains attempted, not byte-verified. |
| Remaining safety case design | Sol high, read-only and parallel to reboot | Proposed five bounded held-modifier/timeout/sleep/session cases with explicit missing harness support. | Root checked actual worker exit paths and recorded cases as unexecuted in gap register. |
| Postboot continuity | Luna medium | Initial focus guard refused before input; corrected target activation allowed app-managed remap and verified cleanup to pass. | Root independently checked new boot, binary hash, exact physical trace, stopped report, empty process list and bytewise profile restoration. |
| Final five-mode physical campaign and cleanup | Luna medium | All five passed after reboot; owned GUI resource deleted, with guest SSH hydration-marker warning. | Root checked each exact binary/boot/trace and stopped empty ledger, then independently verified all four owned UUIDs absent and USB policy unchanged. |

No precise input/output/reasoning token accounting was exposed by these agent
results. Usage and cost savings remain unknown; no percentage is claimed. The
root's review and retries must be included in any later accounting. API pricing
ratios do not establish ChatGPT quota savings.

Early routing lessons: fixed audits/build scripts fit Luna low. Bounded source
lookup fits Luna medium; open-ended diagnosis needs a time limit and escalation.
Sol high was justified for the cross-process cleanup review and implementation.
No Astra escalation was needed. Deterministic checks ran directly when a separate
agent would add little value. Parallel independent reviews/builds were useful;
only one broad Swift operation and one hardware operator ran at a time.

The acceptance standard is unchanged: a worker's summary is not a substitute for
actual hashes, tests, exact physical trace and independent target observations.
