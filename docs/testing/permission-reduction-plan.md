# Permission reduction: execution plan and model routing

Updated 2026-10-03 / 2026-10-04 UTC. Execution resumed at the user's request.
Mixed-model delegation is active; the implementation record retains chronology
and artifact hashes. See [pilot outcomes](mixed-model-permission-pilot.md).

## Active driverless-only experiment — October 3, 2026 Pacific

The user approved a separate driverless-only experiment. Active worktree:
`/private/tmp/keypath-driverless-only`, branch `experiment/driverless-only`,
branched from preserved checkpoint `234f7b87`. The accepted implementation,
research, rig, and agent worktrees remain intact. Fresh owned lease `cbx_896c0d2d8565` is active on `malpern@mini`,
expiring 2026-10-04 03:32:41 UTC. The corrected frozen product source is
`6a35b48dd1c5895a572414d0453594c14e8f7f58`. Approval is `never`, full
filesystem access and network enabled; the original guest-only restrictions
still apply. No host deployment, permission changes, upstream push, or PR.

`Research ✓ → driverless-only simplification ✓ → validation [active] → clean VM/safety acceptance → Caps integration → onboarding`

Earlier bounded acceptance is estimated at 80%, not shipping readiness. The new
simplification has its own gates; source edits alone do not inherit old physical
or test passes. The prior artifact remains the rollback/comparison checkpoint.

| Gate | Work / current state | Worker level | Required independent verification |
| --- | --- | --- | --- |
| D1 | Separate checkpoint/worktree. Complete. | Sol medium | Existing checkpoint unchanged; isolated branch and local Kanata revision recorded |
| D2 | Session is the sole selectable runtime; privileged lifecycle and installer execution removed. Source integrated; safe regression checks passed. | Sol medium; Sol high reviews boundaries | Tests prove flag/env cannot select DriverKit, malformed plans cannot invoke broker actions, and success requires current session readiness |
| D3 | Fresh supported profile defaults; existing profiles preserved; canonical eligibility before managed writes. Source integrated; safe regression checks passed. | Sol medium | Actual fresh generated profile accepted by real Kanata bridge; Caps/media/filter candidates rejected before config/store mutations |
| D4 | Driver/helper/daemon/launcher absent from frozen signed comparison artifact; root independently verified. Corrected artifact signed and independently verified in the fresh guest. | Luna medium for bounded edits; Sol reviews | Strict source/artifact contract, Developer ID/team/hardened signatures on remaining components, recursive forbidden-resource absence |
| D5 | Corrected source6a35b48dd passed broad safe gate5: 5,292 checks, zero failures/warnings; focused lifecycle24 passed. Three old snapshots remain separately unresolved. | Sol owns fixes; deterministic scripts execute | No skipped real-bridge acceptance; classify failures rather than copy expectations blindly; old snapshot failures remain separately unresolved |
| D6 | Frozen corrected6a35b48dd build signed and root-verified; released for owned guest testing. Earlier f274 artifact remains comparison only. No host deployment. | Luna low with fixed script | Root records commit/Kanata/archive/binary identity and verifies actual artifact |
| D7 | New clean admitted VM; normal app launch without opt-in backend flag; first-run remap and unchanged-permission continuity. Active: guest artifact identity/payload passed; desktop login waiting for compliant credential transport fix. | Luna medium established harness; Sol owns anomalies | Owned lease, genuine ESP32 events, fresh nonce/PID/hash/boot, correct output and cleanup; no inherited driver/helper installation |
| D8 | Held-modifier transitions, tap timeout, sleep/wake and session departure. Open. Persistent target sourcea3b0847 independently reviewed; Foundation guard checks passed, isolated build/sign underway; physical phase harness pending. | Sol high designs/reviews; Luna executes bounded scripts | Physical output release and fail-open behavior; no timeout/SIGKILL substitution or provider suspend claimed as OS sleep |
| D9 | Decision and cleanup. Pending. | Sol high decision; Luna low cleanup | Separate verified/failed/untested semantics, preserve profile/worktree, independently absent owned resources and unchanged USB policy |
| D10 | Caps substitution ownership/integration after runtime stabilization. Planned follow-up, feature retained. | Sol high design/recovery review; Sol medium implementation; Luna hardware execution | Collision-safe device-scoped mapping, restore only owned state, stop/crash/reconnect/reboot/protected-input acceptance |
| D11 | Revisit onboarding UX after reduced permissions and Caps prerequisites are verified. Deferred. | Sol medium implementation; design review at appropriate level | Normal fresh installer flow reflects actual consent and supported first win; no unavailable Caps retry loop |

