# Mappings & Gallery — UX Specification

**Version:** Draft 1 · 2026-04-22
**Status:** Design review → Engineering handoff pending
**Contributors:** UX lead, Visual designer, Motion designer, Product/Marketing
**Audience:** Engineering (SwiftUI), QA, future contributors

---

## 1. Executive summary (Product/Marketing)

**Product position.** KeyPath is the most approachable way to make your keyboard yours. It hides no power from expert users, and it never makes beginners feel like they need to learn a config language.

**Central design idea.** Your keyboard is the canvas. Clicking a key tells you what it does and lets you change it. Everything else — presets, rules, packs, scopes — is secondary information revealed in context.

**The Gallery is our discovery moat.** Keyboard remapping has always suffered from "blank canvas" anxiety: users don't know what's possible until someone shows them. The Gallery is our answer — an App-Store-grade, curated discovery surface that turns remapping from a technical exercise into a browsing activity. Install a pack, keep browsing, share what you've made.

**Who we're building for.**
- **New users** who've heard "Caps Lock should be Escape" and want that to be easy.
- **Hobbyists** who know about home-row mods and hyper keys but don't want to edit S-expressions.
- **Power users** who want full control over their keyboard and will reach for the advanced UI when they need it.

All three need the same primary surface. They differ only in how deep they dig.

**Why now.** Our current UI has two top-level concepts ("Mapper" and "Rules") that don't correspond to the user's mental model. Users hit conflicts, dead-end save errors, and silent overrides. This spec replaces both with a unified model: one canvas, one inspector, one Gallery for discovery.

---

## 2. Goals and non-goals

### Goals

1. **One mental model.** Every customization is a **mapping**. Simple or complex, user-authored or pack-contributed — all bindings present identically to the user.
2. **The keyboard is the canvas.** Direct manipulation. Click a key, see what it does, edit it in place.
3. **Discovery is first-class.** The Gallery is a real product surface, not an afterthought.
4. **Progressive disclosure of complexity.** Simple case = inline inspector. Complex case = dedicated sheets reachable from consistent affordances.
5. **No blocking modals on user intent.** Conflicts become soft inline warnings. The user's save always wins.
6. **One canonical Pack Detail surface.** Reached from the Gallery, from contextual suggestions, and from installed-pack management. Never duplicated.

### Non-goals

- Redesigning the Installation Wizard (separate surface, out of scope).
- Rewriting KeyPath's data layer in one pass — this spec is for the UX. Internal data migration is engineering's call.
- Sharing / community / cloud sync. The architecture should accommodate it later; v1 ships local-only.
- Changing any existing kanata config semantics.

---

## 3. Vocabulary (for spec consistency)

| Term | Meaning |
|---|---|
| **Binding** | A single rule on a single key: input + effect (+ optional scope, behavior, metadata). All user-visible customizations are bindings. |
| **Pack** | A named, versioned collection of bindings that belong together (e.g., "Home-Row Mods", "Caps Lock Remap"). Has a manifest (name, author, version, description, config schema). |
| **Direct binding** | A binding the user created themselves via the inspector. No pack membership. |
| **Pack-contributed binding** | A binding installed as part of a pack. Carries a pack tag. |
| **Gallery** | The discovery surface where users browse and install packs. |
| **Pack Detail page** | The canonical surface for a single pack — invoked from many entry points, identical everywhere. |
| **Customize UI** | The detailed per-pack configuration editor (existing per-rule editors, repurposed as sheets). |
| **Inspector** | The right-side panel showing the currently-selected key's binding and edit affordances. |

Engineering note: "Rule" is deprecated from user-facing copy. Internal types can keep the name during migration, but nothing labeled "Rule" appears in the UI.

---

## 4. Information architecture

