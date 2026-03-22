# KeyPath HRM Integration Roadmap

This document tracks the remaining HRM work that belongs in KeyPath itself.

Kanata engine work now lives in the sibling repository:

- `../../../kanata-pr/docs/hrm-roadmap.md`
- `../../../kanata-pr/docs/hrm-phase-1-release-time-positional-spec.md`

This split is intentional:

- kanata owns tap-vs-hold semantics and new HRM primitives
- KeyPath owns observability, explanation, tuning UX, presets, and adoption

## What Is Already Shipped

KeyPath already has most of the app-side HRM observability pipeline in place:

- live tap-hold decision stream
- per-key breakdown and top-reason summaries
- recommendation preview and apply flow

That means the remaining high-value HRM work is mostly upstream kanata engine
work, not new KeyPath-only semantics.

## Remaining KeyPath Work

### 1. Overlay-native reason annotations

**Impact: Medium | Effort: Medium**

When a tap-hold key resolves, the visual keyboard overlay should briefly show
the reason directly on the affected key. This is the most obvious remaining UX
gap in the current observability surface.

### 2. Suggestion heuristic polish

**Impact: Medium-High | Effort: Medium**

Recommendation preview and apply flows exist already. The remaining work is to
make the heuristics more trustworthy, especially around:

- timeout recommendations
- `require-prior-idle` tuning
- `defhands`-related diagnostics

### 3. Curated HRM presets and migration help

**Impact: Medium | Effort: Low-Medium**

Once the next kanata HRM primitive lands, KeyPath should make it easy to adopt:

- preset suggestions
- sample config snippets
- migration notes for existing `tap-hold-opposite-hand` users

### 4. Validation against real user patterns

**Impact: Medium | Effort: Medium**

KeyPath is the best place to validate whether the kanata-side behavior changes
actually improve the real user experience:

- watch how often users hit `prior-idle`, `timeout`, and same-hand outcomes
- compare behavior before/after new primitives
- refine app suggestions based on those outcomes

## Dependencies on Kanata

The next meaningful behavior gains depend on the kanata roadmap, not more
KeyPath-only logic.

Top upstream dependencies:

1. release-time positional HRM
2. generalized positional hold predicates
3. per-modifier policy / Shift exemptions

Those are tracked in:

- `../../../kanata-pr/docs/hrm-roadmap.md`
- `../../../kanata-pr/docs/hrm-phase-1-release-time-positional-spec.md`

## Recommended Work Order

### Near term

- finish overlay-native reason annotations
- tighten tuning suggestion heuristics
- keep docs and preset guidance aligned with the kanata roadmap

### After the next kanata HRM primitive lands

- expose it through presets and migration guidance
- update telemetry explanations to include the new behavior
- validate whether it materially reduces remaining user pain

## Recommendation

Do not use this KeyPath doc as the authoritative source for engine planning.

Use:

- kanata docs for HRM primitive design and phasing
- KeyPath docs for app integration, UX, and adoption sequencing
