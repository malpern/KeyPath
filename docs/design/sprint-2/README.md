# Sprint 2 — The Edges of the Model

**Sprint:** 2 of 2 — **in progress**
**Status:** All six Sprint 2 design docs drafted. High-leverage exec touchpoint requested for override precedence.
**Plan:** [`../exploration-plan.md`](../exploration-plan.md)
**Sprint 1 (closed):** [`../sprint-1/README.md`](../sprint-1/README.md) — Direction C (In-Place Modification) locked
**Craft refinement:** deferred to SwiftUI implementation phase per exec direction

---

## What Sprint 2 is for

Sprint 1 designed the acquisition experience — where the user meets a pack. Sprint 2 designs what happens *after* — where the unified "everything is a binding" model meets reality.

These are the surfaces Draft 1 hand-waved: layers, overrides, coherence, multi-pack keys, first-run, and the inspector's full edge-state matrix. They're also the surfaces that determine whether the product *feels solid* in use, not just *inviting* on first encounter.

---

## What's in this folder

| File | What it is | Depends on |
|---|---|---|
| [`override-precedence.md`](override-precedence.md) | **Foundational.** State diagram + behavior model for what happens when multiple sources want to set the same key. **Needs exec decision.** | — |
| [`pack-coherence.md`](pack-coherence.md) | How packs self-report their health when partially overridden or shadowed | Override precedence |
| [`layers-and-packs.md`](layers-and-packs.md) | How layers interact with pack lifecycle; pack-defined layers; uninstall preservation | Override precedence + pack coherence |
| [`inspector-edge-states.md`](inspector-edge-states.md) | Full inspector matrix — 12 canonical states, composable building blocks | All three above |
| [`first-run.md`](first-run.md) | The sixty-second story for a new user — designed as a moment, not a checklist | Sprint 1 Pack Detail (Direction C) |
| [`customize-sheet-chrome.md`](customize-sheet-chrome.md) | Consistent frame every pack's detailed Customize UI must sit inside | — |

---

## Sprint 2 in one paragraph

We specified the override precedence model as a formal state machine (direct > most-recent-pack > older-packs > hardware default, with shadowing preserved not deleted). Pack coherence was defined as five states (healthy / modified / shadowed / outdated / broken) with per-pack coherence policies that determine when "modified" is a pattern-warning versus a neutral state. Layer × pack interaction defines pack-defined layers as pack-owned (removed on uninstall, with user-binding preservation prompts) and user-defined layers as user-owned. The inspector's twelve canonical edge states were enumerated and composed from shared building blocks, so engineering can build one reusable inspector that handles every case. First-run was designed as a sixty-second moment where a new user installs their first pack and experiences the real effect, with no tour, no modal, no instruction — just the product's own surfaces carrying the weight. The Customize sheet chrome was specified as a fixed frame (header + body + footer) that every pack's bespoke content sits inside, with automatic coherence banners rendered by the chrome so consistency is enforced, not optional.

---

## What the exec needs to do

### 1. Lock the override precedence model (required, ~45 min)

Read [`override-precedence.md`](override-precedence.md) and confirm or modify the four foundational claims at the bottom:

1. **Precedence order:** Direct > most-recent-pack > older-packs > hardware default.
2. **Shadowing is preserved, not deleted.** Uninstall reveals shadowed bindings.
3. **Install order is the pack precedence mechanism.** No user-defined pack priority in v1.
4. **Direct bindings persist through pack lifecycle.** Uninstalling a pack does not remove user overrides on its keys.

This is the high-leverage Sprint 2 touchpoint. Changes to this model after lock-in get expensive fast because pack-coherence, layer × pack interaction, and inspector states all build on it.

### 2. Lock layer ownership claims (required, ~10 min, probably at same session)

Read [`layers-and-packs.md`](layers-and-packs.md) and confirm the two claims at the bottom:

1. Pack-defined layers are owned by the pack; user-defined layers are owned by the user.
2. Layer identity is a manifest-declared ID, with user-facing display name separately tracked.

### 3. Review first-run (nice to have, ~15 min)

Read [`first-run.md`](first-run.md). Is the sixty-second story right? Too much? Too little? Is the "try Caps Lock → Escape" nudge too prescriptive? This is the moment that shapes every new user's mental model of the product — worth a real read.

### 4. Skim pack coherence, inspector, customize (optional)

[`pack-coherence.md`](pack-coherence.md), [`inspector-edge-states.md`](inspector-edge-states.md), [`customize-sheet-chrome.md`](customize-sheet-chrome.md) are all derivative of the precedence + layer decisions. If those two are locked, the rest are internally consistent. Skim for red flags if you want.

