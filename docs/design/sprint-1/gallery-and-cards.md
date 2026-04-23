# Gallery — IA, Browse Experience, and Pack Card Grammar

**Sprint:** 1 · Day 6
**Status:** Draft for review with Pack Detail direction
**Depends on:** Pack Detail direction decision (most decisions are independent, a few are flagged)

---

## Information architecture

Three top-level tabs and a persistent search field. No more.

```
Gallery
├── Discover                  (default tab, editorial-ish without being "Today")
├── Categories                (structured browsing)
└── My Packs                  (installed inventory + pack-level ops)

Search (always visible at top, not a tab)
```

**What's intentionally missing:**

- No "Today" / "Featured this week" carousel.
- No "Trending" / "Popular this week".
- No rankings, no leaderboards.
- No ratings/reviews in v1.
- No social signals of any kind.

Per exec direction, the Gallery does not try to generate its own visibility. It's a well-organized shelf the user walks up to when they want something. The shelf is curated, not auto-ranked.

---

## Discover tab

Two sections, stacked vertically. Scrollable.

### Section 1: Starter Kit (only visible if the user has fewer than ~3 packs installed)

For new users. Three-card row, horizontal scroll if needed. Each card is a curated "get started" pack with a one-sentence pitch.

Labeled simply: **"Start here"** (not "Recommended for you" — nothing personalized, no engagement metrics).

Disappears from the Discover tab once the user has installed enough packs to indicate they're oriented. Still reachable through Categories → Starter Kit.

### Section 2: Curated collections

Six to ten hand-curated collections, each represented as a larger card. Each collection opens into a page of 3–12 packs.

Example collections:
- **"Make Caps Lock Useful"** — the classic: escape, hyper, layer trigger, etc.
- **"Modifier overhaul"** — home-row mods, meh/hyper, modifier swaps.
- **"Writers' toolkit"** — smart caps, symbol layer, cursor helpers.
- **"Vim without Vim"** — nav layer, esc remap, cursor-on-home-row.
- **"One-hand typing"** — mirrored layouts for injury/accessibility.
- **"Dev essentials"** — tmux-style bindings, symbol layer, multi-cursor helpers.

Collections are **editorial**, not algorithmic. They reflect "here's what people do with KeyPath," curated by the product team. They update on a cadence that's decoupled from user behavior — monthly is fine, quarterly is fine, "when we have something good to say" is fine.

No section titled "New this week" or "Updated recently." No velocity signals.

### Visual feel

The Discover tab should feel like a thoughtful shelf in a specialist bookstore. Not loud, not gamified, not trying to grab attention. Generous whitespace. Three-unit grid at most — we don't use density to imply there's "a lot to explore."

---

## Categories tab

A flat grid of category tiles. One-level navigation — no nested categories.

Categories (v1 list, can evolve):

```
Make Caps Lock Useful
Home-Row Mods
Layer-Based Workflows
Vim-Style Navigation
Writer's Toolkit
One-Handed Typing
Developer Essentials
Accessibility Aids
Gaming
```

Each tile: pack count in small type, short description one-liner, representative icon.

