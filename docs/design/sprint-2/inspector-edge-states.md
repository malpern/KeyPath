# Inspector — Full Edge-State Matrix

**Sprint:** 2
**Status:** Draft — synthesizes precedence, coherence, layers
**Builds on:** [`override-precedence.md`](override-precedence.md), [`pack-coherence.md`](pack-coherence.md), [`layers-and-packs.md`](layers-and-packs.md)

---

## Purpose

The inspector is the primary editing surface. It renders for every possible state a selected key can be in. This doc enumerates those states and specifies what the inspector shows and offers in each.

Draft 1 specified only three inspector states (no selection / unbound / bound). That's about 20% of the state space. The rest was implicit. This doc makes it explicit so engineering can build the right thing.

---

## State dimensions

For any selected key, the inspector's display is determined by a combination of:

1. **Layer context** — viewing base, or viewing a non-base layer.
2. **Binding presence** — has a binding on current layer? Or on another layer? Or nowhere?
3. **Source** — direct binding? Pack-contributed? Multiple sources (shadowed)?
4. **Coherence** — if part of a pack, is the pack healthy / modified / shadowed / broken on this key?
5. **Behavior type** — simple remap? Tap-hold? Chord member? Layer trigger? Scoped?

That's a 2 × 3 × 4 × 5 × 5 = 600-state space in principle. In practice, most combinations don't occur, and many collapse to the same display. This doc defines the twelve *canonical* inspector states — the ones we design for — and the rules for assembling any particular state's display from shared building blocks.

---

## Building blocks — the inspector's anatomy

Every inspector state is composed of some subset of these blocks, in this vertical order:

```
1. Header block              ← always shown
   ├── Key visual (64×64 keycap)
   └── Key name + layer context

2. Effective binding block   ← shown if any binding is effective
   ├── Tap output
   ├── Hold output (if applicable)
   ├── Trigger type (if applicable: chord, layer trigger)
   └── Scope note (if scoped)

3. Source block              ← shown if effective binding has a named source
   ├── Primary source: "Direct" | "Pack: X"
   └── Secondary (optional disclosure): shadowed sources, pack coherence note

4. Edit actions block        ← always shown when not in record mode
   ├── Primary action
   ├── Secondary actions (remove, override, etc.)
   └── Advanced disclosures (hold, scope, layer)

5. Popular-for-this-key block ← shown if no effective binding AND key has known suggestions
   └── 2-4 preset chips

6. Related-packs block       ← shown if binding came from a pack
   └── "More like this" / "Browse Gallery"
```

Not every block appears in every state. The ruleset for which blocks appear in which state is defined below.

---

## The twelve canonical states

I'll walk each state, showing the inspector in a wireframe, then note which blocks are shown and any special behavior.

---

### State 1 — No key selected

