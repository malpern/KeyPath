# Starter Kit — Bundled Pack List for v1

**Sprint:** 1 · Day 7
**Status:** Draft list for review
**Intent:** 10–12 packs bundled with the app so the Gallery is never empty and a new user can make their keyboard better in under two minutes.

---

## Why this list exists

A Gallery that depends on a network connection to have content is a Gallery that fails on first launch, in airplane mode, and behind corporate firewalls. The Starter Kit is the set of packs that ship *inside* the app bundle and are available unconditionally.

Per the exec direction, we are not designing "Today" or growth mechanisms. That makes the Starter Kit more important, not less — it's the curated face of the product for every first-time user, and it needs to work without us doing anything clever.

---

## Selection criteria

Each pack in the Starter Kit must meet all four:

1. **Obvious value.** A new user reading the description in under ten seconds understands why this would make their typing better.
2. **Safe defaults.** Installing the pack at default settings does not break or confuse typing for someone who doesn't yet know what tap-hold or home-row mods are.
3. **Representative of a category.** Each Starter Kit pack is the exemplar of a broader family — installing it teaches the user what that category does.
4. **Easy to uninstall.** The pack explicitly supports clean removal with no residual state. If someone tries it and doesn't like it, restoring their keyboard is one click.

---

## The list

Twelve packs across seven thematic clusters.

### Caps Lock hacks (3 packs)

The canonical "why I installed KeyPath" gateway. Most new users are here because they've heard Caps Lock should be Escape.

1. **Caps Lock → Escape.** The classic. Tap caps, get escape. No hold behavior. Single binding, single key. As close to a zero-config pack as exists.
2. **Caps Lock as Hyper.** Tap for escape, hold for ⌃⌥⇧⌘. Adds a modifier key users can bind to anything. Introduces the concept of tap-vs-hold with a gentle onramp.
3. **Caps Lock as Layer Toggle.** Tap for escape, hold activates a nav layer where h/j/k/l become arrow keys. Introduces the concept of layers. Bigger conceptual leap, but the payoff (Vim navigation on any key) is tangible.

### Home-row modifiers (2 packs)

The "hobby entry" — once users have played with caps-lock hacks, home-row mods are the natural next level.

4. **Home-Row Mods — Light.** Only the index and middle fingers on each hand carry modifiers (f=⌘, d=⇧, j=⌘, k=⇧). Fewer mods, easier to learn, fewer accidental triggers. Good onramp.
5. **Home-Row Mods — Full CAGS.** All eight home-row keys carry modifiers in the CAGS layout (⌃⌥⌘⇧ / ⇧⌘⌥⌃). The full experience. Default quick-settings configurable.

### Writer's toolkit (2 packs)

Not hobby-nerdy. Aimed at people who type prose for a living and want small quality-of-life improvements.

6. **Smart Quotes & Dashes.** Convert straight quotes to curly, `--` to em-dash, `...` to ellipsis. Only active when typing into text fields (scope: global but only when no modifier is held). Zero learning curve.
7. **One-Hand Symbol Layer.** Hold semicolon to turn the left hand into a symbol layer (numbers, brackets, arrows). Great for writers who don't want to reach for the number row.

### Developer essentials (2 packs)

The other professional audience.

8. **Tmux-Style Escape.** Remap ⌃b to a more comfortable trigger (default: ⌃Space). Small but often-requested.
9. **Bracket Dance.** `[` + `]` when held become layer triggers for brackets and symbols useful in programming. Aimed at users who do a lot of nested symbol-heavy editing.

### Accessibility (1 pack)

Packs designed for people with typing impairments. The Starter Kit should represent this category clearly.

10. **Sticky Modifiers.** Tap ⇧/⌃/⌥/⌘ to latch them until the next key press. Apple has a similar feature at the OS level; KeyPath's version is configurable per modifier and works with tap-hold.

### Gaming (1 pack)

Smaller audience, but worth one representative pack to say "KeyPath isn't just for writers and developers."

11. **WASD to Arrows.** Remap WASD to arrow keys for games that don't support customization, scoped to only activate when a specific game is in the foreground.

### Layer workflows (1 pack)

Showcases the full layer pattern.

12. **Vim Navigation Layer.** The full Vim-like navigation experience as a layer. This is not for everyone, but it's the pack that demonstrates KeyPath's high ceiling. Included in Starter Kit explicitly to signal "this is what's possible."

---

## Counts and coverage

Twelve packs, organized across seven clusters. Covers:

- **Simple single-key remaps** (1 pack): Caps → Escape
- **Tap-hold single-key** (3 packs): Caps Hyper, Caps Layer, Tmux
- **Multi-key patterns** (3 packs): Home-row Light, Home-row Full, Bracket Dance
- **Scoped-to-app** (1 pack): WASD
- **Scoped-to-text-context** (1 pack): Smart Quotes
- **System-style features** (1 pack): Sticky Modifiers
- **Full layer** (1 pack): Vim Navigation
- **Symbol-density** (1 pack): One-Hand Symbol Layer

No pack is there just to fill a slot. Each teaches a distinct capability.

---

## What we're NOT including in the Starter Kit

- **Ergonomic thumb-cluster remaps.** The audience that wants this (split keyboard users) self-selects; they don't need a bundled pack to discover the idea.
- **Colemak / Dvorak layout switching.** KeyPath supports this, but it's a whole-layout change, not a "pack" in the Starter Kit sense. Better surfaced in System Settings or a dedicated layout picker.
- **Custom shortcut macros.** Too open-ended — what a macro *should do* is so personal that a curated pack will always disappoint.
- **Any vendor-specific pack** (e.g., "Apple Magic Keyboard optimizations", "Logitech MX Keys bindings"). These come later as device-scoped pack offerings; not Starter Kit material.

---

## Engineering and content ownership

- **KeyPath team authors and maintains** all Starter Kit packs. No external contributors in v1.
- **Versioned with the app binary.** Updates to Starter Kit packs ship with app updates, not independently.
- **Manifests must be fully populated.** Each pack needs a name, description, affected keys, quick-settings schema, and a clear uninstall behavior. Pack manifest format is an open engineering question (§12 in Draft 1 spec); these twelve packs should be the proving ground for whatever format is chosen.

---

## Open items

1. **Per-pack copy.** Each pack needs a one-sentence description, a card-sized (80-character) description, and a Pack Detail page description (longer, editorial). I'll draft these alongside the editorial-voice one-pager.
2. **Quick-settings schemas per pack.** Each pack's quick settings need to be spec'd — specifically which settings are inline (Pack Detail quick settings) vs routed to Customize. I'll propose per-pack specs in a follow-up during Sprint 2.
3. **Illustrations per pack.** Each pack needs a card illustration (Gallery) and — depending on Pack Detail direction — possibly a hero diagram. Visual designer owns; I'll sequence after the Pack Detail direction is locked.

---

**Open question for review:** Does this list feel right? Too many? Too few? Missing something obvious? The list is easier to prune than to expand once users form expectations, so if there's doubt about any pack, we should remove it now.