Tapping a tile opens a **category page**: a flat list of packs in that category, sorted alphabetically by default with a sort toggle (Name / Date added to Gallery / Install count — the last one is the only metric we use, and it's secondary).

No "Featured in this category." No subcategories. No sub-filters.

---

## My Packs tab

Flat list. Each row is an installed pack.

```
┌─────────────────────────────────────────────────────────┐
│ [icon] Home-Row Mods                      v2.1.0       │
│        By KeyPath Team                                  │
│        8 bindings · 1 modified by you      [Open →]     │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ [icon] Caps Lock as Hyper                 v1.0.2       │
│        By KeyPath Team                    [Update]     │
│        1 binding                            [Open →]    │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ [icon] Vim Navigation Layer               v3.0.0       │
│        By KeyPath Team                                  │
│        22 bindings · 3 modified by you     [Open →]     │
└─────────────────────────────────────────────────────────┘
```

**Sort** (default: most recently installed). User can change to: Name, Modification status.

**No grouping by category** — users installed these, they know them, categorization is for Discovery, not for the things you already own.

**Row actions:**
- `Open →` opens Pack Detail for that pack.
- `[Update]` if one is available — inline button. Clicking opens the update flow.
- Context menu (right-click or ⋯): Open · Update · Uninstall · Show first binding on keyboard (jumps to main window with that key focused).

**Empty state:** "No packs installed yet. Browse Discover →"

---

## Search

Always visible. Top of the Gallery, above the tabs.

Placeholder: *"Search packs or keys…"*

### Two kinds of query

1. **Pack search** (text): fuzzy match on pack name, description, author. Example: "caps" matches "Caps Lock Remap", "Caps Lock as Hyper", etc.
2. **Key search** (text with key name): typing a key name or symbol shows packs that touch that key. Example: "f" or "j" shows home-row mod packs. Example: "space" shows spacebar-leader packs.

Search detects what kind of query the user typed — treating single-character queries or bracketed queries like `[f]` as key searches; everything else as pack/text searches.

### Results

Inline below the search bar. Results are pack cards (see card grammar below) in a single list, relevance-sorted.

No category filtering in results. No "sort by" — results are already ranked by relevance.

### Behavior

- Search debounces at 120ms.
- Empty query clears the results area and returns to the tab that was active.
- Esc clears the search and returns focus to the tab.

---

## Pack card grammar

The pack card is the atom of the Gallery. It appears in Starter Kit, in collections, in category pages, in search results, and in My Packs (variant).

### Default card

Dimensions: **240 × 140 pt**. Large enough to show a meaningful diagram, small enough to fit 3 across in typical window widths.

```
┌──────────────────────────────┐  ← 12 pt corner radius
│                              │
│   [Pack icon + diagram]      │  ← upper 2/3 — visual
│                              │
├──────────────────────────────┤
│ Home-Row Mods                │  ← SF Pro Text 13 pt semibold
│ Hold home-row keys as mods   │  ← SF Pro Text 11 pt muted, 1 line max
│ 8 bindings                   │  ← SF Pro Text 10 pt secondary
└──────────────────────────────┘
```

### Visual elements

- **Upper area (80 pt tall)**: a representational illustration. Not a keyboard diagram per se — a visual that communicates what the pack is about.
  - For keycap-targeted packs (caps lock, space), show a single stylized keycap with the transformation.
  - For home-row packs, show the bottom row of a keyboard with the affected keys tinted.
  - For layer packs, show a small keyboard with a layer-tinted overlay.
  - Illustrations should share a consistent style: generous corner radii, soft shadows, the app's accent color used as the transformative highlight.
- **Pack name**: 13 pt semibold. Max one line.
- **Description one-liner**: 11 pt muted, max one line, ellipsize if needed.
- **Footer metadata**: 10 pt secondary. Varies by context:
  - In Discover/Categories/Search: *"{N} bindings"*
  - In My Packs: *"{N} bindings · installed {date}"* or *"{N} modified"* if partially overridden.

### States

- **Default**: as shown.
- **Hover**: elevates (shadow blur 2 pt → 8 pt), scales subtly to 1.02, 180ms spring.
- **Pressed**: scales to 0.98 for 100ms, then releases.
- **Installed indicator**: when a pack in a non-My-Packs context is already installed, a small check badge (bottom-right of illustration) marks it as *"✓ Installed"* in SF Symbols `checkmark.circle.fill` at 14 pt. No color change to the card.

### Card in My Packs

Slight variant: the lower metadata area includes an inline `[Update]` button if an update is available, positioned right of the footer text. No other differences.

### Card in dense contexts

For category pages and search results, where density matters more than richness, a **compact card** (240 × 72 pt) is available: illustration collapses to a 48×48 pt icon on the left; name + description stack on the right. Used only in category pages and search results by default.

### Not allowed

- No star ratings on cards.
- No install counts on cards.
- No "New" badges.
- No "Trending" badges.
- No relative time ("updated 3 days ago").

All of these are growth signals. Per exec direction, we don't use them.

---

## Collection pages (clicking into a Discover collection or a Category tile)

A collection page is a full page of pack cards.

### Layout

```
┌─────────────────────────────────────────────────────────┐
│  ← Discover                                         ✕   │
│                                                         │
│  Make Caps Lock Useful                                  │
│  A collection of six mappings that turn a wasted        │
│  key into one of the most powerful keys on your         │
│  keyboard.                                              │
│                                                         │
│  [ Sort: Name ▾ ]                                       │
│                                                         │
│  ┌──────┐  ┌──────┐  ┌──────┐                          │
│  │ Pack │  │ Pack │  │ Pack │                          │
│  │ card │  │ card │  │ card │                          │
│  └──────┘  └──────┘  └──────┘                          │
│                                                         │
│  ┌──────┐  ┌──────┐  ┌──────┐                          │
│  │ Pack │  │ Pack │  │ Pack │                          │
│  │ card │  │ card │  │ card │                          │
│  └──────┘  └──────┘  └──────┘                          │
└─────────────────────────────────────────────────────────┘
```

- Collection title as a proper page title (SF Pro Display 24 pt semibold).
- One paragraph of editorial copy below the title — what this collection is for, who wrote it, any context that helps the user pick.
- Cards in a 3-column grid (wraps to 2 on narrower windows, 1 on very narrow).
- Sort dropdown, top right of the grid.

### Back navigation

- `← Discover` or `← Categories` in the top-left to return to the parent tab.
- ✕ in the top-right dismisses the whole Gallery (back to main window).
- Browser-style back is not a thing — Gallery is a sheet, not a deep navigation stack.

---

## Gallery presentation mode

Per exec direction (focus on core interaction, not visibility), Gallery opens as a **full-window sheet** sliding up from the bottom of the main window.

- **Slide-up**: 300ms cubic-bezier(0.2, 0.8, 0.2, 1). Background dims to 40% black opacity over 200ms.
- **Dismiss**: reverse, 240ms.
- **Window resizes**: Gallery resizes with the main window. No fixed minimum size; layout adapts.

Alternative considered and rejected: separate window. Rejected because (a) it fragments focus, (b) it doesn't fit the "keyboard as canvas" principle — Gallery is a detour, not a parallel home, (c) multi-window is rarely the right answer on macOS for this kind of feature.

---

## What's in scope for Sprint 1 vs deferred

### In scope this sprint

- All the above IA and card grammar.
- Visual design of the pack card at full fidelity (done alongside Pack Detail once direction is picked — cards should share visual DNA with Pack Detail).
- At least three illustration styles explored for the card's upper visual area. One picked.
- Empty state design for My Packs.

### Deferred (Sprint 2 or later)

- Collection page full visual design (basic structure is enough for Sprint 1).
- Search UI polish (input styling, result transitions).
- Pack icon system (see Pack Detail open question).
- Any localization / RTL considerations beyond mirroring the grid.

---

## Dependencies on Pack Detail direction

Most of this document is independent of which Pack Detail direction is picked. But:

- **If Direction A (Product Page)** is picked: card illustrations should have a *product-page vibe* — confident, illustrative, with the pack name as a meaningful element. Cards and Pack Detail pages share a visual DNA that says "these are things."
- **If Direction B (Live Preview)** is picked: card illustrations should hint at *interactivity* — maybe an animated pulse on hover, or a subtle "action" affordance visual. Cards feel like switches, not book covers.
- **If Direction C (In-place Modification)** is picked: card illustrations should be *more abstract/restrained* — since the pack's "real" preview is the user's own keyboard, the card illustration just needs to evoke the pack's character, not demo it. Simpler, more symbolic.

I'll align card visuals with the picked direction once we have the decision.

---

## Open questions

1. **Pack icon vs. illustration.** Do packs have identity elements (icons/logos) distinct from the card illustration, or is the illustration the whole visual identity? I'm leaning "illustration is the identity" for v1 — avoids the need for pack authors to provide logos.
2. **"Installed" badge on non-My-Packs cards.** Do we show the ✓ Installed indicator in Discover/Categories/Search? I recommend yes — it prevents redundant evaluation of something the user already has. Confirmed, but flagging in case anyone disagrees.
3. **Key search edge cases.** How do we handle queries like "caps lock" (two words matching a key name), or "cmd+space" (a shortcut, not a single key)? Proposal: treat multi-word queries as text search by default; key search only fires on single-token queries that match known key identifiers.

None of these block progress. Flagging for awareness.