```
╭───────────────────────────────────╮
│                                   │
│        [large keyboard icon]      │
│          (muted, centered)        │
│                                   │
│        Click any key to edit      │
│        its mapping.               │
│                                   │
│        or                         │
│                                   │
│     [ Browse the Gallery → ]      │
│                                   │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** Empty-state illustration + CTA.
**Actions:** Open Gallery.
**Notes:** This is the wizard's default state when the app opens. In production, users rarely see this — they'll either be viewing a pre-clicked key or browsing.

---

### State 2 — Unbound key on base layer

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │  Q  │   Q                     │
│   └─────┘   on base layer         │
│                                   │
│   ── Output ──────────────────    │
│   [ Record output ]               │
│   [ Type...       ]               │
│                                   │
│   ── Popular for this key ───     │
│   [ Tmux-style bind → ]           │
│   [ Q as Quick Look → ]           │
│   [ Browse Gallery →  ]           │
│                                   │
│   ── Advanced ────────────────    │
│   [▸ Hold behavior...]            │
│   [▸ Device scope...]             │
│   [▸ App scope...]                │
│   [▸ Move to a layer...]          │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1 (header), 4 (edit actions — primary is "Record output"), 5 (popular for this key — if any exist), 6 implicit.
**Actions:** Record, type, expand advanced options.
**Notes:** If no packs target this key, block 5 is omitted entirely. No empty chip row.

---

### State 3 — Bound key on base, direct binding, simple remap

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ ⇪   │   Caps Lock             │
│   │ →esc│   on base layer         │
│   └─────┘                         │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap:   Escape                   │
│                                   │
│   Source: Direct mapping          │
│                                   │
│   [ Edit mapping ]                │
│   [ Remove       ]  (destructive) │
│                                   │
│   ── Advanced ────────────────    │
│   [▸ Hold behavior...]            │
│   [▸ Device scope...]             │
│   [▸ App scope...]                │
│                                   │
│   ── More like this ──────────    │
│   [ Browse Caps Lock packs → ]    │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2 (tap only), 3 (direct), 4, 6.
**Actions:** Edit (re-records), Remove (unbinds), advanced disclosures.
**Notes:** The "more like this" block invites discovery of related packs without being pushy. One link, not an embedded gallery.

---

### State 4 — Bound key on base, direct binding, tap + hold

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ ⇪   │   Caps Lock             │
│   │ →esc│   on base layer         │
│   │ ⌃⌥⇧⌘│                         │
│   └─────┘                         │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap:   Escape                   │
│   Hold:  ⌃⌥⇧⌘ (Hyper)             │
│                                   │
│   Source: Direct mapping          │
│                                   │
│   [ Edit mapping ]                │
│   [ Remove       ]                │
│                                   │
│   ── Advanced ────────────────    │
│   Hold timeout: 200 ms  [ Edit ]  │
│   [▸ Device scope...]             │
│   [▸ App scope...]                │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2 (tap + hold), 3, 4, advanced expanded to show hold timing since hold is present.
**Actions:** Edit the whole mapping, edit just the timeout (inline), remove.

---

### State 5 — Bound key on base, pack-contributed, healthy

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ A   │   A                     │
│   │     │   on base layer         │
│   │  ⌃  │                         │
│   └─────┘                         │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap:   a                        │
│   Hold:  Control (⌃)              │
│                                   │
│   Source: Home-Row Mods pack  →   │
│                                   │
│   [ Edit my own mapping ]         │
│   [ Restore defaults    ]  (muted)│
│                                   │
│   ── Advanced ────────────────    │
│   [▸ Hold behavior...]  (disabled)│
│   [▸ Device scope...]             │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2, 3 (pack), 4.
**Actions:**
- "Edit my own mapping" — creates a direct binding that will override the pack's (triggers coherence warning per pack policy).
- "Restore defaults" — no-op when healthy; appears muted/disabled.
- Some advanced settings (like Hold behavior) are disabled because they're owned by the pack. To edit them, use the pack's Customize UI (tap the pack link).

**Notes:** Source block includes a tappable arrow → opens Pack Detail for Home-Row Mods.

---

### State 6 — Bound key on base, pack-contributed, **user-overridden** (Modified)

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ D   │   D                     │
│   │ →d  │   on base layer         │
│   └─────┘                         │
│                                   │
│   ── Mapping (your override) ──   │
│   Tap:   d                        │
│   Hold:  (nothing)                │
│                                   │
│   Source: Direct (you)            │
│   ⚠ Overrides Home-Row Mods       │
│     Pack's default was:           │
│       Tap: d, Hold: Shift (⇧)     │
│                                   │
│   [ Edit mapping              ]   │
│   [ Release — restore Home-Row    │
│     Mods' default              ]  │
│   [ Remove mapping entirely   ]   │
│                                   │
│   ── Advanced ────────────────    │
│   ...                             │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2, 3 (modified note), 4 (three options).
**Actions:**
- Edit (stay as direct).
- Release — remove the direct binding, letting the pack's shadowed binding resurface.
- Remove — set the key to unbound (different from Release: this leaves no binding at all).

**Notes:** The inspector surfaces the pack's default explicitly. No modal asking "keep new or keep existing" — the user already has their override; they're just viewing it. The "Release" affordance is the opposite of "override" and is explicit.

---

### State 7 — Bound key on base, pack-contributed, **shadowed by another pack**

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ J   │   J                     │
│   │ ↓   │   on base layer         │
│   └─────┘                         │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap:   Down Arrow               │
│                                   │
│   Source: Vim Navigation pack  →  │
│   ◆ Home-Row Mods also maps this  │
│     key, but is shadowed by the   │
│     more recently installed Vim   │
│     Navigation pack.              │
│   [▸ See other sources ]          │
│                                   │
│   [ Edit my own mapping ]         │
│                                   │
│   ── Advanced ────────────────    │
│   ...                             │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2, 3 (with secondary disclosure for shadowed sources), 4.
**Actions:**
- Edit (create direct override).
- "See other sources" disclosure expands:

```
     ── Active ───────────────────  
     · Vim Navigation pack →          
     ── Shadowed (not active) ────   
     · Home-Row Mods pack →           
       Would be: Tap: j, Hold: ⌘      
     · Hardware default               
