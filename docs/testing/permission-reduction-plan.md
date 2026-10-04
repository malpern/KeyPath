# Permission reduction: execution plan and model routing

Updated 2026-10-03 / 2026-10-04 UTC. Execution resumed at the user's request.
Mixed-model delegation is active; the implementation record retains chronology
and artifact hashes. See [pilot outcomes](mixed-model-permission-pilot.md).

## Latest checkpoint — 2026-10-04 00:09 UTC

- Sol high independently found and corrected five crash-recovery/acceptance gaps.
  Root verified the diff and committed `8fd1320b`; 8 targeted regressions pass.
- Full safe gate completed normally: main target 4,314 tests / 0 failures / 28
  skips. Only the 3 known home-row snapshots failed. The formerly stalled repair
  snapshot passed; the earlier 5 ownership/matrix/test-seam failures are gone.
  No full-suite pass is claimed. Baseline classification of the snapshots is open.
- Luna low built the frozen signed artifact; root independently verified it.
  Product source `8fd1320bc8123f1537e80bf6ea1c02f02d4e376a`, Kanata `0853689`.
  Executable `9f0e34353bab238d8d87e10692463b5332e58a5b0fe74da958fa8bbcec62251c`;
  archive `/private/tmp/keypath-session-mixed-crash.zip`, SHA256
  `83a3845bd458c299c055d3c721c452d5e3b91572be6bf710879eb6f44741b4a2`.
- Luna medium has exclusive hardware-operation ownership for guarded staging and
  parent/Secure Input/resume/held-crash campaign. All four passed on the final
  signed source. Root independently verified held-crash release while the same
  fixture run had submitted only its physical key-down. Reboot rerun underway.
- Both owned prepared candidates and the stopped source lease are destroyed;
  independent provider inventories confirm their three UUIDs absent. The one
  owned GUI lease remains for continuity and final worker cases.
- A second bounded Luna analysis located DL-11's missing generated-profile
  eligibility check. Existing default-catalog validation checks Kanata syntax,
  not session eligibility. No generated-profile support claim has been made.

## Position at pause (historical)

`Research complete → limited prototype acceptance about 70% → product hardening → onboarding`

The 70% is a planning estimate for bounded integrated acceptance, not a measured
percentage of shipping readiness or full Kanata feature parity. Broader device,
application and layout coverage is still open. The default backend has not changed.

- Research and rig feasibility: complete within their documented scope.
- Implemented locally: AX-first effective-access checks, opt-in session backend,
  backend-specific installer planning/readiness, canonical lifecycle supervision,
  configuration eligibility checks, repeat correction and safety fixes.
- Physical signed proof: ordinary remap, home-row tap/hold, unmapped typing,
  permission revocation/regrant, Secure Input pass-through, parent automatic
  resume and Caps feasibility. These span several documented binary versions.
- Newest completed case: repeat on binary `32c5781f…`, run
  `session-3826bf9efd914cae`: 10 input/10 output events, nine characters,
  exact physical fixture trace, released target/output state and clean stopped report.
- Source checkpoint before this plan: `3e402d4a`; local Kanata `0853689`.
  Final signed rebuild was interrupted deliberately (exit 143); no final artifact
  from that build is accepted. Last accepted signed binary is from product f33beacf.
- Latest narrow checks: 35 matrix/ownership/safety tests and 10 helper/snapshot
  isolation tests passed. Rust bridge's two real-engine tests passed.
- Broad gate remains incomplete: its snapshot scan hang has a tested isolation
  fix; three home-row snapshot differences remain unclassified. References have
  not been overwritten. Physical held-output worker crash refused before input
  on USB observation transport exit 255; it has not passed.

Preserve all three experimental worktrees. Original restrictions still apply:
guest-only testing, no host security/KeyPath deployment, no TCC database writes,
no ESP32 flashing, no persistent USB autoconnect changes, no upstream push/PR.
Approval policy is `never`; this does not expand task authorization. Credentials
remain scoped and in memory; never read `evidence/auth-image.base64`.

At pause the owned GUI lease is `cbx_92ff62339803` on `malpern@mini`, with source
lease `cbx_8bd54247c73b` on mini and two stopped prepared candidates. Leases expire
around 17:09/17:20 Pacific on October 3. Do not assume they survive the pause.
On resume inspect ownership and expiry before touching any resource; if expired,
reconcile/reap only ours through vm-lab and admit a fresh lease when needed.
The build has stopped; the completed repeat harness stopped its worker cleanly.

## Routing levels

These are workload recommendations, not guarantees of model correctness.
Exact available model IDs are shown so routing is unambiguous.