```
Main window
├── Keyboard canvas (primary, always visible)
├── Inspector panel (right side, shows selected key)
└── Toolbar
    ├── Layer selector
    ├── Device/scope filter (if applicable)
    ├── "Add from Gallery" button  ← entry point to Gallery
    └── Window controls

Gallery (separate window OR full-screen sheet)
├── Discover tab
│   ├── Featured / editorial
│   ├── Categories
│   ├── Search
│   └── Popular
├── My Packs tab (installed inventory)
└── → Pack Detail page (canonical)

Pack Detail page (reached from multiple entry points)
├── Header: name, author, version, description
├── Keyboard preview diagram
├── Binding list
├── Inline quick-config
├── Primary actions (Install / Customize… / Uninstall / Update)
└── → Customize UI (full detailed config sheet)

My Mappings list (secondary view of installed bindings)
├── Filter: all / by pack / by key / by scope
└── Per-row: binding + pack chip + edit action
```

**Navigation model.** The main window is always the home. The Gallery opens as a full-screen sheet or a separate window (see §5.2 below). Pack Detail is always a sheet overlaying whatever context invoked it. Customize UI is a sheet over Pack Detail. All sheets dismiss back to their calling context; no deep back-stacks.

---

## 5. Primary surfaces

### 5.1 Main window — keyboard canvas and inspector

#### 5.1.1 Layout

Two-pane layout, split approximately 65/35 horizontally. Keyboard canvas on the left, inspector on the right. Inspector is collapsible but visible by default.

Keyboard canvas renders the physical keyboard layout at a comfortable size (approx. 900×280 pt for a standard keyboard). Keys are interactive. Below the keyboard: layer tabs, device/scope selector.

Inspector is a vertical column, approximately 340 pt wide. Content anchored to top; scrollable if overflowing.

#### 5.1.2 Keycap visual states

Every key can be in one of these states:

| State | Visual treatment |
|---|---|
| **Unbound** | Default keycap. SF Mono label, neutral tint, subtle border. |
| **Direct binding** | Soft accent-color tint on the keycap face. 8% fill. No icon badge. |
| **Pack-contributed binding** | Same tint as direct binding. *Provenance is not shown on the keycap itself* (see §10 rationale). |
| **Selected** | Accent-color border (2 pt), elevated shadow, no tint change. |
| **Pack-member highlight** | Thin (1 pt) accent-color outline at 40% opacity — shown on all other keys in the pack when user hovers/selects a pack member. Fades in 120ms, out 200ms. |
| **Recording input** | Pulsing accent-color border. |

**Design intent.** The keyboard is about *what keys do*, not *where they came from*. Pack identity lives in the inspector and the Pack Detail page, not on the keycap itself. The pack-member highlight relationship is revealed only in context, not persistently.

#### 5.1.3 Inspector states

The inspector has three states, each with a consistent header:

**State A — No key selected.**
```
[Keyboard icon, large, centered, muted]

Click any key to edit its mapping, or
[Browse the Gallery →]  (button, secondary style)
```

**State B — Key selected, no binding.**
```
[Keycap visual, 64×64]
{Key name, e.g. "Caps Lock"}

── Output ────────────────────────
[ Record output ]  (primary button)
[ Type...      ]  (text field, secondary)

── Popular for this key ──────────
[ Make it Hyper → ]
[ Tap = Esc, Hold = Ctrl → ]
[ Home-Row Mods → ]
[ Browse Gallery → ]  (link, smaller)

── Advanced ──────────────────────
[> Hold behavior...]  (disclosure)
[> Device scope...]   (disclosure)
[> App scope...]      (disclosure)
[> Layer...]          (disclosure)
```

The "Popular for this key" section is filtered from the Gallery by key. If no relevant packs exist, the section is omitted entirely (not shown empty).

**State C — Key selected, has binding.**
```
[Keycap visual with output overlay, 64×64]
{Key name}

── Current mapping ───────────────
Tap:  esc
Hold: ⌃⌥⇧⌘
Scope: Built-in keyboard only

Part of: [ Home-Row Mods → ]   (chip, tappable)

── Actions ───────────────────────
[ Edit mapping ]  (primary)
[ Remove       ]  (destructive, subdued)

── Advanced ──────────────────────
[> Hold behavior...]
...

── More like this ────────────────
[ Browse related packs → ]  (link)
```

The "Part of" chip opens the Pack Detail page for the parent pack. The inspector never hosts pack-level editing — "Edit mapping" changes *this key's* binding; pack-wide config happens in Pack Detail.

#### 5.1.4 Interactions

