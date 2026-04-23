# Layers × Packs

**Sprint:** 2
**Status:** Draft
**Builds on:** [`override-precedence.md`](override-precedence.md), [`pack-coherence.md`](pack-coherence.md)

---

## The problem

Layers are a first-class KeyPath concept: the same physical key can do different things depending on which layer is active. Packs can contribute bindings to layers — including layers that didn't exist before the pack was installed.

That's the interaction we need to design. Three questions:

1. How are pack-contributed layers created, named, and made visible to the user?
2. What happens to a pack-contributed layer when the pack is uninstalled or updated?
3. What does the inspector show for a key whose binding exists only on a non-base layer?

Draft 1 hand-waved all three. This doc specifies them.

---

## Layer taxonomy — three kinds

Before designing interactions, a clearer mental model of what a "layer" is.

| Kind | Origin | Who can modify | Uninstall behavior |
|---|---|---|---|
| **Base** | Always exists | User can add bindings anywhere | Cannot be removed |
| **User-defined** | User created via layer menu | User edits freely | User deletes explicitly |
| **Pack-defined** | Introduced by installing a pack | User can add bindings, but layer itself is owned by the pack | Removed when pack is uninstalled (with user-binding preservation — see below) |

Each kind has different ownership semantics. A user's edits to a user-defined layer are theirs forever. A user's additions to a pack-defined layer are theirs, but the layer itself goes away if the pack is uninstalled — with a preservation path.

---

## How pack-defined layers work

### Layer identity is a manifest-declared ID, not a user-visible name

A pack's manifest declares: *"This pack adds layer `vim-nav`."* The ID `vim-nav` is how the system references the layer internally.

The user sees a display name that's separately specified — *"Vim Navigation"*. The display name can be renamed by the user without breaking pack coherence, because the system tracks the ID. (This is a flexibility we need to preserve — users who customize their workflow shouldn't have their pack status break because they renamed a layer.)

### Layer namespace collisions

If two packs both declare a layer `nav`, we have a problem.

**Solution: layer IDs are namespaced by pack.** Internally, Pack A's `nav` is `packA.nav`; Pack B's `nav` is `packB.nav`. They're different layers. Both can coexist. The user sees both in the layer menu, disambiguated by display name:

```
  Layer menu:
  ├── Base
  ├── ────────
  ├── Vim Navigation        ← packA.nav
  ├── Nav (from My Pack)    ← packB.nav
  └── ────────
  └── + New layer
```

If one pack's layer already has a more specific name than `Nav`, the disambiguation is only applied when there's an actual conflict. Packs should name their layers distinctively from day one; the namespace collision handling is a safety net.

### User layers vs. pack layers in the menu

The layer menu organizes layers by kind for clarity:

```
  Layer menu:
  ├── Base                         ← always first, always present
  ├── ────────  Your layers  ────────
  ├── Navigation                   ← user-defined
  ├── Symbols                      ← user-defined
  ├── ──────  From packs  ──────────
  ├── Vim Navigation               ← pack-defined (Vim Nav pack)
  ├── Writer's Layer               ← pack-defined (Writer's Toolkit pack)
  ├── ──────────────────────────────
  └── + New layer                  ← creates user-defined
```

Group headers appear only when each group is non-empty. For a user with only base + one user layer, the pack section doesn't show.

### Creating bindings on a pack-defined layer (user intent)

The user can add their own bindings to a pack-defined layer. Example: they're using the Vim Navigation pack, and want to add `w` → word-jump-forward because the pack didn't include it.

Behavior:
- User switches to the pack's layer.
- Clicks `w`, records output, saves.
- A direct binding is created on (`w`, `vim-nav` layer). It's a direct binding, owned by the user, on a pack-contributed layer.
- The pack is now *Modified* (specifically: has direct bindings added to its layer). Coherence reporting reflects this.

This is fine and expected. The pack's layer is the canvas; the user's additions are their own.

### What if the pack is uninstalled?