Total review time: 60–90 minutes depending on how deep you want to go on first-run. The override-precedence + layers decisions are the only blocking items.

---

## What was intentionally scoped down

Per the exec direction to not generate visibility and to focus on the core interaction model:

- **First-run has no tour, no modal, no "welcome tour" overlay.** Just a welcome inspector state with two paths, both of which lead to the sixty-second moment through the product's own surfaces.
- **No achievements, progress meters, or gamification** in first-run.
- **No user-defined pack priority** in the precedence model. Install order is the mechanism.
- **No pack dependencies** in v1. Packs don't declare they require other packs.
- **No community features** (ratings, reviews, sharing) in any of these docs.

Per the exec direction to defer craft to SwiftUI:

- **No visual comps.** Everything is ASCII wireframes at the same fidelity as Sprint 1.
- **Motion specs are sketches**, not frame-level timing. Motion designer will refine in implementation.

---

## Dead ends (documented for posterity)

### Dead end: "most recent wins" without shadowing

Early draft of override precedence had installed bindings *mutating* each other — install Pack B → Pack A's bindings are deleted (not shadowed). Rejected because (a) it breaks the uninstall-reveals-previous mental model, (b) it makes the data layer lossy (once you uninstall, you can't recover), (c) it makes "reinstall" unpredictable.

### Dead end: user-defined pack priority (drag to reorder)

Considered letting users explicitly set the precedence order of installed packs via drag-and-drop in My Packs. Rejected for v1 because (a) install-order handles the 95% case, (b) it adds a whole new UI surface and mental model, (c) it's the kind of feature users ask for in year 2 of product use, not year 0. Deferred.

### Dead end: inline pack editor in the inspector

Sprint 1 considered putting a pack's full configuration editor inside the inspector when a pack-contributed key is selected. Rejected because (a) rules with complex timing or multi-pane UIs (home-row mods, chord groups) can't fit in a 340 pt inspector, (b) the inspector would become two products in one, (c) the Customize sheet route (via Pack Detail) is the right place.

### Dead end: binary "healthy vs not healthy" pack state

Early pack-coherence draft had just two states. Rejected because the distinction between *"modified but still working"* and *"modified and broken"* matters a lot to users, and the five-state model (with per-pack coherence policies) is how that distinction gets expressed cleanly.

### Dead end: first-run as a skippable overlay tour

Draft 1's first-run was a tour. Rejected in favor of a moment designed into the product's own surfaces. A tour is infrastructure; a moment is a product decision.

---

## After exec review → consolidated spec v2

Once the precedence and layer decisions are locked, Sprint 2's output is complete. The team will then produce a **consolidated UX spec (v2)** that replaces the archived Draft 1:

- Everything Sprint 1 produced (IA, Pack Detail direction, Gallery, cards, Starter Kit, editorial voice, motion).
- Everything Sprint 2 produced (precedence model, coherence, layers, inspector, first-run, customize chrome).
- Cross-references to dead-end notes for traceability.
- An updated implementation sequencing plan for engineering.

Then: **full exec review.** Full team walkthrough against the original ask. If approved, engineering handoff begins with Phase 1 (data unification).

---

## Remaining open questions (aggregated from Sprint 2 docs)

Listed for convenience; individual docs have fuller context.

1. **Per-layer precedence visibility in the inspector.** Currently: inspector shows precedence for the current layer only. (§override-precedence)
2. **Whole-pack vs per-key restore.** Proposal: both, with different affordances. (§override-precedence, §pack-coherence)
3. **Multi-pack with same layer name.** Proposal: layer IDs are namespaced by pack; display names disambiguate. (§layers-and-packs)
4. **Scoped pack binding edge cases.** Proposal: normal precedence applies; scope is a filter, not a precedence dimension. (§override-precedence, §inspector-edge-states)
5. **"Remove" vs "Unbind" vs "Release" vocabulary.** Needs a final pass. (§inspector-edge-states)
6. **Banner text length in Customize chrome.** Proposal: wrap up to 2 lines, then link-truncate. (§customize-sheet-chrome)
7. **First-run persistence (fade vs dismiss-on-action).** Proposal: dismiss-on-action only. (§first-run)

None block the exec decision on precedence. All can be resolved during engineering.

---

## Logistics

**Next step:** Exec decision on override-precedence + layers-and-packs claims.
**Planned Sprint 2 wrap:** Immediately after the decisions are locked. Consolidated spec v2 begins the next day.
**Consolidated spec v2 target:** 3–5 working days after Sprint 2 wrap.
**Exec review target:** 1 week from consolidated spec v2 completion.

Engineering has not been engaged. Waiting for consolidated spec v2.