- **Click key** → inspector updates to show that key. If the key is part of a pack, other pack members show a soft outline highlight.
- **Hover key (500ms)** → tooltip showing current binding, one-line format: `caps → tap: esc / hold: ⌃⌥⇧⌘`.
- **Right-click key** → context menu: *Edit mapping · Copy binding · Paste binding · Remove mapping · Show in Gallery (if part of a pack)*.
- **Cmd-Z** → undo last binding change. Supports full undo/redo stack per session.
- **Typing while key is selected** → starts record mode (capture next keystroke as output).

#### 5.1.5 Toolbar

Top of the main window:

```
[◀ Layer: Base ▾] [Device: All ▾]      [+ Add from Gallery] [≡]
```

- Layer dropdown: switch between user-defined layers. Current layer's bindings are what the keyboard renders.
- Device dropdown: filter bindings to a specific device if using device-scoped mappings.
- "Add from Gallery" is the primary path into the Gallery (see §5.2).
- Overflow menu (≡): access to My Mappings list, preferences, help.

### 5.2 Gallery

#### 5.2.1 Presentation

Opens as a **full-window sheet** sliding up from the bottom of the main window. Takes the full window bounds with rounded top corners. Dismissed via ✕ in top-left or Esc.

Alternative (design option): opens as a separate window. Pros: user can browse and edit in parallel. Cons: multi-window workflow is rare on macOS. **Recommendation: sheet.**

#### 5.2.2 Structure

Three top-level sections, navigable via tabs at the top:

1. **Discover** (default)
2. **Categories**
3. **My Packs**

Plus a persistent **Search** field and a ✕ to close.

#### 5.2.3 Discover tab

Editorial home. Four sections scrolling vertically:

- **Hero carousel**: 3–5 featured packs, large cards with keyboard-diagram imagery. Auto-rotates every 8 seconds (paused on hover). Each card shows pack name, one-line teaser, "See Pack" action.
- **Starter Kit**: a fixed row: "New to KeyPath? Try these." Three curated packs with small cards.
- **Popular this week**: horizontal scroll of pack cards by install count.
- **Editor's picks**: hand-curated themed collection. Rotates monthly.

Card design: 240×160 pt, rounded 12 pt. Keyboard diagram on top half (showing affected keys highlighted), pack name and author below. Hover: elevates 2 pt, subtle scale to 1.02.

#### 5.2.4 Categories tab

Flat grid of category tiles:

- Make Caps Lock Useful
- Home-Row Mods
- Layer-Based Workflows
- Vim-Style Navigation
- Writer's Toolkit
- One-Handed Typing
- Developer Essentials
- Gaming Keybindings
- Accessibility Aids

Each tile: 280×120 pt with representative icon/diagram. Click → category page showing all packs in that category, sortable by Popular / Newest / Name.

#### 5.2.5 My Packs tab

Installed inventory. Flat list of pack rows:

```
[pack icon] Home-Row Mods                  Installed Mar 14 · v2.1.0
            By KeyPath Team                [● Update available]
            8 bindings · 1 modified by you  [Open →]
```

Sort: Most recent / By name / By modification status.
Actions per row: Open (→ Pack Detail), Update (if available), Uninstall.
Empty state: "No packs installed yet. [Browse Discover →]"

#### 5.2.6 Search

Ever-present at the top. Placeholder: *"Search packs or keys…"*. Searching by a key name (e.g., "caps" or "space") returns all packs that touch that key, cross-cutting categories.

### 5.3 Pack Detail page

The canonical pack surface. Identical whether invoked from the Gallery, from a chip in the inspector, or from My Packs.

#### 5.3.1 Presentation

Opens as a **sheet overlaying the current surface**. If the current surface is the main window, it covers the right ~60% of the window. If the current surface is the Gallery, it slides in from the right as a navigation push (detail view pattern).

Size: 640 pt wide, height flexes to content up to 80% of screen height.

#### 5.3.2 Layout

