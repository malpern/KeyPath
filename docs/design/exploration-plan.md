# Mappings & Gallery — Design Exploration Plan

**Status:** Sprint 1 closed (Direction C locked) · Sprint 2 drafted · awaiting exec decision on precedence model
**Owner:** UX lead
**Exec sponsor:** (pulled in at touchpoints below)
**Ends in:** Exec review → new consolidated spec (v2) → engineering handoff
**Current state:** [`sprint-1/`](sprint-1/) · [`sprint-2/`](sprint-2/)

---

## Direction from exec review

> *"Don't worry about generating visibility for the gallery with a 'Today' module or anything like that. Focus on the core interaction model, getting a clear and simple system in place that is well explored and well designed and contributes to a holistic experience for KeyPath."*

Everything in this plan flows from that. We are not building growth or engagement surfaces. We are building the simplest, most coherent interaction model possible and making sure the whole experience feels like one product.

The previous Draft 1 spec has been archived (`docs/design/archive/`). We're not iterating on it — we're starting the design work it skipped.

---

## Why two sprints (not more, not fewer)

Draft 1 was strong on architecture and weak on experience design. The two places where that mattered most were:

1. **Where the user decides to adopt a pack** — Pack Detail and the Gallery.
2. **Where the model's edges meet reality** — layers, overrides, and pack coherence.

One sprint isn't enough to cover both honestly. Three or more starts to overbuild before we learn anything. Two sprints is the right shape.

---

## Sprint 1 — The acquisition experience

**Goal:** Design the surfaces where a user discovers, evaluates, and installs a pack. End of sprint: visual direction locked, interaction flow confirmed, ready for Sprint 2 to build on.

### What we're designing

- **Pack Detail page.** The canonical surface. Three visual directions explored; one selected. Real visual comps (not wireframes): typography, spacing, imagery style for keyboard diagrams, binding-list density, inline quick-settings layout, primary action treatment. Covers pre-install, installed/unmodified, installed/modified, and update-available states.
- **Gallery — browse and evaluate.** Information architecture for Discover, Categories, My Packs. Visual language for pack cards: the size, the diagram, the typography, the rest state vs hover vs press. Search input and results treatment.
- **Editorial voice.** Pack naming conventions, description tone, category labels. Produces a style guide fragment for pack authoring.
- **Starter Kit scope.** Which 8–12 packs ship bundled with the app so the Gallery is never empty. Not designing the packs themselves — listing them, writing their marketing copy, and confirming they cover the "most common needs" bases.

### What we're NOT designing in Sprint 1

- Growth surfaces of any kind ("Today", suggestions, notifications, ambient prompts).
- Community contribution UI.
- Ratings/reviews.
- Pack update distribution mechanism (engineering concern, not UX).

### Team composition for Sprint 1

- **UX lead** (myself) — overall direction, IA, critique.
- **Visual designer** — Pack Detail comps, Gallery card grammar, typography, color exploration.
- **Motion designer** — install animation refinement, sheet transitions, pack-member highlight behavior.
- **Product/marketing** — editorial voice, category naming, Starter Kit curation.

### Deliverables at end of Sprint 1

1. Pack Detail — locked visual direction with all states designed.
2. Gallery — Discover, Categories, My Packs designed to the same fidelity.
3. Pack card component — spec'd and visually resolved.
4. Starter Kit pack list — 8–12 packs named, described, categorized.
5. Editorial voice one-pager for pack copy.
6. Motion spec updates for install / transitions.

### Exec touchpoint during Sprint 1

**Mid-sprint check-in:** Review three Pack Detail visual directions; pick one. This decision sets the visual voice for the rest of the product. ~30 minutes. Expected around day 5 of the sprint.

---

## Sprint 2 — The edges of the model

**Goal:** Design the parts of the experience where the unified "everything is a binding" model meets reality. These are the cases that Draft 1 hand-waved and they will determine whether the product feels solid or flimsy.

### What we're designing

- **Layers × packs.** The inspector view for a key that belongs to a user-defined or pack-introduced layer. How layers appear in the layer selector after a pack installs one. What uninstalling a layer-introducing pack does to the user's layer list. How the keyboard canvas communicates "you're looking at a non-base layer."
- **Override precedence model.** A complete state diagram: direct binding vs pack binding vs multiple packs vs layers. "Who wins" on every combination. What happens on uninstall/reinstall when there's a direct override in the middle. Where the precedence is visible to the user (or intentionally hidden).
- **Pack coherence.** How a pack self-reports its health when partially overridden. Where that shows up in the UI (inspector? Pack Detail? My Packs list?). The specific language. What's visible to users who never interact with the overridden key vs. who do.
- **First-run experience.** The sixty-second story for a brand-new user: what do they see, what do they do, what do they feel, what do they learn. Concrete, not infrastructural. Designed as a moment, not a checklist.
- **Inspector — all edge states.** Multi-pack keys (a key touched by two packs). Keys with only a hold behavior. Keys that are chord members. Keys that are both a pack member and a layer trigger. Device-scoped bindings. We enumerate the full matrix and design the inspector for each.

