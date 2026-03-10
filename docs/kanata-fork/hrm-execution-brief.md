# HRM Execution Brief

This document is a standalone brief for implementing the next round of
home-row-mod (HRM) improvements in kanata for KeyPath.

It is written for an agent with no prior conversation context.

## Purpose

The goal is to push kanata's tap-hold behavior closer to the best
"timeless HRM" setups seen in ZMK and QMK while staying realistic about
what host-side software can do.

This work is focused on **kanata engine behavior**, not KeyPath UI.
KeyPath can expose settings and presets, but the remaining high-value HRM
gaps are in the tap-versus-hold decision logic itself.

## Why This Work Matters

Home row mods fail in three main ways:

| Failure | Symptom | Example |
|---|---|---|
| False hold | normal typing triggers a modifier | typing `fd` becomes `Ctrl+D` |
| False tap | intended shortcut emits letters | intended `Ctrl+C` becomes `fc` |
| Perceived latency | key output feels slow or hesitant | tap-hold waits too long before deciding |

Kanata already has two major HRM improvements that eliminate many false holds:

- `tap-hold-opposite-hand` with `defhands`
- `require-prior-idle` in `defcfg`

Those are a strong baseline, but they do not fully match the "timeless HRM"
behavior people get from the best ZMK/QMK setups. The remaining gap is mostly
about **release-time positional disambiguation**, richer positional rules, and
more context-aware policy for specific modifiers like Shift.

## Current Baseline

These items are already implemented in the vendored kanata fork:

- `tap-hold-opposite-hand` + `defhands`
  - local commit: `d047516`
- `require-prior-idle`
  - local commit: `4c569f1`

Key implication:

- Do not spend time re-proposing or redesigning those features as new work.
- Treat them as the baseline behavior that all new work must build on.

## Success Criteria

We should consider this work successful if we can do most of the following:

- reduce remaining false holds during same-side rolls and normal prose typing
- preserve intentional shortcut use, including difficult edge cases
- reduce perceived latency without introducing brittle heuristics
- make behavior explainable and testable
- keep the implementation upstream-friendly where possible
- avoid turning kanata into a generic policy engine or analytics platform

## Constraints

### Host-Side, Not Firmware

Kanata is host-side software, not keyboard firmware.

That means the following are achievable:

- event-history-based hold/tap decisions
- timing heuristics
- hand/position-aware decisions
- release-time disambiguation
- decision tracing and debug instrumentation

But these limits remain:

- no access to keyboard matrix scan timing
- subject to OS scheduler jitter and system load
- cannot fully match firmware-level determinism under adverse conditions

This is a constraint on worst-case timing consistency, not on correctness of
the logic. The remaining roadmap items are still worth doing.

### Upstream Acceptance Constraints

The kanata maintainer appears to prefer:

- named, purpose-built features
- minimal conceptual surface area
- practical solutions to concrete remapping problems

The maintainer is less likely to want:

- generic predicate DSLs
- abstraction-heavy frameworks
- analytics-style telemetry
- speculative complexity without clear examples and test coverage

## What We Should Build First

### Immediate Recommendation

Build a **minimal HRM decision-tracing primitive first**, then implement the
highest-value behavior change.

Reason:

- decision tracing lowers the risk of the next engine changes
- it provides evidence for what still fails after `opposite-hand` and
  `require-prior-idle`
- it improves the chance of getting future behavior changes accepted upstream
- it gives KeyPath a clean foundation for validation and tuning tools

Important:

- keep tracing debug-oriented and opt-in
- do not start with full analytics, dashboards, or aggregate statistics
- the trace should explain decisions, not profile users

## Recommended Work Order

### Step 1: Minimal HRM Decision Tracing

Add a small, opt-in tracing mechanism that records why a tap-hold decision
resolved a certain way.

Examples of reason codes:

- `tap:prior_idle`
- `tap:same_hand_roll`
- `tap:release_before_trigger`
- `hold:opposite_hand`
- `hold:timeout`
- `hold:release_time_positional`

The purpose is not end-user analytics. The purpose is:

- engine debugging
- regression detection
- KeyPath-side validation
- evidence for future upstream proposals

### Step 2: Release-Time Positional Hold-Tap

This is the most important behavior change.

Goal:

- same-side rolls should keep resolving as taps
- deliberate same-hand shortcuts should still be possible when the home-row mod
  is truly held

This is the clearest remaining gap between current kanata behavior and the
best "timeless HRM" setups.

### Step 3: Generalized Positional Hold Rules

Once release-time logic exists, extend positional triggering in a targeted way.

Examples:

- opposite-hand versus same-hand
- configurable trigger positions
- left/right or per-key hand overrides for unusual layouts

Keep this constrained. Do not build a generic DSL.

### Step 4: Per-Modifier Policy and Shift Exemptions

Shift is different from Ctrl, Alt, and Cmd during normal typing.

Useful goals:

