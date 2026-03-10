# Kanata HRM Improvement Roadmap

Analysis of upstream improvements to Home Row Mod (HRM) behavior in kanata,
updated to reflect what is already implemented and what remains to reach
"timeless HRM" parity with the strongest ZMK/QMK setups.

## Current Baseline

These primitives are already implemented in the vendored kanata fork:

- **`tap-hold-opposite-hand` + `defhands`**: merged in commit `d047516`.
  This eliminates the most common false holds from same-hand rolls by making
  cross-hand presses trigger hold and same-hand presses resolve as tap.
- **`require-prior-idle` `defcfg` option**: merged in commit `4c569f1`.
  This short-circuits tap-hold resolution to tap when the key press occurs
  during a typing streak.

This is already a strong HRM baseline. The next gains come from improving how
kanata resolves edge cases that remain after those two heuristics.

## The Three HRM Failure Modes

Every HRM improvement targets one or more of these:

| Failure | Symptom | Example |
|---------|---------|---------|
| **False hold** | Typing "fd" produces Ctrl+D | Fast same-hand roll activates hold |
| **False tap** | Intended Ctrl+C produces "fc" | Hold key released too quickly |
| **Perceived latency** | Key output feels delayed | Tap-hold waits for timeout before emitting |

`tap-hold-opposite-hand` primarily eliminates **false holds** from
same-hand rolls.

## Proposed Phases

### Phase 1: Release-Time Positional Hold-Tap

**Impact: High | Effort: Medium-High | Acceptance: Medium**

This is now the highest-value missing primitive.

The goal is to defer part of the positional decision until release time so that
same-side rolls still resolve as taps, while deliberate same-hand shortcuts can
still succeed if the home-row mod is actually held long enough.

This is the main gap between kanata's current HRM behavior and the "timeless
HRM" ZMK approach. Today, opposite-hand detection is a strong approximation,
but it is coarser than release-time positional logic.

Potential directions:

- Add a dedicated tap-hold variant with explicit release-time positional
  semantics.
- Generalize positional trigger logic so "which keys may trigger hold" and
  "when to finalize the decision" are both first-class concepts.

This belongs in kanata's event engine, not in KeyPath. It changes the tap
versus hold decision itself, not just configuration shape.

### Phase 2: Generalized Positional Hold Predicates

**Impact: High | Effort: Medium | Acceptance: Medium**

`tap-hold-opposite-hand` proves that hand-aware HRM works well. The next step
is to make positional triggering more expressive without turning the config
surface into a generic DSL.

Examples of useful targeted extensions:

- opposite-hand versus same-hand
- explicit allowed trigger positions
- left/right overrides for unusual layouts
- per-key hand overrides for splits, columns, and thumb clusters

The important constraint is to keep these as named behaviors or named options,
not a free-form predicate language.

### Phase 3: Per-Modifier Policy and Shift Exemptions

**Impact: High | Effort: Medium | Acceptance: Medium**

Not all modifiers should be suppressed equally during typing streaks.

Shift is special:

- capital letters are part of normal typing
- punctuation often depends on Shift
- users tolerate more conservatism for Ctrl / Alt / Cmd than for Shift

A clean implementation would allow per-hold-action policy such as:

- Shift exempt from certain streak suppression rules
- different positional rules by modifier class
- more forgiving timing for some actions than others

This is likely more valuable than adaptive timing because it improves real text
entry behavior directly.

### Phase 4: Telemetry / Decision Tracing

**Impact: Medium | Effort: Low-Medium | Acceptance: Low-Medium**

Expose why a tap-hold resolved the way it did:

- resolved as tap due to prior-idle
- resolved as tap due to same-hand roll
- resolved as hold due to opposite-hand trigger
- resolved as hold due to timeout

This is primarily valuable for downstream tooling such as KeyPath:

- tuning assistants
- misfire reports
- simulator validation
- regression detection during engine changes

Upstream may prefer minimal logging, but even a debug-only or TCP-only trace
mode would substantially improve confidence in future HRM work.

### Phase 5: Adaptive Timeout

**Impact: Medium | Effort: Medium | Acceptance: Medium**

Adjust the tap-hold timeout dynamically based on recent typing cadence. Fast
typists get shorter timeouts for less latency; slower or more deliberate input
gets longer timeouts for fewer false taps.

