# Auto Shift Roadmap

## Summary

KeyPath should start with an **experimental Auto Shift collection implemented entirely in KeyPath**, not with a Kanata upstream dependency.

The first version should target **symbols/punctuation only** and reuse existing KeyPath tap-hold generation. A broader letters-based Auto Shift mode should be treated as a later phase because it is more timing-sensitive, more conflict-prone, and more likely to degrade typing feel.

Kanata syntax sugar can be pursued later if KeyPath proves a stable set of semantics and default behaviors.

---

## Problem

KeyPath already supports:

- Symbol layers
- Tap-hold behaviors
- Home row mods
- Shifted outputs for some mappings

But it does **not** currently support a simple "hold the same key a bit longer to get the shifted variant" workflow.

Examples:

- Tap `.` -> `.`
- Hold `.` -> `>`
- Tap `1` -> `1`
- Hold `1` -> `!`

This is materially different from symbol layers:

- Symbol layers are **mode/layer-based**
- Auto Shift is **per-key timing-based**

---

## Recommendation

### Product Recommendation

Build Auto Shift in **KeyPath first**.

### Scope Recommendation

Phase 1 should ship:

- `Auto Shift Symbols`
- Disabled by default
- Clearly labeled experimental
- Collection-level timeout
- Optional fast-typing protection
- Strong conflict warnings

Phase 1 should **not** ship:

- Auto Shift for all letters by default
- Auto Shift as a system default
- Broad "replace Shift" positioning

### Upstream Recommendation

Do **not** start with a Kanata PR.

Instead:

1. Ship an experimental KeyPath collection
2. Learn actual user preferences and failure modes
3. Use that evidence to decide whether a Kanata syntax-sugar PR is warranted

---

## Why Start In KeyPath

KeyPath can already generate the core mechanism using existing dual-role/tap-hold support. That means there is no immediate engine blocker.

Starting in KeyPath lets us validate:

- whether users actually want Auto Shift
- whether the useful scope is symbols only vs letters too
- which default timeout feels acceptable
- whether fast-typing protection is mandatory
- whether conflicts with home row mods make the feature too fragile

These answers materially affect what a Kanata syntax-sugar proposal should look like.

---

## Current Functional Gap

The missing pieces are mostly **UX and semantics**, not raw config generation.

### Already Available

- Per-key tap-hold behavior generation
- Collection-based mapping generation
- Existing symbol-layer/single-key/tap-hold collection patterns
- `require-prior-idle` support in KeyPath's generated Kanata config

### Still Needed

- A dedicated collection concept and UX for Auto Shift
- Scope presets (`symbols only`, later maybe `letters`, `digits`, `selected keys`)
- Timeout controls
- Optional fast-typing protection
- Conflict detection and messaging
- Clear interaction rules for real Shift and existing tap-hold rules
- Documentation that explains the tradeoffs and expectations

---

## Product Constraints

Auto Shift is more fragile than a symbol layer.

Main risks:

- false positives during normal typing
- false negatives when the hold threshold is too high
- direct overlap with home row mods and custom tap-hold rules
- punctuation behavior varying by keyboard layout
- users expecting it to feel like a native firmware feature

This makes **narrow scope and careful defaults** more important than feature breadth.

---

## Proposed UX

### Collection Name

`Auto Shift Symbols`

Possible later variants:

- `Auto Shift Letters`
- `Auto Shift Digits`
- `Auto Shift Selected Keys`

### User-Facing Description

"Tap for the normal symbol. Hold the same key slightly longer for the shifted symbol."

### Recommended Controls

- Enable/disable toggle
- Timeout slider
- `Protect fast typing` toggle
- Optional key group selector in later phases

### Recommended Defaults

- Scope: punctuation/symbols only
- Timeout: start conservative
- Fast typing protection: on by default for letter-based variants, optional for symbols

---

## Technical Shape

Use a **generated collection** approach similar to other configurable collections.

At a high level:

1. Store collection config
2. Generate `KeyMapping` entries for the selected keys
3. Emit dual-role behavior where:
   - tap = base key
   - hold = shifted form

Examples of generated semantics:

- `.` -> `tap-hold(... . S-.)`
- `,` -> `tap-hold(... , S-,)`
- `/` -> `tap-hold(... / S-/)`
- `1` -> `tap-hold(... 1 S-1)`