Current simplification estimate: **70%**, independent of the older 80% bounded
checkpoint. Corrected frozen source `6a35b48dd` passed **5,292 safe checks / zero
failures / zero compiler warnings**, plus 24 focused lifecycle checks. Lifecycle
ownership fixes are integrated and independently reviewed. The fresh guest
verified the exact binary hash, strict signing and absence of driver/helper
payloads and system extensions. Physical runtime and reboot checks remain.

The guest login helper was stopped before credential loading because its existing
transport writes a plaintext temporary file. A reviewed memory/stdin-only fix is
required before continuing desktop setup; no password was written or exposed.

The three original home-row snapshot failures are excluded from the safe gate.
Their UI source, mock inputs and reference images are byte-identical to verified
`origin/master` (`d5581754`); rendering parity still needs a matching baseline run.

Frozen signed comparison archive `/private/tmp/keypath-driverless-only-f274374e9.zip`
SHA256 `ae522ffb1de27c22fb5393d050b5b7c0a66b5b07d62470772d47b68016e47a01`,
main executable `6cbe01a2a95412e2ea1874832efb9fb8e1da076bdb7348df15ad3d36bbc7fc1d`.
Root independently verified strict deep signing, stable Developer ID/hardened
identities and forbidden-payload absence. Not notarized; guest-only, not deployed.

Safety review found and corrected asynchronous lifecycle reentrancy. Complete
start/stop/restart admission, intent generations, cleanup of late launches,
cancellation-safe accepted stops and generation/PID/nonce-bound supervision are
integrated. Healthy repeated start re-adopts supervision. Source tests and signing
passed; actual output release remains a physical acceptance requirement.

A read-only dependency audit estimates roughly10,000–11,000 additional legacy
Swift lines may be removed after wiring changes. Removal sequence: helper/launcher
executables, helper adapters (preserve duplicate-app discovery), daemon adapters,
legacy wizard/VHID pages, privileged install implementations, PID leftovers.
Preserve Karabiner import/conversion, app launcher UI, shared utilities, historical
pure contracts and all session cleanup/transaction machinery. No bulk deletion
before signed VM stabilization.

Source review found and fixed a real app-only input omission: generated app
aliases were unused when their inputs were absent from global collections.
Those inputs now enter the captured source/base map; the existing transactional
Unicode-refusal regression passes before file/journal/reload changes. All six
new default goldens were individually reviewed, with the original full catalog
golden retained separately to preserve historical generator coverage.

The narrow virtual-input switch fix is integrated: real TCP/passthrough engine
tests prove fallback → active app branch → fallback with down/up output. All
branches and virtual definitions remain validated; unsupported media/Unicode
and other predicates remain rejected. The rebuilt bridge also accepts only layer release (not key release), with
real-engine ownership tests. The core save/pack/rollback gate passed 176 cases;
the third broad gate verifies these changes but retains the four failures above. Signed/physical app-specific acceptance
is still pending. Unit-test application launches are blocked to keep this gate
from opening or modifying host applications. The fresh VM is admitted; only the established validated rig is released for D7.

Do not imply default media keys or raw Caps are now supported. Built-in definitions
remain available, fresh enabled defaults are conservative, and existing profiles
are preserved with explicit unsupported-profile failures. Caps automatic mapping
ownership remains a planned follow-up after runtime stabilization (DL-01), not a
removed feature. Restore a Caps-based first-success tour only after owned mapping,
collision handling and recovery pass. Onboarding UX
redesign follows verified reduced requirements, as requested.

## Previous bounded checkpoint — 2026-10-04 00:21 UTC (historical)


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
  fixture run had submitted only its physical key-down.