```

This is the "what would happen if I removed things" view. Power-user affordance.

---

### State 8 — Key bound on another layer, not on current layer

Viewing base, but the key is bound on `vim-nav`.

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ J   │   J                     │
│   │     │   on base layer         │
│   └─────┘                         │
│                                   │
│   No mapping on this layer.       │
│                                   │
│   Bound on: Vim Navigation layer  │
│     → Down Arrow                  │
│     (from Vim Navigation pack)    │
│                                   │
│   ── Edit for base ───────────    │
│   [ Record output for base ]      │
│   [ Show Vim Navigation →   ]     │
│                                   │
│   ── Advanced ────────────────    │
│   [▸ Hold behavior...]            │
│   ...                             │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1 (with layer context), 2 (showing off-layer binding), 4.
**Actions:**
- Record / type — creates a direct binding on base for this key.
- "Show Vim Navigation" — switches the canvas to that layer (the user can then edit the binding there).

**Notes:** This is the state that lets the user understand "this key isn't unbound globally, it just isn't bound *here*."

---

### State 9 — Layer trigger key (on base, triggers a layer)

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ ⇪   │   Caps Lock             │
│   │→esc │   on base layer         │
│   │ →nav│                         │
│   └─────┘                         │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap:   Escape                   │
│   Hold:  Activate 'Vim            │
│          Navigation' layer  →     │
│                                   │
│   Source: Vim Navigation pack  →  │
│                                   │
│   [ Edit my own mapping    ]      │
│   [ Show Vim Navigation →  ]      │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2 (hold is a layer trigger, clickable), 3, 4.
**Notes:** The "Activate 'Vim Navigation' layer" text is a link. Clicking it switches the canvas. The keycap illustration shows the layer arrow glyph (→) in its corner to denote "this goes to a layer."

---

### State 10 — Viewing a non-base layer, key has binding on this layer

Viewing `vim-nav`, key is `j` with pack binding `j → Down`.

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ J   │   J                     │
│   │ ↓   │   on Vim Navigation     │
│   └─────┘   layer                 │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap:   Down Arrow               │
│                                   │
│   Source: Vim Navigation pack  →  │
│                                   │
│   [ Edit my own mapping ]         │
│                                   │
│   ── Also on ─────────────────    │
│   Base layer: (nothing — normal   │
│                'j' key)           │
│   [ Back to base layer ← ]        │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1 (with non-base layer context), 2, 3, 4, + "Also on" block (new) that summarizes the key's bindings on other layers.

**Notes:** "Also on" appears only for keys that have bindings on layers other than the one currently being viewed. Provides cross-layer context without leaving the current layer.

---

### State 11 — Key is a chord member

A key that, when pressed together with specific other keys, produces a chord output. Bound via a chord group.

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ J   │   J                     │
│   │ ◈   │   on base layer         │
│   └─────┘                         │
│                                   │
│   ── Mapping ─────────────────    │
│   Tap alone:  j                   │
│                                   │
│   Part of chord group:            │
│   · j + k pressed together → ESC  │
│   · j + f pressed together → TAB  │
│                                   │
│   Source: Chord Essentials pack   │
│                                   │
│   [ Edit my own mapping for J ]   │
│   [ Show chord group →         ]  │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2 (tap + chord memberships), 3, 4.
**Notes:** The keycap has a chord-member glyph (◈) to denote "this key is part of a chord group." Clicking "Show chord group" opens the Pack Detail for the chord source with the chord group highlighted.

---

### State 12 — Device-scoped binding

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │ A   │   A                     │
│   │     │   on base layer         │
│   │  ⌃  │                         │
│   └─────┘                         │
│                                   │
│   ── Mapping (when active) ──     │
│   Tap:   a                        │
│   Hold:  Control (⌃)              │
│                                   │
│   Only active on:                 │
│   · Built-in Apple keyboard       │
│                                   │
│   On other keyboards, this key    │
│   behaves normally (a).           │
│                                   │
│   Source: Home-Row Mods pack  →   │
│                                   │
│   [ Edit my own mapping ]         │
│   [ Change scope...     ]         │
│                                   │
╰───────────────────────────────────╯
```

