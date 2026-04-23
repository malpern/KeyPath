# Pack Coherence

**Sprint:** 2
**Status:** Draft — depends on override-precedence model
**Builds on:** [`override-precedence.md`](override-precedence.md)

---

## The problem

A pack is a coherent pattern — home-row mods are eight bindings that work together. When a user overrides one key (direct binding takes ownership) or when another pack shadows one of the pack's keys, the pattern may silently break in ways that don't surface until the user tries to *use* the pattern and it doesn't work.

The user's fallback diagnostic in that moment is: *"did something I installed break something I was using?"* — which is a terrible place for a user to be. The app owes them better than that.

Pack coherence is the system's answer. Every installed pack reports its own health; the UI surfaces that health in exactly the places the user is looking when the question matters.

---

## Coherence states — five possibilities

Every installed pack is always in exactly one of these states:

| State | Meaning | Visual glyph |
|---|---|---|
| **Healthy** | All pack bindings active, version matches installed version | ✓ green check |
| **Modified** | Some bindings have user direct-binding overrides. Pattern may or may not still work. | ⚠ yellow diamond |
| **Shadowed** | Some bindings shadowed by another, more-recently-installed pack. | ◆ orange outline |
| **Outdated** | Pack author has published a newer version; installed version is older. | ⟳ blue |
| **Broken** | Pack can't resolve — manifest error, missing dependency, invalid binding | ✕ red |

States are **not mutually exclusive** except for Broken. A pack can be Modified + Shadowed + Outdated simultaneously. The displayed glyph in those cases follows a priority ladder (Broken > Outdated > Modified > Shadowed > Healthy), but the full state is visible on drill-down.

### Healthy

The default. All bindings the pack contributes are the effective bindings for their (key, layer). No direct overrides, no shadowing. Pack version matches installed version.

### Modified

One or more of the pack's bindings has been overridden by a user direct binding. The pack's binding is still installed — just shadowed by the user's explicit action.

### Shadowed

Another pack, installed later, contributed a binding on the same (key, layer) and is currently the effective binding. The earlier pack's binding is still installed — just shadowed by install-order precedence.

### Outdated

The local Starter Kit or update mechanism indicates a newer version is available. Until updated, the pack runs at its installed version.

### Broken

Something about the pack can't resolve:
- Manifest file missing or malformed.
- Binding references a key/layer/scope the system doesn't recognize.
- Pack declared a dependency on another pack or feature that isn't present.
- VHID driver version incompatible with pack requirements (edge case).

Broken packs are not active — their bindings don't contribute to the precedence stack. They're listed in My Packs so the user can see the problem and either update, reinstall, or uninstall.

---

## Per-pack coherence declaration

Each pack's manifest declares **what coherence means for this particular pack**. This is important because different packs have different tolerances for partial application.

### Coherence policies

A pack declares one of three policies in its manifest:

1. **`all-or-nothing`**: the pack only works if all its bindings are the effective binding. Any modification or shadowing is flagged as a *pattern broken* warning. *Example: Home-Row Mods — removing one finger's mod breaks the finger-independence assumption; users should know.*

2. **`core-must-be-intact`**: the pack declares a subset of its bindings as "core." Modifications to core bindings are flagged; modifications to non-core bindings are fine. *Example: Vim Navigation Layer — hjkl are core (disabling any of them breaks the navigation pattern); additional helpers like `w` for word-jump are optional.*

3. **`per-key-independent`**: each binding is useful on its own; modifications don't affect the rest. *Example: Smart Quotes & Dashes — curly-quote substitution and em-dash substitution are independent; disabling one doesn't affect the other.*

The policy is declared in the manifest. UI behavior is consistent regardless — the policy just determines the *threshold* at which the pack's state flips from Modified (low-concern) to Modified (pattern-broken warning).

### Visual treatment based on policy

- **per-key-independent** pack with one override: "1 modified" — no warning tone.
- **core-must-be-intact** pack with a core override: "⚠ core binding modified — pattern may not work as intended."
- **all-or-nothing** pack with any override: "⚠ modified — pattern may not work as intended."

---

## Where coherence shows up

### 1. Inspector (key-level)

When a user selects a key that's part of a pack, the inspector shows the pack's coherence status on that specific key (not the whole pack):

**Healthy pack, healthy key:**
```
Part of: Home-Row Mods →
```

**Modified pack, key IS the overridden one:**
```
Overrides Home-Row Mods on this key  →
(the pack's default was: tap:a hold:⌃)
```

**Shadowed pack, key IS the shadowed one:**
```
Also provided by Home-Row Mods (shadowed)  →
(Vim Nav wins on this key because it was installed more recently)
```

### 2. Pack Detail (pack-level)

On Pack Detail, the header shows the pack's overall coherence state. Specifics are in a status line:

**Healthy:**
```
Home-Row Mods · ✓ Active
All 8 bindings working as designed.
```

**Modified, all-or-nothing pack:**
```
Home-Row Mods · ⚠ Pattern may not work
1 of 8 bindings is overridden by your direct mapping.
This pack assumes all 8 keys work together — see details below.
[ Restore all defaults ]  [ Edit my override ]
```

**Shadowed:**
```
Home-Row Mods · ◆ Partially shadowed
3 of 8 bindings are shadowed by Vim Navigation Layer (installed more recently).
[ Review shadowed keys ]
```

**Outdated:**
```
Home-Row Mods · v2.1.0 installed · ⟳ v2.1.1 available
[ Update ]
```

**Broken:**
```
Home-Row Mods · ✕ Can't load
The pack's manifest references a layer "custom" which doesn't exist.
[ Reinstall ]  [ Uninstall ]
```

### 3. My Packs (list-level)

The My Packs list shows a coherence glyph next to each installed pack name and a short status string:

```
✓ Home-Row Mods        v2.1.0 · active
⚠ Caps Lock as Hyper   v1.0.2 · modified · pattern ok
◆ Vim Nav Light        v1.0.0 · 2 keys shadowed
⟳ Smart Quotes         v3.0.0 → v3.0.1 available
✕ Broken Pack          can't load — reinstall
```

### 4. Keyboard canvas (not shown)

The keyboard itself does not carry coherence indicators. We decided in Sprint 1 that the keyboard shows *effective state*, not provenance. Coherence is metadata; it belongs in the inspector and the Pack Detail view.

---

## Non-blocking warnings, not modals

Coherence concerns never produce modals. They're always inline information the user can act on or ignore.

### When the user overrides a pack-contributed key

The existing post-override inline warning (specified in Draft 1) is augmented with coherence context:

**Per-key-independent pack:** *"Overrode Home-Row Mods on this key. [Undo]"* (unchanged)

**Core-must-be-intact pack, non-core key:** *"Overrode Home-Row Mods on this key. [Undo]"* (treated same as per-key-independent for this key)

**Core-must-be-intact pack, core key:** *"Overrode Home-Row Mods on this key. This key is core to the pack's pattern — the home-row mod pattern may not work as intended. [Undo]"*

**All-or-nothing pack:** *"Overrode Home-Row Mods on this key. The pack assumes all 8 keys work together; overriding may break the pattern. [Undo]"*

The warning is non-blocking. The save already completed. The warning educates; the user chooses what to do.

---

## Restoring coherence

Two affordances for a user who wants to restore a pack to Healthy state:

### Per-key restore (inspector)

From the inspector of an overridden key:
```
[Release ownership → restore Home-Row Mods binding]
```

One click: the direct binding is removed; the pack's shadowed binding becomes effective again.

### Whole-pack restore (Pack Detail)

From the Pack Detail of a Modified pack:
```
[ Restore all defaults ]
```

This removes *all* direct bindings on keys that the pack contributes. Resulting state: pack is Healthy (no user overrides on any pack key).

Confirmation on click: *"Restore 3 direct mappings to Home-Row Mods defaults? Your custom mappings on these keys will be removed."* with Cancel / Restore buttons. This one *is* a confirmation — because it's destructive of user work in a way the per-key restore isn't. Still not a modal though; a light popover attached to the button.

---

## How pack authors get this right

For the Starter Kit (all authored by the KeyPath team), each pack manifest needs to declare its coherence policy explicitly. Proposed assignments:

| Pack | Policy | Rationale |
|---|---|---|
| Caps Lock → Escape | per-key-independent | One binding. Policy doesn't really apply but must be declared. |
| Caps Lock as Hyper | per-key-independent | One binding. |
| Caps Lock as Layer Toggle | core-must-be-intact (core: caps) | Caps is the layer trigger; the layer's internal bindings are helpers. Disabling the caps binding breaks the whole thing. |
| Home-Row Mods — Light | core-must-be-intact (core: f, j) | Index fingers are the most-used mods. Disabling other fingers still leaves a usable pack. |
| Home-Row Mods — Full CAGS | all-or-nothing | The CAGS layout assumes symmetry; losing one breaks the assumption. |
| Smart Quotes & Dashes | per-key-independent | Three independent substitutions. |
| One-Hand Symbol Layer | core-must-be-intact (core: `;`) | Layer trigger is core; symbol bindings inside are helpers. |
| Tmux-Style Escape | per-key-independent | Single binding. |
| Bracket Dance | all-or-nothing | The `[`/`]` pair must both function for the pattern to work. |
| Sticky Modifiers | per-key-independent | Each modifier's stickiness is independent. |
| WASD to Arrows | all-or-nothing | The 4 keys are one unit; missing one breaks WASD navigation. |
| Vim Navigation Layer | core-must-be-intact (core: h, j, k, l) | hjkl are core; additional nav helpers are optional. |