- Unchanged-permission reboot continuity passed on final binary9f0e3435,
  parent remap b091c2c6c4e44b9c. Boot1791066067 →1791072532. Explicit cleanup
  confirms stopped/empty worker ledger, no exact app processes and bytewise
  restored original configuration. First postboot target-focus refusal is excluded;
  the rig now explicitly activates the target and independently checks its state.
  All five final-source worker cases passed: remap2b095459a4754d89,
  HRM tap4fc7a7a1a8a84742, HRM hold670bea4a4e50423c, unmapped24c28355f5b241c6,
  repeat14ccd6b0a95a41db. Root checked all acceptance fields and each stopped,
  empty-held ledger. Repeat had10 input/10 output, nine characters.
- All four owned VM resources are destroyed. Root independently checked both
  provider inventories; all four UUIDs absent. Fixture is detached and host
  policy remains ask with no automatic VM binding. Cleanup evidence:
  evidence/session-runtime/mixed-model-final-cleanup.json. GUI deletion emitted
  a guest SSH hydration-marker warning; actual resource deletion was verified.
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
| 6 | Re-run final-source physical ordinary remap, home-row tap/hold, unmapped typing and repeat. Passed on final reviewed9f0e3435 after reboot; each cleanly stopped. | Luna medium, established harness only | Sol medium checks fixture trace, focus, fresh PID/nonce/hash/boot, counters and clean stopped report |
| 7 | App-managed remap → Secure Input pass-through → automatic resume. Passed on final9f0e3435; unchanged-permission reboot remap also passed. | Luna medium, established harness only | Sol high checks lifecycle/report identity and independent physical result; protected-input remapping remains an accepted limitation |
| 8 | Held-output worker crash and parent release before physical key-up. Passed on final9f0e3435 with independent release-during-hold evidence. | Sol high owns experiment; Luna may run fixed harness | Sol high independently checks kill target, actual emitted-key release timing, fixture still held and empty target state; escalate ambiguous failure to Astra |
| 9 | Held-modifier Secure Input transitions, tap timeout, sleep/wake and session recovery. Open. | Sol high designs bounded cases; Luna medium executes approved scripts | Sol high checks no stuck output, correct reset/restart and ordinary typing during failure; record hardware/session limits |
| 10 | Controlled unchanged-permission reboot and USB reconnect continuity on final app. Final-app reboot/remap passed; separate integrated reconnect remains open. | Luna medium with existing lab controls | Sol high checks new boot, startup settling, exact attachment, same approved identity and actual remap without permission mutation |
| 11 | Evaluate generated/default profiles against parser-backed backend eligibility (DL-11). Open before enabling backend more broadly. | Luna medium enumerates profiles; Sol medium fixes eligibility | Sol high verifies supported semantics and explicit rejection; no silent feature removal or privileged fallback |
| 12 | Close bounded prototype decision and reconcile current evidence. Open. | Luna low prepares evidence table | Sol high decides verified/failed/untested, remaining gates and customer permission claims; no default/release declaration while safety gates remain |
| 13 | Collect artifacts and destroy/reconcile all four owned lab resources. Complete; all four UUIDs independently absent and USB policy unchanged. | Luna low, ownership-guarded controller only | Sol medium independently checks all four provider UUIDs absent and host fixture policy unchanged; preserve research/source/evidence |
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

## Recommended next experiment (proposal, not yet executed)

The user asked whether to remove the other backend in an experimental worktree.
Recommendation: preserve this accepted checkpoint/worktree and run a separate
driverless-only experiment. First make session runtime the only executable path
and explicitly reject unsupported profiles; then remove driver-specific install,
helper/service and VHID safety glue in reviewed stages. Retain Kanata's engine
and shared permission/lifecycle authorities. This can reveal whether the simpler
installation also yields a simpler maintainable architecture.

Judge success against an agreed supported-feature subset and the open safety,
Caps ownership, generated-profile and real-device gates. A compiling branch or
a few remaps are insufficient. Keep Secure Input/prelogin limits explicit.
Deletion does not solve OS/device-attribution boundaries. The current worktree,
main checkout and all evidence remain preserved; no driverless-only conversion
has been performed merely in response to the question.
