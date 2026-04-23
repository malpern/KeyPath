# Sprint 1 — The Acquisition Experience

**Sprint:** 1 of 2 — **CLOSED**
**Status:** ✓ Direction C (In-Place Modification) locked by exec. Moving to Sprint 2.
**Craft refinement** (full visuals, motion polish) deferred to SwiftUI implementation phase — wireframes in this folder are the committed shape.
**Plan:** [`../exploration-plan.md`](../exploration-plan.md)
**Sprint 2:** [`../sprint-2/`](../sprint-2/)
**Archived Draft 1 spec:** [`../archive/mappings-and-gallery-ux-spec-2026-04-22-draft1.md`](../archive/mappings-and-gallery-ux-spec-2026-04-22-draft1.md)

---

## What's in this folder

| File | What it is | Status |
|---|---|---|
| [`pack-detail-directions.md`](pack-detail-directions.md) | Three visual directions for the Pack Detail page, compared | **Needs exec decision** |
| [`gallery-and-cards.md`](gallery-and-cards.md) | Gallery IA, Discover/Categories/My Packs layout, pack card grammar | Draft — some decisions pend Pack Detail direction |
| [`starter-kit.md`](starter-kit.md) | List of 12 bundled packs shipping with v1 | Draft — review the list |
| [`editorial-voice.md`](editorial-voice.md) | Copy style guide for packs, Gallery, microcopy, errors | Draft |
| [`motion-notes.md`](motion-notes.md) | Motion decisions not dependent on Pack Detail direction | Partial |

---

## Sprint 1 in one paragraph

We explored the surfaces where a user discovers, evaluates, and installs a pack. Three distinct hypotheses for the Pack Detail page (the "Product Page," "Live Preview," and "In-Place Modification" directions) are ready for exec decision. Gallery IA and pack card grammar are spec'd to a level that's independent of that decision. We proposed a 12-pack Starter Kit covering the key use cases (caps lock hacks, home-row mods, writer/dev/accessibility/gaming) to ensure the Gallery is valuable on first launch and offline. An editorial voice guide anchors all copy in the product. Motion decisions that are direction-independent are written; direction-dependent motion waits.

---

## What the exec needs to do

### 1. Pack Detail direction (required, ~30 min)

Read [`pack-detail-directions.md`](pack-detail-directions.md) and pick A, B, or C. My recommendation is C with a fallback mode; A is a solid safer choice; B I'd only pick if we decide exploratory/hands-on is more important than in-place. Once picked, the direction determines Gallery card visuals, motion refinement, and Sprint 2 planning.

### 2. Starter Kit review (nice to have, ~15 min)

Read [`starter-kit.md`](starter-kit.md). Is the list right? Too many? Too few? Missing something? The list is easier to prune now than to expand after users form expectations.

### 3. Editorial voice acknowledgment (optional)

Skim [`editorial-voice.md`](editorial-voice.md). If anything in the voice feels off-brand or misaligned with how you think about KeyPath's personality, flag it. This guide will shape every piece of user-facing copy.

### 4. Gallery IA sanity check (optional)

Skim [`gallery-and-cards.md`](gallery-and-cards.md). The main thing to verify is that the three-tab structure (Discover/Categories/My Packs) and the absence of growth surfaces matches your direction.

Total review time: 30–60 minutes depending on how deep you want to go. Pack Detail direction is the only blocking decision.

---

## What's coming in Sprint 2 (preview)

Once the Pack Detail direction is locked, Sprint 2 covers:

- **Inspector edge states** — multi-pack keys, layer-scoped bindings, chord members, device-scoped bindings, keys with only hold behaviors.
- **Layers × packs** — how layers appear in the UI after a pack installs one; how the inspector handles layer-scoped bindings.
- **Override precedence model** — a complete state diagram: direct binding vs pack binding vs multiple packs vs uninstall-after-override scenarios.
- **Pack coherence** — how a pack self-reports its health when partially overridden; where that shows in the UI.
- **First-run** — the sixty-second story for a brand-new user. A moment, not a checklist.
- **Customize sheet chrome** — consistent frame that every pack's Customize UI must sit inside.

Sprint 2 has one high-leverage exec touchpoint: the override precedence model (~45 min). Please prioritize that one.

---

## What was intentionally cut or deferred

Per the exec direction *"don't worry about generating visibility for the gallery … focus on the core interaction model"*:

- No Today / Featured / Trending modules.
- No ratings, reviews, or social signals.
- No algorithmic recommendations.
- No notifications suggesting new packs.
- No velocity/popularity signals on cards.

This is deliberate. The Gallery should feel like a thoughtful shelf in a specialist bookstore, not a content recommendation feed.

Other deferrals:

- Per-pack quick-settings schemas → Sprint 2.
- Pack illustration style exploration → after Pack Detail direction is picked.
- Per-Starter-Kit-pack copy drafting → after editorial-voice review.
- Localization / RTL → post-v1.

---

## Working norms applied

- All artifacts in this folder. No private tools, no Figma-only decisions.
- Dead-end explorations documented alongside kept work. (Two dead ends so far: considered a "detail view as full-screen modal" before converging on sheet-over-keyboard; considered a dedicated "Manage Packs" tab before folding it into Gallery > My Packs.)
- Draft 1 spec is archived and not used as reference.
- Engineering is not yet engaged — Phase 1 work waits for the consolidated spec at end of Sprint 2.

---

## Dead ends (for posterity)

### Dead end: "Detail view as full-screen takeover"

Early exploration had Pack Detail opening as a full-screen modal that hid the main window entirely. We rejected this because (a) it loses context — the user was looking at their keyboard, and losing that mid-flow breaks the mental model, (b) sheet patterns are more Apple-native for this kind of detail, (c) fullscreen modals invite too much visual complexity.

### Dead end: "Manage Packs" as a fourth tab

Considered separating "browse packs" from "manage my installed packs" as distinct tabs. Rejected because My Packs naturally belongs inside the Gallery (App Store pattern — Purchased tab) and a separate tab would double the IA surface for no new capability.

### Dead end: Pack Detail's quick settings as a modal sub-sheet

Considered making quick settings open as a secondary sheet on top of Pack Detail, with a "Settings" button. Rejected because the settings are the *point* of a rich Pack Detail — hiding them one layer deeper wastes the surface. Inline is the right call.

### Dead end: Category hierarchy

Considered multi-level categories (e.g., "Home-Row Mods" → "Light / Full / Custom"). Rejected because (a) twelve packs across nine categories is plenty without nesting, (b) nesting adds navigation friction, (c) users don't want to learn a taxonomy — they want to find the thing.

---

## Logistics

**Next step:** Exec picks Pack Detail direction. Once picked, I update this folder with direction-specific comps and proceed to Sprint 2 planning.

**Planned Sprint 1 wrap:** 3 working days after the direction decision. Primary outputs: full-fidelity Pack Detail comps, full Gallery visual design, Starter Kit copy drafts, final motion spec for Sprint 1.

**After Sprint 1 wrap → Sprint 2 kickoff:** See [`../exploration-plan.md`](../exploration-plan.md) for the Sprint 2 scope.