```
───────────────────────────────────────────
[✕]              Home-Row Mods         v2.1.0

By KeyPath Team · 1,240 installs · ★ 4.8

Turn your home row into modifier keys. Hold a
to press ⌃, hold s to press ⌥, and so on.
Works like standard keys when tapped.

┌─────────────────────────────────────────┐
│  ┌─┐                                    │
│  │Q│ ┌W┐ ┌E┐ ┌R┐ ┌T┐ ┌Y┐ ┌U┐ ┌I┐ ┌O┐ ┌P┐ │
│  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ │
│   ┌A┐ ┌S┐ ┌D┐ ┌F┐ ┌G┐ ┌H┐ ┌J┐ ┌K┐ ┌L┐   │  ← affected keys glowing
│   └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘   │
└─────────────────────────────────────────┘

Keys this pack will map:
  a    tap: a     hold: ⌃
  s    tap: s     hold: ⌥
  d    tap: d     hold: ⇧
  f    tap: f     hold: ⌘
  j    tap: j     hold: ⌘
  k    tap: k     hold: ⇧
  l    tap: l     hold: ⌥
  ;    tap: ;     hold: ⌃

Quick settings:
  Hold timeout:  [====●====] 180ms
  Layout:        (●) CAGS  ( ) CGAS  ( ) Custom
  Only on:       [ Built-in keyboard ▾ ]

                    [ Customize… ]  [ Install ]
───────────────────────────────────────────
```

**Header**: pack icon (if provided), name, author, version. Below: metadata (install count, rating — future), description.

**Keyboard preview**: miniaturized keyboard diagram, affected keys highlighted with pack-specific accent. Animated glow on first appearance (see motion spec §7).

**Binding list**: compact rows, one per binding. Expandable if pack has many bindings.

**Quick settings**: inline controls for the most common customizations. Pack manifest declares these (sliders, toggles, chooser). This handles the 80% case.

**Primary actions**: two buttons right-aligned at bottom.
- Pre-install: **Customize…** (secondary) and **Install** (primary).
- Post-install, unmodified: **Uninstall** (destructive subdued) and **Edit configuration** (primary).
- Post-install, modified: add **Restore defaults** (subdued). Update available adds an **Update** pill near the version number.

#### 5.3.3 States

- **Pre-install**: as shown above.
- **Installing** (momentary): primary button morphs to show progress spinner. Button text "Installing…". Takes 200–400ms typically.
- **Installed — unmodified**: "Install" button becomes "Edit configuration". Small check badge near the name: *"✓ Installed"*.
- **Installed — modified**: *"✓ Installed · 1 key modified"* subtitle. "Restore defaults" action appears.
- **Update available**: orange-tinted pill near version: *"v2.1.1 available · [Update]"*.
- **Incompatible** (future): disabled Install button with explanation.

### 5.4 Customize UI (detailed configuration)

Reached via **Customize…** (pre-install) or **Edit configuration** (post-install) from the Pack Detail page. This is where your existing per-rule UIs live, now as sheets.

#### 5.4.1 Presentation

Opens as a sheet over the Pack Detail page. Same width (640 pt) if the pack config is simple; can expand wider (up to 960 pt) for complex packs with multiple panes.

#### 5.4.2 Structure

Each pack's Customize UI is bespoke to that pack — that's already the pattern you have. What this spec standardizes:

- A consistent **header**: pack name, version, ✕ to close.
- A consistent **footer**: two buttons, right-aligned. Pre-install: **Cancel** and **Install with these settings**. Post-install: **Cancel** and **Save changes**.
- Content area between: pack-specific UI.
- Escaping via ✕ or Esc always prompts for unsaved changes.