The pack-defined layer goes away — **but** the user's direct bindings on that layer are preserved in an "Orphaned bindings" surface with a prompt for what to do with them.

Flow:

1. User uninstalls Pack (Vim Navigation).
2. Before actually removing, the system checks: does the user have direct bindings on the pack's layer?
3. If yes:

```
  Uninstall Vim Navigation?

  You have 3 direct bindings on this pack's "Vim Navigation" layer:
    · w → Cmd+Right
    · b → Cmd+Left
    · e → Shift+Cmd+Right

  What should happen to these?

    ○ Move them to a new user layer called "Vim Navigation (my edits)"
    ● Discard them along with the pack
    ○ Cancel uninstall
```

Default is "Move to new user layer" because it's the least destructive. The user can pick "Discard" if they want a clean removal.

4. On confirm, the pack-defined layer is removed, pack's bindings are deleted from the precedence stack, user's direct bindings either move to a new user layer or are discarded.

5. Toast: *"Vim Navigation uninstalled. Your 3 custom bindings moved to layer 'Vim Navigation (my edits)'."*

This is the most complex uninstall path. It's worth the complexity because losing a user's direct bindings is a real cost.

### Pack updates and layers

If a pack's update modifies the layer structure (adds a layer, removes one, renames one), update behavior:

- **Added layer**: new layer appears after update. Existing user data on other layers unaffected.
- **Removed layer**: ask the user (same UX as uninstall for that specific layer). If the layer had user bindings, offer to preserve them as a new user layer.
- **Renamed layer**: display name updates; layer ID is unchanged; user's bindings on it are unaffected.

---

## What the keyboard canvas shows for non-base layers

The main window keyboard canvas always shows one layer at a time. The layer selector (in the toolbar) picks which.

### Layer selector visual

The layer selector is a dropdown in the toolbar. When a non-base layer is selected, the canvas makes it obvious — not just a dropdown label, but an ambient visual treatment:

- **Base layer selected**: canvas has its normal color treatment.
- **Non-base layer selected**: canvas acquires a subtle tinted background (e.g., soft accent-color wash at 6% opacity). A sticky "Layer: Vim Navigation" chip appears in the top-left of the keyboard canvas area, with a ✕ affordance to return to base.

This ensures the user always knows "what layer am I looking at?" — which is critical because the same key has different bindings on different layers.

### Bindings shown on the canvas

The canvas shows only bindings on the current layer. If the current layer is `vim-nav`:
- Keys with bindings on `vim-nav` show their mapped state (tint + inspector-ready).
- Keys without bindings on `vim-nav` show as unbound, even if they're bound on `base`. (This is correct: on this layer, they *are* unbound.)
- Exception: keys that are **layer triggers** — i.e., keys whose binding is "activate layer X" — are shown specially. See below.

### Layer triggers

A layer trigger is a key that activates a layer when held (or tapped, depending on binding). On the base layer, caps might be bound to `(tap: esc, hold: layer-vim-nav)`.

When viewing the base layer canvas, caps shows as a bound key with a specific indicator — a small layer-arrow glyph (→) in its keycap corner, or a tinted ring — to denote "this key goes to a layer."

When viewing the vim-nav layer canvas, caps itself is still present as the trigger (you can see what brings you there), and its display shows: *"(this is how you got here)"*.

### Navigating between layers

Three ways:

1. **Layer dropdown in toolbar** — explicit pick.
2. **Click a layer trigger key** on the canvas → dropdown appears asking "preview this layer?" — clicking yes switches the canvas to that layer. This is a preview; the user's actual keyboard behavior isn't changed.
3. **Keyboard shortcut** (future) — ⌥⌘1 / ⌥⌘2 etc. Deferred past v1.

---

## Inspector behavior for layer-scoped keys

The inspector's behavior for a key depends on whether the user is viewing base or a non-base layer, and whether the key has a binding on the current layer.

### Case 1 — viewing base, key is layer trigger