---

## Update flow and coherence

When an update is available for a pack:

1. User sees the ⟳ indicator.
2. Click [Update] → opens a diff preview:
   ```
   Home-Row Mods · v2.1.0 → v2.1.1

   What's changing:
   · Hold timeout default: 180ms → 200ms
   · New binding on ' (apostrophe): tap:' hold:⇧
   · 1 binding unchanged

   Your direct overrides (will not be affected):
   · d (your mapping: tap:d hold:(nothing))
   ```
3. User confirms. Update applies atomically. Coherence state updates.

Key rule: **an update can never silently change a user-overridden key**. If v2.1.1 changes the binding on `d` but the user has overridden `d`, the user's override stays. The pack's *shadowed* binding for `d` gets the new version, but it's still shadowed.

If the user later releases ownership of `d`, the new (v2.1.1) binding becomes effective — not the old one. This is correct.

---

## Edge cases

### Pack becomes broken after an OS update

The OS updates, something changes (a key identifier, a driver version), and a pack that was working becomes Broken. The user's direct bindings are unaffected; only the pack's contributions drop out of the precedence stack.

Messaging: one-time notification when the app detects the change on launch — *"Pack X couldn't load after your recent macOS update. Your other mappings still work."* with a [Review] action leading to Pack Detail.

### Pack that provides a binding on a key with no prior user interaction

Common case. User installs a pack, pack's binding becomes effective. No special messaging — this is just normal installation.

### Pack is fully shadowed by another pack

Scenario: Pack A (`caps → esc`), then Pack B (`caps → hyper`). Pack A's only binding is now shadowed. Pack A is in Shadowed state.

Is this confusing? Slightly, because the user installed Pack A and "nothing happened." We handle this in the install flow:

When installing Pack A would result in fully-shadowed bindings, the install toast gets a coherence note: *"Pack A installed. 1 binding is shadowed by Pack B (installed more recently). To make Pack A's binding active, reinstall Pack A or uninstall Pack B. [Learn more →]"*

This is the one place where precedence is surfaced proactively, because the user has a legitimate reason to wonder why installation didn't produce visible change.

### Pack with a conditional binding (scoped)

Scoped bindings (device-specific, app-specific) are always *potentially* active depending on context. A scoped pack is Healthy if all its scoped bindings are the effective binding when in-scope. Out-of-scope is not an incoherence.

---

## What we're not doing

- **No automatic conflict resolution.** The system never silently "fixes" a shadowed or modified state by promoting one pack over another or reverting user overrides. That's the user's decision.
- **No pack dependency graph in v1.** Packs don't declare dependencies on other packs. If they need to coexist with specific packs, that's out of scope for v1.
- **No transactional install.** Installing a pack is not a transaction across multiple packs. If installing Pack B shadows Pack A, we inform the user, but we don't offer an "install as a group" flow.
- **No "upgrade path" automation.** If Pack A v1 and Pack A v2 have different coherence policies, we don't auto-migrate the user's overrides.

---

## Open questions

1. **Does "modified but pattern-ok" (per-key-independent pack with overrides) deserve a visual glyph?** Currently: no — it stays visually Healthy. The *number* of overrides is surfaced ("1 modified") in text, but no warning glyph. Proposal: keep it this way. A warning glyph would be noise for per-key-independent packs where partial overrides are expected.

2. **Policy violations during update.** If a pack updates from `per-key-independent` → `all-or-nothing`, and the user has overrides, the coherence state may change from "Modified, pattern ok" to "Modified, pattern broken." Is this surprising? Probably not if framed well — it means the pack author changed how the pack wants to be used. Messaging: *"Home-Row Mods v2.2 treats its bindings as all-required. Your existing overrides now mark the pattern as possibly broken."* Not a blocker, but worth a heads-up in the update diff.

3. **Broken packs and the user's keyboard.** Broken packs have their bindings excluded from the precedence stack. This means keys that were bound by the broken pack become unbound (or revert to the next shadowed source). Is that okay? Yes — the keyboard should reflect what's currently working. A pack that can't load shouldn't be silently "kind of working."

4. **Coherence for packs with layer contributions.** A pack that introduces a layer is Healthy if the layer exists and all its bindings are effective within that layer. What if the user renames the layer? Currently proposed: rename doesn't break coherence — the layer identity is a manifest-declared ID, the name is user-visible label. Engineering to confirm this split is feasible.

---

## Related

- [`override-precedence.md`](override-precedence.md) — the underlying model that coherence reports on
- [`inspector-edge-states.md`](inspector-edge-states.md) — how coherence shows up in the inspector's various states
- [`layers-and-packs.md`](layers-and-packs.md) — coherence considerations for layer-introducing packs
