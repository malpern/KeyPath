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
| Final physical parent campaign | Luna medium | In progress at 00:03 UTC. | Root must inspect actual hardware/report evidence before accepting and dispatching dependent work. |

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