Pack authors (for built-in packs, that's the KeyPath team) are responsible for the content design per pack. This spec doesn't prescribe it beyond the shell.

---

## 6. Visual design system

### 6.1 Typography

- **Display/headlines**: SF Pro Display. H1 28 pt bold, H2 20 pt semibold, H3 15 pt semibold.
- **Body**: SF Pro Text. 13 pt regular, line-height 17 pt.
- **Keycap labels**: SF Mono. 11–13 pt medium depending on keycap size.
- **Secondary/muted**: SF Pro Text 12 pt regular, 60% opacity.
- **Chips and pills**: SF Pro Text 11 pt medium.

### 6.2 Color

- **Accent**: system accent color (user's macOS preference). Used for selection, primary buttons, bound-key tint.
- **Pack highlight** (for the pack-member outline effect): accent at 40% opacity.
- **Semantic**:
  - Success: system green
  - Warning: system orange
  - Destructive: system red
  - Informational: system blue
- **Surfaces**:
  - Main window background: `windowBackgroundColor`
  - Keyboard canvas: `controlBackgroundColor` with 4 pt padding
  - Inspector: `controlBackgroundColor`
  - Sheets and popovers: `regularMaterial` on macOS 15, `.glass` on macOS 26+
- **Keycap**:
  - Unbound fill: `controlColor` with 50% opacity
  - Bound fill: accent at 8% opacity
  - Border: `separatorColor` 1 pt

All colors respect Dark Mode; designs must be reviewed in both.

### 6.3 Spacing

8 pt grid throughout. Component padding commonly 12 pt or 16 pt. Section gap 24 pt. Inspector column padding: 16 pt horizontal, 20 pt top/bottom.

### 6.4 Iconography

SF Symbols exclusively. Common symbols:
- `keyboard` — keyboard references
- `square.grid.2x2` — Gallery / grid views
- `cube.box` — pack
- `square.and.arrow.down` — install
- `arrow.triangle.2.circlepath` — update
- `slider.horizontal.3` — customize
- `trash` — uninstall/remove
- `exclamationmark.triangle` — soft warnings
- `checkmark.circle.fill` — installed/success

### 6.5 Liquid Glass (macOS 26+)

- Sheets and popovers use `.glass` material when available (`#if compiler(>=6.2)` + `#available(macOS 26, *)`).
- Keycap highlight on selection uses a subtle glass effect on macOS 26+ instead of flat tint.
- Inspector background becomes a glass panel on macOS 26+, with a soft drop shadow connecting it to the keyboard canvas.
- Fallback on macOS 15: `regularMaterial` and flat tint.

### 6.6 Keycap component

A reusable `KeycapView` component. Sizes: 32 pt, 48 pt, 64 pt, 88 pt. All sizes share the same visual grammar:
- Rounded rectangle, corner radius = size × 0.12
- Optional label on face (SF Mono)
- Optional secondary label for hold/tap layered keys (two-row grid, smaller font)
- Optional icon (SF Symbol) replacing label for non-alphanumeric keys
- State-dependent fill and border per §5.1.2

---

## 7. Motion & transitions

The motion designer's priorities: clarity over showmanship, continuity over novelty.

### 7.1 Sheet presentation

- **Gallery sheet**: slides from bottom, 300ms, easeOut. Background dims to 50% black with 250ms fade.
- **Pack Detail sheet (from chip)**: slides from right, 280ms, spring (response 0.4, damping 0.85). Slight overshoot permitted.
- **Customize sheet (over Pack Detail)**: crossfade and scale from 0.96 → 1.0, 240ms.
- **Dismiss**: reverse of presentation, 220ms.

### 7.2 Selection and pack-member highlight

- **Key selection**: instant border change (no delay). Shadow elevates over 150ms.
- **Pack-member highlight**: fade in 120ms easeOut. Fade out 200ms easeIn when selection moves. If selection changes to another pack, briefly (80ms) show no highlight before the new pack's highlight appears — avoids a jarring "relay" where outlines swap on different keys simultaneously.

### 7.3 Install animation

When user installs a pack from Pack Detail:
1. Install button morphs to spinner for duration of the install (200–400ms typical).
2. Affected keys on the main window's keyboard pulse once each, staggered by 40ms from left to right, accent-color tint swell from 0% → 12% → 8% fill over 300ms per key.
3. A toast appears at the bottom of the main window: *"Home-Row Mods installed · 8 bindings added"* with an Undo button. Slides up 250ms, dwells 4 seconds, fades out 400ms.

The cascading pulse is the pack's "arrival moment" — it makes the abstract ("a pack was installed") physical ("these specific keys just got new powers"). Not decorative; functional feedback.

### 7.4 Override warning

When the user overrides a pack-contributed binding:
- Save completes instantly (no modal).
- Inline warning badge appears below the inspector's "Current mapping" section: *"Overrode Home-Row Mods on this key"* with an Undo link. Fades in 180ms, dwells until user interacts again.
- No animation on the keyboard canvas itself — the override is a metadata change, not a spatial one.

### 7.5 Keycap hover tooltip

Appears after 500ms hover delay. Fades in 150ms. Follows cursor until the user leaves the keycap, then fades out 120ms.

### 7.6 Gallery card hover

Card elevates (shadow increases from 2 pt blur to 12 pt blur), scales to 1.02, 180ms spring. On click: card briefly scales down to 0.98 (100ms) then back to 1.0, while the Pack Detail sheet begins its entrance. Provides a tactile "you pressed this" feedback.

### 7.7 Motion preferences

All animations respect `Reduce Motion`:
- Slides become crossfades.
- Springs become linear.
- Cascading key pulse becomes a single simultaneous flash.
- Gallery card hover elevation still happens but without scale.

---

## 8. Interaction patterns (cross-surface)

### 8.1 Navigation model

- Main window is always the root.
- Gallery is a sheet over the main window. Closing Gallery returns to the main window with any changes applied.
- Pack Detail is a sheet over either the Gallery (deep link from a card) or the main window (deep link from a chip / pack membership chip).
- Customize is a sheet over Pack Detail.
- Back affordance: always a ✕ close button at top-left of the sheet, plus Esc as keyboard shortcut. No back arrows — sheets dismiss flat, they don't navigate deeper into a stack.

### 8.2 Conflict resolution (replaces today's modal)

Previous flow: modal dialog with "keep new / keep existing". Deprecated.

New flow: when the user saves a binding that conflicts with a pack-contributed binding:
1. Save completes immediately. User's mapping is now active.
2. Override is logged: pack membership removed from that key's binding.
3. Inline warning in inspector appears (§7.4).
4. Pack's status across the app updates to "1 key modified".

No user choice is asked. If they regret it, Undo is a click away.

### 8.3 Installing a pack — canonical flow

1. User clicks a pack anywhere (Gallery card, inspector chip, Pack Detail link).
2. Pack Detail sheet appears.
3. Quick settings are editable inline; defaults are sensible for most users.
4. User clicks **Install**.
5. Button morphs to spinner. Installation runs (~200–400ms).
6. Sheet dismisses with slide-down.
7. Affected keys cascade-pulse on the main window keyboard.
8. Toast appears: *"X installed · N bindings added"* with Undo.

If the user instead clicks **Customize…**: Customize sheet slides in over the Pack Detail, user configures, clicks **Install with these settings**, same installation sequence as above (steps 5–8).

### 8.4 Uninstalling a pack

1. User opens Pack Detail for an installed pack (any entry point).
2. Clicks **Uninstall** (destructive button).
3. Confirmation: small popover attached to the button — *"Remove 8 bindings from your keyboard?"* with **Cancel** / **Uninstall** buttons. Not a full modal.
4. On confirm: pack bindings are removed from the user's config.
5. Affected keys fade from bound → unbound (reverse of install cascade).
6. Toast: *"Home-Row Mods uninstalled"* with Undo.

### 8.5 Updating a pack

1. Update availability is surfaced in multiple places: Pack Detail header badge, My Packs row indicator, Gallery Discover tab (if user has an outdated pack).
2. User clicks **Update**.
3. Pack manifest fetches, diff is computed (new bindings added / existing changed / removed).
4. A diff preview appears: *"2 bindings changed, 1 added. Review changes →"* with inline expand.
5. User confirms.
6. Update is applied as a single atomic operation. Toast: *"Home-Row Mods updated to v2.1.1"*.
7. User-overridden keys are preserved — the update applies only to unmodified pack members.

### 8.6 Copy / paste bindings

Right-click a key → Copy binding. Right-click another key → Paste binding. Preserves all binding metadata (tap, hold, scope) but strips pack membership (the paste is a direct binding, not a pack-contributed one).

### 8.7 Keyboard navigation

- Arrow keys: move selection between keys (up/down/left/right on the canvas).
- Enter: begin recording output for the selected key.
- Esc: deselect key / dismiss sheet / close Gallery.
- Cmd-F: focus Gallery search field (when Gallery is open).
- Tab / Shift-Tab: move between inspector controls.

Full keyboard-only navigation must be possible. No click-only affordances.

---

## 9. Edge cases and error states

### 9.1 No keys bound yet (empty keyboard)

The keyboard canvas shows all keys unbound. The inspector (when no key selected) shows an invitation: *"Click a key to edit its mapping, or browse the Gallery →"*. The toolbar's "Add from Gallery" button gets a subtle accent-color pulse (2 seconds after idle) to draw attention on first run.

### 9.2 Pack install fails

If installation can't complete (helper XPC failure, disk error, invalid manifest):
- Install button returns to its pre-click state.
- Inline error below the button: *"Couldn't install. {reason}. Try again."* with a Retry affordance.
- No destructive state — nothing was partially installed.

### 9.3 Pack is fully overridden

Every member of a pack has been replaced by direct bindings. Pack Detail shows: *"Fully customized · 0 of 8 pack bindings active"* with a **Restore defaults** button. The pack is still "installed" in the manifest sense; user can revert.

### 9.4 Conflicting pack installs

User installs Pack A, then installs Pack B that touches some of the same keys. Our default: **most recent install wins** per key (precedence model). Pack A's metadata on those keys is marked "overridden by Pack B install". Inspector and Pack A's detail page reflect this.

User can see in Pack A's detail: *"3 keys overridden by Home-Row Mods"*. Restore restores Pack A's bindings, which in turn marks Pack B's bindings as overridden. This is symmetric.

### 9.5 No bindings and Gallery is empty (first run, offline)

Gallery Discover tab shows an offline empty state: *"No packs available. Check your internet connection or continue with manual mappings."* The keyboard canvas and inspector work fully without the Gallery.

### 9.6 Rapid sequential installs

If the user installs two packs in quick succession, cascade-pulse animations may overlap. Solution: the second install's cascade starts after the first completes — queue, don't stack.

### 9.7 Recording output timeout

If the user clicks "Record output" and doesn't press anything for 10 seconds, recording auto-cancels with a subtle shake of the record button. No error, just an abort.

---

## 10. Accessibility

- **VoiceOver**: every keycap is a labeled button. Label format: *"Caps Lock, currently mapped to Escape, part of Home-Row Mods pack. Double tap to edit."* Inspector controls all labeled and grouped.
- **Dynamic Type**: respect system text size. Keycap labels scale within physical bounds; some truncation with tooltip-on-hover fallback is acceptable for very large type settings.
- **High Contrast**: switch to outlined keycap states rather than subtle fills. Pack-member outlines thicken from 1 pt to 2 pt.
- **Reduce Motion**: see §7.7.
- **Reduce Transparency**: replace Liquid Glass / material with solid `controlBackgroundColor` plus a 1 pt border.
- **Keyboard-only navigation**: see §8.7. All sheets trap focus correctly; Esc always works.
- **Color vs. state**: never encode state using color alone. Selected = border + shadow; bound = tint + a subtle indicator glyph in the keycap's corner at sizes ≥ 48 pt.

---

## 11. Product/marketing notes

### 11.1 First-run onboarding

First launch after Installation Wizard completion:
1. User lands on main window with empty keyboard.
2. Overlay tour (one pass, skippable): highlights "Click any key to start" and "Browse the Gallery for ready-made packs".
3. Gently suggests: *"Start with a preset?"* with a single CTA opening the Gallery Discover tab scrolled to Starter Kit.

Users who dismiss the tour never see it again. A help menu item reopens it on demand.

### 11.2 Naming

User-facing terminology (final):
- Customizations → **mappings**
- Rules / rule collections → **packs**
- Rules tab → **Gallery**
- Inspector / right panel → unchanged, or rename to **Mapping Inspector**
- Custom Rules panel → deprecated (merged into My Packs)

### 11.3 Brand tone

The Gallery is the product's most marketing-y surface. Editorial voice:
- Approachable. "Make your caps lock useful again." Not "configure a dual-role key binding."
- Expert-aware. Don't dumb down — explain timing, tap/hold, precedence where users will naturally ask.
- Celebratory when appropriate. Install toasts can be warm: *"Welcome to your new home row."* Not over-done.

### 11.4 Success metrics (engineering coordinate with product to instrument)

- % of new users who install ≥ 1 pack within first session.
- Distribution of Gallery time-to-first-install.
- Override rate: % of pack bindings that get user-modified.
- Customize… click-through rate on Pack Detail.
- Gallery return rate: weekly active Gallery opens per user.

---

## 12. Open questions for engineering / product review

1. **Pack manifest format.** This spec assumes packs have a manifest with name, version, description, keys-affected, config-schema, and binding template. Engineering to propose concrete JSON schema. Product to sign off on which fields are required vs optional.
2. **Pack update mechanism.** Over-the-wire update of built-in packs: how? Bundled in app vs fetched from a CDN? Signing? First-pass probably bundled.
3. **User-authored packs.** Can users export their direct bindings as a pack to share? Roadmap question. This spec is forward-compatible with "yes, later."
4. **Device scope on pack bindings.** If a pack has device-scoped bindings, how is that communicated in the preview keyboard diagram? Multiple keyboard diagrams per device? One diagram with a device selector?
5. **Layer-scoped packs.** A pack may define bindings across multiple layers (e.g., a Vim pack with a "navigation" layer). The Pack Detail keyboard preview needs a layer selector. TBD.
6. **Simple-vs-complex threshold for quick settings inline.** Each pack's manifest should declare its "quick settings" schema. What counts as simple enough to surface in Pack Detail vs requiring Customize…? Propose: toggles, sliders with labeled values, enum pickers. Anything with >3 dimensions or custom components routes to Customize.
7. **Search indexing.** Gallery search by key name requires packs to tag the keys they touch. Manifest must include this. By-category search is straightforward; full-text search against description is optional for v1.
8. **Analytics privacy posture.** If we instrument per §11.4, local-only? Aggregate? User opt-in? Product to decide before engineering implements.

---

## 13. Out of scope (for v1)

- Community pack submissions / ratings / reviews.
- Cloud sync of user configurations.
- Redesign of the Installation Wizard.
- Redesign of Settings (preferences, permissions, advanced).
- Multi-user / profile switching.
- Import from Karabiner Elements or other tools.

All are compatible with this architecture but are separate tracks.

---

## 14. Implementation sequencing (suggested)

Rough phases. Engineering may reorder.

**Phase 1 — Data unification.**
- Introduce unified `Binding` type. Migrate existing direct remaps and rule-sourced bindings to the new type.
- Introduce `Pack` manifest type + metadata on bindings.
- No UI changes yet. Backend-only.

**Phase 2 — Inspector redesign.**
- Rebuild right-side inspector per §5.1.3.
- Add pack-membership chip.
- Remove conflict-resolution modal.
- Add override warning inline.

**Phase 3 — Pack Detail page.**
- Build canonical Pack Detail component per §5.3.
- Wire install/uninstall/update flows.
- Route the existing per-rule Customize UIs as Customize sheets.

**Phase 4 — Gallery.**
- Build Gallery shell (Discover / Categories / My Packs tabs).
- Curate initial pack content.
- Wire search.

**Phase 5 — Polish.**
- Motion per §7.
- Accessibility pass.
- First-run onboarding.
- Liquid Glass adoption on macOS 26.

Each phase is independently shippable. Phase 1 has no user-visible change but is prerequisite for 2+. Phase 2 can ship before the Gallery (§5.2) if we keep the existing Rules tab temporarily as a bridge.

---

## 15. Appendix — example binding object (for reference)

```swift
struct Binding {
    let key: KeyIdentifier
    let tapOutput: KeyAction?
    let holdOutput: KeyAction?
    let timing: HoldTiming?
    let scope: BindingScope   // device, app, layer, global
    let source: BindingSource // .direct | .pack(PackReference)
    let metadata: BindingMetadata
}

struct PackReference {
    let packID: String
    let packName: String
    let installedVersion: String
    let originalConfigHash: String
    let isModified: Bool  // computed: user has changed this binding since install
}
```

For illustration only. Engineering owns final types.

---

**End of spec. Please review and annotate. Open questions in §12 should be resolved before Phase 1 kicks off.**