This is sufficient for a first version even without new Kanata syntax.

---

## Architecture Plan

### Phase 0: Product Definition

Decide and document:

- exact scope of Phase 1 key set
- timeout default and allowed range
- whether `require-prior-idle` is available in this collection
- whether real Shift simply passes through and wins
- whether non-US layout support is explicitly out of scope for v1

Deliverable:

- finalized product semantics in this document

### Phase 1: Collection Model

Add a first-class KeyPath collection/config for Auto Shift.

Expected work:

- add a new `RuleCollectionConfiguration` case or reuse an existing configurable pattern with Auto Shift-specific config
- add config codable support
- add default catalog entry in `RuleCollectionCatalog`
- add dynamic collection summary and activation hint behavior if needed

Suggested config fields:

- `scope`
- `timeoutMs`
- `protectFastTyping`
- `enabledKeys` or derived preset set

### Phase 2: Mapping Generation

Generate mappings from config.

Expected work:

- add Auto Shift mapping generation next to other configurable collection generators
- derive shifted output from selected keys
- emit dual-role behaviors using existing rendering infrastructure
- wire optional `require-prior-idle` contribution into generated config

Questions to settle:

- whether symbols and digits share one timeout
- whether all keys use basic `tap-hold` vs a different variant

### Phase 3: UI

Add collection UI in the rules summary and collection row surfaces.

Expected work:

- collection card rendering
- timeout control
- scope presentation
- experimental labeling
- help copy explaining timing tradeoffs

If this behaves like a preset collection rather than a freeform editor, the UI should stay intentionally constrained.

### Phase 4: Conflict Guardrails

Add clear warnings when Auto Shift overlaps with:

- home row mods
- tap-hold custom rules
- existing remaps on the same keys
- other generated collections that own the same inputs

Warnings should explain:

- which keys conflict
- which rule wins today
- why the interaction is risky even if technically valid

### Phase 5: Testing

Required test coverage:

- config codable round-trip
- collection migration/default behavior
- mapping generation correctness
- `require-prior-idle` emission behavior
- conflict detection behavior
- UI tests for controls and defaults

Manual verification:

- symbols only feels usable at default timeout
- real Shift still behaves predictably
- conflicts are visible and actionable
- rapid typing does not produce surprising output for the supported scope

### Phase 6: Documentation and Feedback

Add:

- user-facing feature doc
- troubleshooting guidance
- explanation of when symbol layers may still be preferable

Success criteria:

- users can understand the feature without reading raw Kanata syntax
- users understand that this is timing-based and experimental

---

## Proposed Delivery Sequence

### Milestone 1

Ship `Auto Shift Symbols` behind an experimental label.

Includes:

- generated collection
- timeout control
- conflict warnings
- documentation

Does not include:

- letters
- custom per-key editor
- Kanata upstream work

### Milestone 2

Evaluate whether letters are viable.

Only proceed if:

- symbol-only adoption is positive
- support burden is manageable
- the default timing strategy is stable

### Milestone 3

Consider a Kanata syntax-sugar PR if:

- KeyPath semantics have stabilized
- the lowered/generated config shape is repetitive enough to justify sugar
- there is a clear, minimal syntax proposal

---

## Kanata Follow-Up

If the feature succeeds in KeyPath, then propose a **small syntax-sugar** addition upstream rather than a large new runtime primitive.

Good upstream position:

- "KeyPath has validated this behavior with real users"
- "The implementation lowers to existing hold-tap semantics"
- "This is a convenience syntax, not a new subsystem"

Avoid proposing upstream:

- a broad replacement for Shift
- many policy knobs before the base behavior is proven
- a feature whose semantics are still changing

---

## Open Questions

- Should digits be included in the first scope, or punctuation only?
- Should `protect fast typing` be user-visible in v1, or just built into defaults?
- Should the first version infer shifted outputs only, or allow explicit overrides?
- Should Auto Shift collections be mutually exclusive with certain home row mod setups?
- Is there enough value beyond the existing symbol layer to justify maintenance cost?

---

## Bottom Line

The right roadmap is:

1. Start in KeyPath
2. Scope narrowly
3. Use existing tap-hold generation
4. Treat Auto Shift as experimental
5. Learn from usage
6. Only then consider Kanata syntax sugar

That path minimizes technical risk, minimizes upstream coordination risk, and gives us better product information before making a parser-level proposal.