- exempt Shift from some anti-misfire rules
- allow different positional/timing policy by hold action
- keep text entry natural while staying conservative for more disruptive mods

### Step 5: Adaptive Timeout

Only after the work above.

Adaptive timing is attractive, but it should come after the simpler,
higher-confidence heuristics. It is easier to justify after tracing exists and
after positional behavior is stronger.

## Short-Term Milestones

These are the milestones another agent should treat as the current near-term
execution plan.

### Milestone 1: Trace the Current HRM Decision Path

Deliverables:

- identify where current hold-tap decisions are finalized in kanata
- add an opt-in trace mechanism for tap-hold decisions
- define a small, stable set of reason codes
- verify low overhead when disabled
- document how to enable and inspect traces

Success condition:

- we can explain why a specific HRM key resolved as tap or hold in real cases

### Milestone 2: Gather Example Failures Against the Current Baseline

Deliverables:

- create a small reproducible set of HRM edge cases
- capture trace output for those cases
- identify which failures remain after `opposite-hand` and `require-prior-idle`

Success condition:

- we have concrete examples that justify the next behavior change

### Milestone 3: Implement Release-Time Positional Hold-Tap

Deliverables:

- design a narrow feature shape
- implement the runtime behavior in the correct processing layer
- add tests for same-hand rolls, same-hand shortcuts, cross-hand shortcuts,
  and release-order edge cases
- add trace reasons for the new resolution path

Success condition:

- at least one important class of current false-hold or false-tap behavior is
  improved without obvious regressions

### Milestone 4: Validate Acceptance Strategy

Deliverables:

- decide whether the tracing primitive is upstreamable as-is
- decide whether release-time positional hold should be proposed upstream as a
  named feature or kept in the KeyPath fork first
- document the framing for jtroo

Success condition:

- we know which pieces are intended for upstream and which are fork-only

## Longer-Term Milestones

### Milestone 5: Targeted Positional Generalization

Deliverables:

- extend positional logic beyond strict opposite-hand behavior
- support unusual geometries or per-key overrides where necessary
- keep the public configuration surface small and explicit

### Milestone 6: Per-Modifier HRM Policy

Deliverables:

- implement Shift exemptions or other per-hold-action policy
- add tests showing why Shift needs different handling
- document the rule plainly

### Milestone 7: Adaptive Timeout

Deliverables:

- prototype adaptive timing based on recent typing cadence
- validate with trace data
- ensure it actually improves behavior instead of just adding tuning complexity

### Milestone 8: Optional Advanced Interaction Rules

Deliverables:

- evaluate bilateral combinations or multi-HRM interaction rules only if the
  simpler positional work still leaves important gaps

This is lower priority and should not block earlier work.

## Top 3 Engine Priorities

These are the top 3 **engine** items, not KeyPath UI items:

| Rank | Item | Reward | Effort | Risk | Likely upstream acceptance |
|---|---|---|---|---|---|
| 1 | Release-time positional hold-tap | High | Medium-High | Medium | Medium |
| 2 | Generalized positional hold rules | High | Medium | Medium | Medium-Low |
| 3 | Per-modifier policy / Shift exemptions | High | Medium | Medium | Medium-Low |

Important note:

- all three are fundamentally kanata work
- KeyPath can expose them later, but it cannot implement them cleanly outside
  the engine

## Telemetry Guidance

For this project, "telemetry" should mean **decision tracing**, not analytics.

Preferred shape:

- opt-in
- debug-only if possible
- low overhead
- minimal reason codes
- usable from logs or a small event surface

Avoid:

- user behavior analytics
- aggregate statistics in kanata itself
- product-specific instrumentation
- anything that creates ongoing protocol burden without clear engine value

If there are two layers, prefer this split:

1. a minimal upstreamable tracing primitive in kanata
2. any richer aggregation or visualization in KeyPath or the KeyPath fork

## Architectural Guidance

Kanata has two relevant places where hold-tap behavior can be implemented:

1. keyberon-level queued-event logic
2. kanata processing-layer logic with access to broader event history

Use the kanata processing layer for any behavior that depends on:

- pre-press history
- timing relative to prior key presses
- per-modifier policy
- multi-key context beyond the current queue
- release-time disambiguation that is awkward in the generic keyberon model

## Non-Goals

Do not pursue these unless requirements change:

- machine-learning-based hold/tap prediction
- a generic predicate DSL for tap-hold policy
- rich analytics inside kanata
- solving every rare multi-HRM interaction before the top 3 priorities

## Source Documents

Read these first:

- [hrm-roadmap.md](./hrm-roadmap.md)
- [tcp-overlay-events.md](./tcp-overlay-events.md)
- [tcp-tap-activated-requirement.md](./tcp-tap-activated-requirement.md)

If the agent needs broader product context, also inspect how KeyPath currently
uses HRM features in the main repository, but this brief is intended to be
enough to start the kanata-side work.
