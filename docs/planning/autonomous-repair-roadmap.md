# Autonomous Repair Roadmap (Phase 2 — Deferred, Not Abandoned)

**Status:** Ambition on hold — gated on
[installer-reliability-phase1.md](installer-reliability-phase1.md) exit criteria
**Date:** 2026-07-06

## The Ambition

KeyPath should eventually be **self-healing**: it continuously validates that
the whole stack (VHID driver → daemon → kanata runtime → TCP → input capture →
permissions) is actually working, and when something degrades it fixes it
before the user notices their keyboard misbehaving. The end state is a user
who never thinks about services, daemons, or permissions after first-run —
the keyboard just keeps working.

This goes **beyond industry practice**, deliberately. Karabiner-Elements ships
a user-clicked "restart service" menu item; Rogue Amoeba ships a Repair
button. Nobody in this space does continuous autonomous repair. That is partly
because it is genuinely hard on macOS — and partly an opportunity: "the
keyboard remapper that never breaks" is a differentiator no competitor has.

## Why It Is Deferred (Honest Assessment)

The 18-month installer/repair instability loop was substantially *caused* by
premature autonomy. The machinery autonomy requires — throttles so repair
doesn't hammer the system, restart-window heuristics so repair doesn't fight a
service that is still starting, watchdogs to trigger it, retry budgets to
bound it — was where most regressions lived (see the Feb 2026 false-green
incident, the stale-throttle interaction, the watchdog misattributing a helper
stall to kanata). Each autonomous mechanism is another writer to shared system
state and another reader that can hold a stale view.

Two failure classes make naive autonomy actively harmful:

1. **Unfixable states.** BTM corruption, Tahoe driver-approval loops, TCC.db
   desync, endpoint-security software blocking the dext — no app can fix
   these. Autonomous repair against them is a retry loop that burns CPU,
   spams logs, and can make things worse (repeated unregister/register cycles
   are themselves documented to corrupt SMAppService state).