| Role | Model / effort | Appropriate work | Escalation |
| --- | --- | --- | --- |
| Routine operator | `gpt-6-luna`, low | Fixed scripts, small evidence summaries, hash/status comparisons, documentation reconciliation | Unexpected result, ambiguous state or any proposed script/code change → Sol |
| Focused analyst | `gpt-6-luna`, medium | Classify known failures against explicit criteria, run established test matrices, extract documented facts | New causal hypothesis or safety/permission judgment → Sol |
| Orchestrator / implementer | `gpt-6.1-sol`, medium | Plan ownership, focused implementation, dependency ordering, evidence review | Cross-module behavior, concurrency or failure containment → Sol high |
| Systems implementer / reviewer | `gpt-6.1-sol`, high | Swift concurrency, Rust ABI, TCC identity, installer/lifecycle invariants and mapping recovery | One well-investigated unresolved failure or conflicting architectural evidence → Astra high |
| Difficult escalation | `gpt-6-astra`, high | Cross-process/macOS failures, competing causal explanations, difficult architecture tradeoffs | Use only for a bounded diagnosis; return findings to Sol |

Use scripts directly for deterministic operations whenever no model decision is
needed. Do not create an agent merely to wait for a build. Start with the lowest
appropriate effort; a routine operator is not authorized to improvise a fix.

## Ordered work and verification gates

“Verifier” means review the actual diff, result or independent postcondition;
an agent's success summary alone is insufficient. No dependent step starts until
its gate passes. An intentionally limited prototype can close its acceptance
without pretending the feature backlog is complete.

| Step | Work / status | Worker level | Orchestrator verification before proceeding |
| --- | --- | --- | --- |
| 1 | Reconcile pause state, stopped build, source hashes, VM ownership/expiry and fixture state. Complete. | Luna low; Sol owns any recovery decision | Known lease identities only; no worker/build still active; no stale artifact accepted; preserve worktrees |
| 2 | Triage three home-row snapshot differences against an isolated baseline. Open; unrelated source/reference files unchanged. | Luna medium for reproduction; Sol medium for diagnosis/fix | Compare actual images and baseline; keep references unless an intentional visual change is established; record unrelated blocker if unresolved |
| 3 | Consolidate and freeze remaining source changes; run appropriate safe tests and broad gate after the hang fix. Main target passed; three unchanged snapshots remain failed. | Sol medium for edits; Luna low for existing checks | Review canonical permission/installer/liveness ownership, targeted results and broad-gate failures; no claim of a full pass after timeout |
| 4 | Build and sign frozen candidate; verify archive, executable identity and source provenance. Complete on frozen source8fd1320b. | Luna low using existing build script | Sol medium checks signature, explicit commit/hash record and no host deployment; no concurrent broad Swift build |
| 5 | Stage exact signed artifact in owned guest and check effective approval after update. Complete, exact signed artifact staged without guest resigning. | Luna low using guarded staging harness | Sol medium checks ownership, signature/hash, independent process capability and no privilege contamination |
| 6 | Re-run final-source physical ordinary remap, home-row tap/hold, unmapped typing and repeat. Earlier versions passed. | Luna medium, established harness only | Sol medium checks fixture trace, focus, fresh PID/nonce/hash/boot, counters and clean stopped report |
| 7 | App-managed remap → Secure Input pass-through → automatic resume. Passed on final9f0e3435; unchanged-permission reboot rerun underway. | Luna medium, established harness only | Sol high checks lifecycle/report identity and independent physical result; protected-input remapping remains an accepted limitation |
| 8 | Held-output worker crash and parent release before physical key-up. Passed on final9f0e3435 with independent release-during-hold evidence. | Sol high owns experiment; Luna may run fixed harness | Sol high independently checks kill target, actual emitted-key release timing, fixture still held and empty target state; escalate ambiguous failure to Astra |
| 9 | Held-modifier Secure Input transitions, tap timeout, sleep/wake and session recovery. Open. | Sol high designs bounded cases; Luna medium executes approved scripts | Sol high checks no stuck output, correct reset/restart and ordinary typing during failure; record hardware/session limits |
| 10 | Controlled unchanged-permission reboot and USB reconnect continuity on final app. Research proof exists; integrated acceptance open. | Luna medium with existing lab controls | Sol high checks new boot, startup settling, exact attachment, same approved identity and actual remap without permission mutation |
| 11 | Evaluate generated/default profiles against parser-backed backend eligibility (DL-11). Open before enabling backend more broadly. | Luna medium enumerates profiles; Sol medium fixes eligibility | Sol high verifies supported semantics and explicit rejection; no silent feature removal or privileged fallback |
| 12 | Close bounded prototype decision and reconcile current evidence. Open. | Luna low prepares evidence table | Sol high decides verified/failed/untested, remaining gates and customer permission claims; no default/release declaration while safety gates remain |
| 13 | Collect artifacts and destroy/reconcile all four owned lab resources. Three resources destroyed/independently absent; GUI lease cleanup follows continuity. | Luna low, ownership-guarded controller only | Sol medium independently checks all four provider UUIDs absent and host fixture policy unchanged; preserve research/source/evidence |
| 14 | Caps product mapping ownership and recovery (DL-01/DL-09). Feasibility passed; integration open. | Sol high; Astra only for unresolved OS/lifecycle design | Independent Sol high review of existing-map preservation, F18 conflicts, stop/crash, protected input, reconnect and reboot; no host map changes |
| 15 | Common media/brightness/international coverage and Apple Fn equivalents (DL-04/DL-05). Follow-up. | Sol medium for adapter/action work; Sol high for Fn semantics | Luna medium collects device cases; Sol high reviews actual input/output separately and permission impact; firmware-only Fn remains a boundary |
| 16 | Mouse output (DL-06). Follow-up implementation gap. | Sol medium; Sol high reviews held buttons/async cleanup | Physical output and dragging/scroll/multi-display checks, generated-event tagging and crash release; record added requirements |
| 17 | Unicode/text output and optional clipboard fallback (DL-07). Follow-up. | Sol medium; Luna medium runs compatibility matrix | Sol high checks composition, app compatibility, clipboard preservation and explicit fallback behavior |
| 18 | Limited per-device normalization (DL-03). Research follow-up. | Sol high; Astra if competing architecture options remain | Two-device proof, collisions/reconnect and stated attribution limits; no claim of arbitrary per-keyboard support |
| 19 | Broader keyboard/layout/app compatibility (DL-10). Open; some real hardware required. | Sol medium defines matrix; Luna medium executes available cases | Sol high separates VM evidence from built-in/USB/Bluetooth physical Mac evidence; unavailable hardware is untested, not passed |
| 20 | Session/prelogin/FileVault boundary (DL-08). Accepted limitation. | Luna low maintains documentation | Sol medium checks claims; no implementation attempt to bypass the boundary |
| 21 | Onboarding and installer UX based on verified reduced requirements. Deferred until permission/safety gates close. | Sol medium for UX/design and implementation; Luna medium for scripted first-run QA | Sol high verifies customer steps match observed requirements and unsupported-profile choices are clear; no UI promises based on feasibility alone |
| 22 | Consider isolated Kanata or Karabiner contributions after local validation. Deferred. | Sol high for extraction/upstream fit; Luna medium for current upstream facts | Sol high checks independent usefulness and local evidence; submitting/pushing remains outside current authorization |