### What we're NOT designing in Sprint 2

- Per-pack Customize UIs (still owned by pack authors — but we will specify the shell/chrome of the Customize sheet more rigorously).
- Sharing, export, import.
- Settings/preferences redesign.

### Team composition for Sprint 2

Same team. Product/marketing is lighter-weight this sprint — mostly involved in first-run copy.

### Deliverables at end of Sprint 2

1. Inspector — every state designed, including the six edge cases.
2. Override precedence model — state diagram + UI surfaces that expose it.
3. Pack coherence surface — designs for inspector, Pack Detail, and My Packs.
4. Layers × packs — inspector, layer selector, and canvas treatments.
5. First-run — sixty-second flow designed as a moment, with copy.
6. Customize sheet chrome — consistent frame that every per-pack Customize UI must sit inside.

### Exec touchpoint during Sprint 2

**Mid-sprint decision:** Override precedence model review. This is a semantic decision with data-layer implications — engineering needs it locked before they can scope Phase 1. ~45 minutes. Expected around day 4 of the sprint.

---

## After both sprints: consolidated spec (v2) and exec review

Once both sprints conclude, the team produces **one consolidated UX spec** — replacing the archived Draft 1. It will include:

- Everything Draft 1 had that survived review (IA, vocabulary, data model proposal, accessibility, out-of-scope list).
- The Sprint 1 outputs fully integrated — Pack Detail, Gallery, card grammar, Starter Kit list, editorial voice.
- The Sprint 2 outputs fully integrated — inspector edge states, override precedence, pack coherence, layers, first-run.
- Visual comps (not just wireframes) for all primary surfaces.
- A revised implementation sequencing plan for engineering.

Then: **exec review.** One session, full team present. Walkthrough of the new spec against the original ask. If approved, engineering handoff begins.

Target duration end-to-end: six weeks from start of Sprint 1 to exec review.

---

## How the exec gets pulled in

The exec directive was: *"Pull me in when I can be helpful in setting direction and providing feedback."* Here's where that happens, in order:

1. **Kickoff (optional, 15 min)** — confirm the plan, anything to add or cut before the team starts.
2. **Sprint 1 mid-sprint (~30 min)** — pick the Pack Detail visual direction from three options.
3. **Sprint 1 end (~45 min, optional)** — review consolidated Sprint 1 outputs before Sprint 2 kicks off. Skippable if confidence is high.
4. **Sprint 2 mid-sprint (~45 min)** — lock the override precedence model. This is the session with the highest leverage; please prioritize.
5. **Sprint 2 end / consolidated-spec review (~90 min)** — exec review. Full team. Walkthrough. Decision to proceed to engineering or iterate once more.

Four required sessions from exec, total. Plus whatever async feedback on written artifacts is useful.

---

## Working norms for this exploration

- **All artifacts land in `docs/design/` as they're produced.** Sprint notes, explorations, dead-end explorations, comp PDFs. Nothing is hidden in a private tool.
- **Dead ends are documented.** If we try a direction and abandon it, a one-paragraph "we tried X, we didn't pick it because Y" note gets committed. Future-us will thank us.
- **No pre-emptive engineering.** Engineering stays on other work during these two sprints. Handoff happens only after the consolidated spec.
- **The Draft 1 spec stays archived and is not used as a reference.** Starting from scratch conceptually, not incrementally editing.
- **This plan itself is a living doc.** If the team discovers something during exploration that changes the sprint structure, edit this plan and note why.

---

## Open decisions (before kickoff)

None. The direction is clear enough to start. Mid-sprint touchpoints will surface real decisions at the right moments.

If there's anything you'd like me to add or cut from this plan before we begin, say so. Otherwise I'll kick off Sprint 1 and surface the first touchpoint on day 5.

---

**Archived Draft 1:** [`docs/design/archive/mappings-and-gallery-ux-spec-2026-04-22-draft1.md`](archive/mappings-and-gallery-ux-spec-2026-04-22-draft1.md)
