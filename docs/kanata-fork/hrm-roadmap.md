# Kanata HRM Improvement Roadmap

Analysis of upstream improvements to Home Row Mod (HRM) behavior in kanata,
prioritized by impact, feasibility, and likelihood of maintainer acceptance.

## Status

- **PR #1955** (`defhands` + `tap-hold-opposite-hand`): Merged / under review.
  Adds hand-awareness to tap-hold resolution — opposite-hand key press triggers
  hold, same-hand triggers tap. This is the foundation for further HRM work.

## The Three HRM Failure Modes

Every HRM improvement targets one or more of these:

| Failure | Symptom | Example |
|---------|---------|---------|
| **False hold** | Typing "fd" produces Ctrl+D | Fast same-hand roll activates hold |
| **False tap** | Intended Ctrl+C produces "fc" | Hold key released too quickly |
| **Perceived latency** | Key output feels delayed | Tap-hold waits for timeout before emitting |

`tap-hold-opposite-hand` (PR #1955) primarily eliminates **false holds** from
same-hand rolls.

## Proposed Phases

### Phase 1: Typing Streak Detection (`require-prior-idle`)

**Impact: High | Effort: Medium | Acceptance: High**

If any key was pressed within N ms before a tap-hold key, resolve immediately
as tap. Rationale: during fast typing, the user is never trying to hold a
modifier — they're mid-word.

This is proven in ZMK (`require-prior-idle-ms`) and frequently requested by
the kanata community. It would be the single highest-impact addition after
opposite-hand detection.

**Implementation approach**: Kanata-layer short-circuit in the processing loop,
not a keyberon `Custom` closure change. The kanata layer already tracks
timestamps for each key event and can check
`now - last_press_timestamp < idle_threshold` before entering the tap-hold
waiting state at all. This avoids any latency from the Custom closure queue
and keeps keyberon generic.

**Configuration sketch**:
```lisp
(defalias
  a (tap-hold-opposite-hand 180 a lmet
      (require-prior-idle 150)))
```

Or as a global/per-key option in `defcfg`:
```lisp
(defcfg
  tap-hold-prior-idle 150)
```

**Why kanata-layer, not keyberon**: The `Custom` closure only sees the queued
events *after* the tap-hold key. It cannot see whether a key was pressed
*before* the tap-hold key was pressed. The kanata processing layer has access
to the full event history.

### Phase 2: Adaptive Timeout

**Impact: Medium | Effort: Medium | Acceptance: Medium**

Adjust the tap-hold timeout dynamically based on recent typing speed. Fast
typists get shorter timeouts (less latency), slow/deliberate typing gets
longer timeouts (fewer false taps).

This is more complex than Phase 1 and harder to tune. Phase 1 covers the
most common case (typing streaks) with a simpler mechanism. Phase 2 becomes
valuable for the remaining edge cases where the user pauses mid-word.

### Phase 3: Global `defhands` + Per-Key Overrides

**Impact: Low-Medium | Effort: Low | Acceptance: High**

Allow `defhands` to be referenced by multiple tap-hold variants, not just
`tap-hold-opposite-hand`. This lets other custom tap-hold functions also
benefit from hand-awareness without duplicating hand assignments.

Also add per-key hand overrides for split keyboards where the physical
split position varies.

### Phase 4: Bilateral Combinations (Stenography-Inspired)

**Impact: Niche | Effort: High | Acceptance: Medium**

Only activate modifiers when keys from *both* hands are held simultaneously.
Inspired by stenography and used in some QMK/ZMK setups. Niche but powerful
for users who want aggressive misfire prevention.

This is architecturally complex because it requires tracking multiple
simultaneous tap-hold keys and their interactions.

### Phase 5: Telemetry / Statistics (Optional)

**Impact: Low | Effort: Medium | Acceptance: Low**

Expose misfire statistics (false hold rate, false tap rate, average hold
duration) via TCP or log output. Useful for tuning but unlikely to be
accepted upstream — jtroo prefers kanata to stay focused on key remapping,
not analytics. Better suited for KeyPath's fork or a separate tool.

## What NOT to Propose

### ML-Based Prediction

Using machine learning to predict tap vs. hold based on typing patterns.
This would be rejected by the kanata community for several reasons:

- Adds heavy dependencies (model runtime) to a lean system tool
- Non-deterministic behavior violates user expectations
- Training data requirements create privacy concerns
- The simpler heuristics (opposite-hand + prior-idle) cover 95%+ of cases

### Full Predicate API

A generic DSL for combining arbitrary conditions (hand, timing, key identity,
sequence position) into tap-hold predicates. While architecturally elegant,
this is over-designed for the kanata maintainer's taste. jtroo prefers
purpose-built features with clear names over generic frameworks. Each
predicate should be its own named option.

## Existing Issues & Discussions

| Reference | Topic | Status |
|-----------|-------|--------|
| [#1602](https://github.com/jtroo/kanata/issues/1602) | Opposite-hand HRM | Closed by PR #1955 |
| [#128](https://github.com/jtroo/kanata/issues/128) | Custom tap-hold expansion | Open |
| [Discussion #1086](https://github.com/jtroo/kanata/discussions/1086) | HRM general discussion | Active |
| [Discussion #1024](https://github.com/jtroo/kanata/discussions/1024) | Bilateral combinations | Active |

## Key Architectural Insight

Kanata has two layers where tap-hold logic can live:

1. **keyberon layer** (`HoldTapConfig::Custom` closure): Sees only the
   queued events *after* the tap-hold key was pressed. Generic, reusable,
   but limited to what's in the queue.

2. **kanata processing layer**: Has access to full event history, timestamps,
   global state (current layer, active modifiers, recent key timings). Can
   short-circuit *before* entering the tap-hold waiting state.

Phase 1 (prior-idle) and Phase 2 (adaptive timeout) **must** use the kanata
layer because they need pre-press timing data. Phase 3 and Phase 4 can use
either layer depending on the specific logic needed.