Example: user is on base, selects `caps`, which is bound `(tap: esc, hold: layer-vim-nav)`.

```
Caps Lock
─────────
Tap:   esc
Hold:  → Activate Vim Navigation layer

Part of: Vim Navigation pack  →

[ Edit mapping ]  [ Show Vim Navigation layer → ]
```

The "Show Vim Navigation layer" button switches the canvas to that layer.

### Case 2 — viewing non-base layer, key has binding on this layer

Example: user is on Vim Navigation layer, selects `j`, which is bound `(tap: j, hold: nothing)` on this layer — but the pack assigns `(tap: Down-Arrow)` on this layer.

Wait — simpler: the pack binds `j → Down-Arrow` on `vim-nav`. So on vim-nav:

```
J (on layer: Vim Navigation)
──────────────────────────
Output: Down Arrow

Part of: Vim Navigation pack  →

[ Edit mapping ]  [ Back to base layer ← ]
```

### Case 3 — viewing non-base layer, key has no binding on this layer

Example: user is on Vim Navigation layer, selects `q`, which has no binding on this layer but IS bound on base.

```
Q (on layer: Vim Navigation)
──────────────────────────
No mapping on this layer.

On base layer: (nothing — normal 'q' key)

Record output for this layer:
[ Record output ]  [ Type... ]

[ Back to base layer ← ]
```

This is important: the user needs to understand that "no binding on this layer" is *different* from "no binding globally." The inspector is explicit.

### Case 4 — viewing non-base layer, key is layer trigger back to base

Some packs define bidirectional layer triggers: `caps` on base triggers vim-nav; `caps` on vim-nav triggers base (goes "back"). This is a pattern.

```
Caps Lock (on layer: Vim Navigation)
─────────────────────────────────
Hold: ← Activate Base layer

Part of: Vim Navigation pack  →

[ Edit mapping ]
```

### Case 5 — viewing base, key is part of a pack-defined layer but not a trigger

Example: `j` is bound on `vim-nav` (pack), but on base it's just a normal j. User selects `j` while on base.

```
J
──
No mapping on this layer.

Bound on: Vim Navigation layer (press Caps to switch there)

[ Record output for base ]  [ Show Vim Navigation → ]
```

The inspector acknowledges that this key *is* bound somewhere — just not on the current layer. One click to see it in context.

---

## Creating new layers (user-defined)

### Flow

From the layer dropdown: `+ New layer`. A dialog:

```
  New layer

  Name:     [ ____________________ ]
  Trigger:  [ Choose a key… ]  ← optional

  [ Cancel ]  [ Create ]
```

If trigger is specified, a binding is auto-created: `(hold: activate-this-layer)` on the chosen key. If trigger is left empty, the layer exists but has no way to reach it — which is fine; the user might activate it only from the layer dropdown, or add a trigger later.

### Renaming a user layer

Inline-editable label in the layer dropdown (click to focus, type, enter). Doesn't affect bindings.

### Deleting a user layer

From the layer dropdown, right-click on the layer: `Delete "Symbols"…`. Confirmation: *"Delete layer 'Symbols' and its N bindings? This cannot be undone."* If the layer has a trigger binding, that binding is also removed.

### Deleting a pack-defined layer

Not allowed from the layer menu. The user has to uninstall the pack to remove its layer.

---

## What the inspector shows for a pack-defined layer trigger

When the user selects a key that triggers a pack-defined layer, the inspector surfaces the pack's identity on the layer too:

```
Caps Lock
─────────
Tap:   esc
Hold:  → Activate "Vim Navigation" layer
           (from Vim Navigation pack)

Part of: Vim Navigation pack  →

[ Edit mapping ]
```

This closes the loop: the user can see "this key activates a layer, and the layer comes from a pack."

---

## Edge cases

### Pack layer with no bindings in it

A pack can (in principle) introduce a layer without any bindings on that layer, expecting the user to populate it. This is unusual but valid. The layer shows up, the canvas is empty on it, the user fills it in.