Steps 14–19 are tracked follow-ups; decide their scope after step 12. They do not
silently become requirements for full feature parity. Onboarding follows the
verified permission and supported-feature decision, not an indefinite promise
to implement every advanced feature first. See the [gap register](driverless-gap-register.md)
for all 12 gap IDs and their detailed acceptance criteria.

## Orchestrator contract

Use this chat as the orchestrator after resume; a separate user-visible thread
is unnecessary unless requested. Start no workers while paused. Keep the
orchestrator on Sol medium where practical, increasing effort for safety reviews.
The current root model is not changed by this document; child agents can use the
explicit model/effort overrides available in this session.

Each delegated task receives a compact packet: objective, source checkpoint,
owned paths/lease, restrictions, specific input files, allowed actions, acceptance
criteria and stop/escalation conditions. Prefer a fresh bounded context instead
of forwarding the full conversation. Workers read applicable AGENTS.md and
necessary skills; compact context must not omit those requirements.

Each result returns: changed paths/commit if applicable, checks actually run,
evidence paths and identifiers, pass/fail/untested status, remaining concerns and
usage if exposed. Never return credentials or broad raw logs. The orchestrator
reads the evidence/diff and validates the gate before merging the result or
dispatching dependent work. Avoid redoing the whole task as “verification.”

Only one agent may operate the shared VM/ESP32 at a time. Only one agent may
write a given worktree or compile broadly at a time. Concurrent code agents need
separate worktrees and explicit integration ownership. Use parallel agents for
independent read-only investigations when useful; the four-slot limit includes
the orchestrator. Do not manufacture parallelism around a sequential hardware
campaign. Scope in a prompt is an instruction, not a technical permission boundary.

Luna escalates immediately on an unexpected destructive/stateful result, unclear
ownership, credential/focus ambiguity or a proposed architecture change. Sol
escalates a properly investigated hard failure with a concise causal record,
rather than repeatedly retrying. Mutations are never blindly replayed; read-only
retry behavior remains bounded by the existing harness.

## Savings hypothesis and measurement

Mixed-model delegation should reduce expensive-model usage for repetitive work.
It does not guarantee fewer total tokens: each worker consumes instructions,
context and output, and the orchestrator consumes review tokens. Small tasks and
long shared-state dependency chains may cost more to delegate. Reasoning effort,
context size, retries and verifier rework matter as much as the model name.

Pilot the next five suitable completed task packets on resume. Record model and
effort, input/output/reasoning/cached tokens where exposed, wall time, retries,
review effort and first-pass gate acceptance. Include orchestrator usage in the
total. Compare with comparable prior single-agent work where accounting exists;
otherwise report observed spend and quality without inventing a savings percentage.
Keep routing only where it saves cost/usage at the same verification standard.

OpenAI describes Sol as the balanced model, Luna as focused/high-volume and
Astra as the strongest option for demanding work: [model guidance](https://developers.openai.com/api/docs/models).
Official guidance explicitly warns that subagents can increase tokens, especially
with shared mutable state or sequential dependencies: [multi-agent guidance](https://developers.openai.com/api/docs/guides/responses-multi-agent).
Usage assessment must include root and subagent calls, retries and reasoning:
[usage accounting](https://developers.openai.com/api/docs/guides/agents-api/observability).
API prices are not a promise of proportional ChatGPT subscription quota savings.