This remains attractive, but it should follow positional and policy work rather
than precede it. The simpler heuristics cover more failures with less tuning.

### Phase 6: Global `defhands` Reuse + Per-Key Overrides

**Impact: Low-Medium | Effort: Low | Acceptance: High**

Allow `defhands` to be referenced by more tap-hold variants and support
per-key hand overrides where the physical split position varies. This is useful
in advanced layouts, but it is no longer a top-priority blocker now that the
base `defhands` support already exists.

### Phase 7: Bilateral Combinations / Multi-HRM Interaction Rules

**Impact: Medium | Effort: High | Acceptance: Medium**

Only activate modifiers when keys from both hands are meaningfully involved, or
add explicit rules for interactions between multiple simultaneous home-row mods.

This is powerful for advanced users but architecturally complex. It should come
after the simpler release-time and positional improvements.

## Ranking Summary

| Rank | Improvement | Value | Effort | Risk |
|------|-------------|-------|--------|------|
| 1 | Release-time positional hold-tap | High | Medium-High | Medium |
| 2 | Generalized positional hold predicates | High | Medium | Medium |
| 3 | Per-modifier policy / Shift exemption | High | Medium | Medium |
| 4 | Telemetry / decision tracing | Medium | Low-Medium | Low |
| 5 | Adaptive timeout | Medium | Medium | Medium |
| 6 | `defhands` reuse + per-key overrides | Low-Medium | Low | Low |
| 7 | Bilateral combinations / multi-HRM interaction | Medium | High | High |

## What NOT to Propose

### ML-Based Prediction

Using machine learning to predict tap vs. hold based on typing patterns.
This would be rejected by the kanata community for several reasons:

- Adds heavy dependencies (model runtime) to a lean system tool
- Non-deterministic behavior violates user expectations
- Training data requirements create privacy concerns
- The simpler heuristics (opposite-hand + prior-idle + positional rules) cover
  the vast majority of cases

### Full Predicate API

A generic DSL for combining arbitrary conditions (hand, timing, key identity,
sequence position) into tap-hold predicates. While architecturally elegant,
this is over-designed for the kanata maintainer's taste. jtroo prefers
purpose-built features with clear names over generic frameworks. Each
predicate should be its own named option.

## Existing Issues & Discussions

| Reference | Topic | Status |
|-----------|-------|--------|
| [#1602](https://github.com/jtroo/kanata/issues/1602) | Opposite-hand HRM | Implemented via `d047516` |
| [#128](https://github.com/jtroo/kanata/issues/128) | Custom tap-hold expansion | Open |
| [Discussion #1086](https://github.com/jtroo/kanata/discussions/1086) | HRM general discussion | Active |
| [Discussion #1024](https://github.com/jtroo/kanata/discussions/1024) | Bilateral combinations | Active |

## Key Architectural Insight

Kanata has two layers where tap-hold logic can live:

1. **keyberon layer** (`HoldTapConfig::Custom` closure): Sees only the queued
   events after the tap-hold key was pressed. Generic and reusable, but
   limited to what is visible in that queue.

2. **kanata processing layer**: Has access to full event history, timestamps,
   global state (current layer, active modifiers, recent key timings). Can
   short-circuit *before* entering the tap-hold waiting state.

Rules that depend on pre-press history or richer global state must live in the
kanata processing layer. That includes:

- prior-idle typing streak detection
- adaptive timeout
- per-modifier policy based on recent context

Rules that depend on queued post-press events may fit in keyberon, but once the
behavior needs release-time disambiguation or multi-key interaction awareness,
it likely belongs in the kanata layer for clarity.

## Practical Constraint: Host-Side, Not Firmware

These improvements are all achievable in host-side software. Kanata can inspect
event order, timing, active modifiers, and recent history well enough to get
very close to firmware-quality HRM behavior for real users.

What it cannot fully match is firmware-level determinism:

- no access to keyboard matrix scan timing
- subject to OS scheduler jitter and system load
- less precise under adverse conditions than QMK/ZMK running on-device

That is a limit on worst-case timing consistency, not on correctness of the
decision logic. The remaining roadmap items are still worth doing in kanata.