2. **Approval-gated states.** When macOS wants a human to click something,
   autonomy has nothing to do. Detecting this reliably *is* the hard part —
   we got it wrong repeatedly (wizard dead-ends, #931/#937/#961).

Conclusion: autonomy is a *policy layer* that must sit on top of a
detection/repair substrate that is already boringly reliable. Phase 1 builds
that substrate. Autonomy without it re-opens the loop.

## Prerequisites (Hard Gates)

Do not start Phase 2 work until **all** of these hold:

1. **Phase 1 exit criteria met** — executable state matrix, one liveness
   predicate, postcondition-proven one-shot repair, lint ratchets, and a
   sustained zero-regression stability window (≥ 2 release cycles).
2. **Repair telemetry exists and has accumulated.** Every manual repair
   attempt logs: triggering state-matrix row, action taken, postcondition
   outcome, duration. We need this data to know which (row → action) pairs
   have a near-100% success rate — those are the only candidates for
   automation.
3. **Detection has a measured false-positive rate near zero.** An autonomous
   system that fixes non-problems is worse than none (the Feb 2026 "Kanata
   Service Stopped" false alert would have triggered a pointless — possibly
   harmful — autonomous restart).
4. **Every state-matrix row is classified** as `auto-fixable` /
   `user-approval-required` / `unfixable-escalate`, with tests.

## Design Principles for the Autonomy Layer

When we build it, these are the rules. They are written down now so the
ambition survives context loss without the mistakes recurring.

### 1. Autonomy ladder — earn each rung

Roll out per (state-matrix row, repair action) pair, not globally:

| Tier | Behavior | Promotion criterion |
|------|----------|---------------------|
| 0 — Observe | Detect + log only | default for every new detection |
| 1 — Notify | Surface degraded state, offer one-click repair | detection FP rate ≈ 0 over a release cycle |
| 2 — Confirm | Prepared repair, executes on a single user click | manual repair success rate for this pair ≥ 99% in telemetry |
| 3 — Autonomous | Fix silently, notify after the fact | tier-2 history clean over a release cycle; action is idempotent + reversible |

A pair can be demoted instantly on any incident. Tier is data
(configuration + telemetry-driven), not code branches.

### 2. Only idempotent, non-escalating actions can reach Tier 3

Candidates, ranked by likely safety (validate against telemetry, not
intuition):

- **Likely safe:** TCP config-reload retry; `launchctl kickstart` of a crashed
  kanata; VHID daemon restart when the driver extension is healthy but the
  daemon socket is gone.
- **Maybe, with strict bounds:** re-register after *provably* stale
  SMAppService `.enabled` (the one case where the throttle-bypass logic
  earned its keep).
- **Never autonomous:** binary replacement / reinstall; helper
  unregister/register cycles; anything touching TCC; anything whose failure
  mode is "keyboard stops working mid-keystroke"; anything in an
  approval-gated or unfixable row.

### 3. Structural safeguards (non-negotiable)

- **Single writer:** all autonomous mutations flow through the same
  `InstallerEngine`/`PrivilegedOperationsRouter` path as manual repair — same
  postconditions, same reporting. No parallel "quick fix" path (that is how
  the 5-repair-paths era started).
- **Global budget + circuit breaker:** N autonomous actions per hour; any
  postcondition failure trips the breaker for that pair and falls back to
  Tier 1 (notify). The breaker state is visible in the UI.
- **Terminal-state respect:** `pending approval` and `unfixable` rows are
  hard stops. The autonomy layer's most important skill is *knowing when to
  do nothing* — surface a guided manual step instead.
- **Kill switch:** one user-visible toggle ("automatic repair") that drops
  everything to Tier 1. Default-on only after a full release cycle of opt-in
  dogfooding.
- **Audit trail:** every autonomous action is logged with before/after
  snapshots and surfaced in a "what KeyPath did" view. Silent must never mean
  invisible.

### 4. Continuous validation is a separate, read-only concern

The "continuous testing" half of the ambition — actively proving the stack
works end-to-end (e.g., periodic synthetic-input probes through the VHID
device, config round-trip checks) — is valuable independently of autonomous
*repair* and should ship first. It is read-only, so it carries none of the
risk. Its output feeds the same `SystemSnapshot`, raising detection quality
for both manual and (later) autonomous repair.

Ideas parked here:

- Synthetic keystroke probe through kanata's virtual device to a test sink,
  proving true end-to-end input capture (not just TCP liveness).
- Config reload canary: after every config apply, verify a marker rule is
  live via TCP introspection.
- Post-update self-check: after app/kanata updates, proactively verify TCC
  identity stability held (Workstream 4 contract, checked at runtime).
- Wake/unlock probes: sleep-wake and fast-user-switch are historically where
  kanata-on-macOS breaks (upstream #1357, #1539); probe after those events
  specifically.

## Success Metrics (define before building)

- **MTTR** for degraded states: target seconds (autonomous) vs. minutes/hours
  (user notices → clicks repair).
- **Autonomous action success rate** (postcondition proven): ≥ 99.5%; below
  that, demote the pair.
- **False-intervention rate** (acted when nothing was wrong): ~0; any incident
  is a P1 against the detection layer.
- **Support-load proxy:** installer/repair-related bug reports per release,
  which should fall through Phase 1 and stay flat-or-falling as tiers rise —
  if autonomy raises it, the ladder is being climbed too fast.

## Relationship to Phase 1

Phase 1 is not a retreat from this ambition; it is the only credible route to
it. Everything Phase 1 builds — the single snapshot, the executable matrix,
the postcondition-proven repair verbs, the telemetry, the lint ratchets — is
exactly the substrate the autonomy layer needs. What Phase 1 removes
(watchdog-triggered fixes, throttle heuristics) is the *ad hoc* autonomy that
grew without these foundations and caused the loop.

Revisit this document at each Phase 1 exit review.