**Blocks:** 1, 2 (scope note), 3, 4.
**Notes:** "Only active on" is an informational band above the actions, styled as a scope indicator (muted tint, maybe a small device icon). "Change scope…" lets the user modify the scope (if it's a direct binding) or shows an explanation for pack-contributed scopes ("Scope is managed by the Home-Row Mods pack — customize in the pack's settings").

---

## Special consideration — pack coherence glyphs in inspector

When the selected key's source pack is in a non-Healthy coherence state, the source block's pack link adorns with the coherence glyph:

- **Healthy:** `Source: Home-Row Mods pack →` (no glyph)
- **Modified (pack-wide):** `Source: Home-Row Mods pack ⚠ →` (yellow diamond after the name)
- **Shadowed:** not applicable to the winning binding's source (the winning binding's source is by definition not shadowed). Only the *shadowed* source in State 7's disclosure shows ◆.
- **Outdated:** `Source: Home-Row Mods pack ⟳ →` (update glyph)
- **Broken:** not possible — broken packs don't contribute effective bindings. User would never see a selected key with a Broken pack source.

---

## Interactions — common across states

### Entering record mode

Primary "Edit mapping" / "Record output" always enters record mode. Record mode changes the inspector chrome:

```
╭───────────────────────────────────╮
│   ┌─────┐                         │
│   │  A  │   Press any key…        │
│   └─────┘   (or Esc to cancel)    │
│                                   │
│   ⚡ Listening...                  │
│                                   │
╰───────────────────────────────────╯
```

Cancels on Esc (no change) or completes on a key press (updates binding).

### Advanced disclosures

All "Advanced" section disclosures (Hold behavior, Device scope, App scope, Move to layer) expand inline. They don't open modals or sheets. The panel scrolls if content grows.

### Hover over source chip

When hovering the source chip (e.g., "Home-Row Mods pack →"), a tooltip appears with a one-line summary of the pack and its coherence state. Click → Pack Detail.

---

## What the inspector does NOT show

To keep it focused, the inspector does not show:
- **Full pack manifest details** — those are in Pack Detail.
- **Other users' edits or templates** — no community data in the inspector.
- **Keyboard diagrams of other layers** — inspector is about one key on one layer at a time. "Also on" is text, not visual.
- **Statistics or usage data** — no "this key is pressed N times per day" or similar telemetry.
- **Recommendations beyond the "Popular for this key" block** — no "users like you also use these packs" ML stuff.

---

## Width and scrolling

Inspector is 340 pt wide (per Sprint 1 main-window spec). Content is anchored to top. If content overflows, the inspector scrolls independently of the keyboard canvas. The advanced disclosures are collapsed by default to minimize scroll.

---

## Accessibility notes

- Every building block has a clear VoiceOver grouping. Users can navigate block-by-block with VO.
- State 6 (user override) and State 7 (shadowed) are the most information-dense. VoiceOver labels make the relationships explicit: *"A, on base layer, mapped by your direct override. The Home-Row Mods pack's default for this key is Tap a, Hold Shift, but your direct binding takes precedence."*
- Coherence glyphs have text alternatives: ⚠ is read as "warning: pack modified."
- All state-revealing disclosures can be reached with keyboard (Tab/Shift-Tab).

---

## Open questions

1. **"Remove" vs. "Unbind" language.** State 3 has `[Remove]`. But "remove" in English implies something is being taken out of a collection. For a direct binding, this is correct — you're removing the binding. For a pack-contributed binding (State 5), we don't offer "Remove" because uninstalling the pack is the removal path; instead we offer "Release" (restore defaults after an override). Consistent language across states needs one more pass.

2. **Space allocation for long pack names.** "Home-Row Mods Full CAGS (Experimental)" as a source name could overflow the 340 pt inspector. Need a truncation pattern: probably middle-truncation with tooltip on hover.

3. **How many "Also on" layers to list.** If a user has a key bound on 5 non-current layers, does State 10's "Also on" block list all 5? Proposal: list up to 3, then "+2 more on other layers" disclosure. Avoids overwhelming the inspector.

4. **Multi-device visual treatment.** State 12 assumes one device scope. A pack could scope differently per device (Home-Row Mods on built-in, not on external). Inspector would need to show multiple scope bands — getting busy. May need a separate "Device behavior" inline table for multi-device scoped bindings.

---

## Related

- [`override-precedence.md`](override-precedence.md) — governs what's in the source block
- [`pack-coherence.md`](pack-coherence.md) — governs the glyph decorations on source chips
- [`layers-and-packs.md`](layers-and-packs.md) — governs the layer context header and "Also on" block
- Sprint 1 [`pack-detail-directions.md`](../sprint-1/pack-detail-directions.md) — the Pack Detail page every pack-source link opens