Coherence: pack is Healthy — it introduced what it said it would. User's bindings on the layer are direct bindings.

### Pack layer with bindings on multiple layers

A single pack can contribute bindings to base AND to a new layer. Example: Home-Row Mods + Vim Navigation combined into one pack (hypothetical):
- On base: contributes home-row mod bindings on a/s/d/f/j/k/l/;
- Introduces `vim-nav` layer and contributes h/j/k/l → arrows

Handled normally. The pack's contributions are tracked per (key, layer). Coherence is computed over all contributions.

### User tries to delete a pack-defined layer's trigger

Example: Vim Nav pack binds `caps` on base as the layer trigger. User remaps `caps → esc` directly.

Consequence: no direct way to activate the pack's layer now (except from the dropdown). The pack's layer still exists and its bindings still work *if the layer is activated*, but there's no trigger.

Coherence: pack is Modified (its trigger binding is overridden). For an all-or-nothing pack or a core-must-be-intact pack with the trigger declared as core, this is a *pattern may not work* state. User is warned inline at override time.

Restoration: removing the direct binding on `caps` restores the pack's trigger.

### Layer trigger from a key that's part of another pack

Example: Pack A binds `caps` on base as a Hyper-key binding. Pack B (installed later) also wants to use `caps` as its layer trigger.

Normal precedence: Pack B wins (most recently installed). Pack A's `caps` binding is shadowed. The user might be surprised — they installed "Caps Lock as Hyper" and then "Vim Nav" and Hyper stopped working.

Messaging at install: *"Vim Navigation uses Caps Lock, which is also used by Caps Lock as Hyper. Caps Lock will now activate Vim Navigation instead. Reinstalling Caps Lock as Hyper will swap them back."*

This is the most substantive precedence-related messaging we do during install. It's correct because it's where the user is most likely to be confused.

---

## Open questions

1. **Visual distinction for the non-base canvas tint.** Should each layer have its own distinct tint, or all non-base layers share one tint color? My recommendation: one tint (accent @ 6%) to avoid noise, but allow pack-defined layers to declare an *optional* color override in their manifest (so Vim Nav could be slightly green-tinted if the pack author wants). Default is the shared tint; customization is optional.

2. **Preview-only layer switching on the canvas.** Currently proposed: clicking a layer trigger on the canvas asks "preview this layer?" — explicit confirm. Alternative: immediate switch, with a clear "Viewing: Vim Navigation (preview) — [back to base]" banner. Less click, same clarity? Needs quick usability check once we're in SwiftUI.

3. **Display name collisions.** If user has a user-defined layer "Navigation" and installs Vim Nav (which has display name "Vim Navigation"), that's fine. But if they install a pack whose display name *exactly* matches an existing user layer, what happens? Proposal: the pack's display name is suffixed — "Navigation (from Vim Nav pack)" — to disambiguate. User can rename.

4. **Can user-defined and pack-defined layers have overlapping bindings?** Example: user's "Nav" layer binds `j → Down`; pack's "Vim Nav" layer also binds `j → Down`. They're on different layers, so no precedence collision. But are we okay with the redundancy? Yes — they're just two layers that happen to have similar bindings. User may deactivate one by choosing not to trigger its activation.

---

## Decision asked of exec

Two claims to lock:

1. **Pack-defined layers are owned by the pack; user-defined layers are owned by the user.** Uninstalling a pack removes its layer (with preservation prompt for user bindings on it). *Accept?*

2. **Layer identity is a manifest-declared ID, with user-facing display name separately tracked.** Renaming a layer doesn't break pack coherence. *Accept?*

These two, plus the four from override-precedence, are the foundational claims Sprint 2 rests on.

---

## Related

- [`override-precedence.md`](override-precedence.md) — precedence stack is per (key, layer)
- [`pack-coherence.md`](pack-coherence.md) — coherence policies for layer-contributing packs
- [`inspector-edge-states.md`](inspector-edge-states.md) — inspector behavior for all layer × key combinations
