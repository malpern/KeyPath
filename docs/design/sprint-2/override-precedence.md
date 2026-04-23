# Override Precedence Model

**Sprint:** 2 · Foundational document
**Status:** For exec decision — high-leverage, affects data layer
**Decision needed:** Lock the precedence model before anything else in Sprint 2 depends on it

---

## Why this matters enough to be the first Sprint 2 doc

"Everything is a binding" is the product's central claim, and the moment we introduce packs, we need to answer: *when two things want to set the same key, who wins?* That answer determines how the data layer is shaped, how the inspector shows provenance, how uninstall works, and how update works. Get this wrong and every bug for the next year will be some variant of "why did my mapping change?"

Draft 1 said "most recent install wins" in passing. That's half a model. This doc is the whole one.

---

## The shape of the problem

A user's keyboard at any moment has an **effective binding** per key per layer. That binding is computed from a stack of *contributions*. Contributions come from three sources:

1. **Direct bindings** — user-authored, via the inspector.
2. **Pack bindings** — installed as part of a pack.
3. **Hardware default** — whatever the key natively produces when nothing claims it.

Multiple packs can claim the same key. A user can override a pack-contributed key with a direct binding. Packs can be installed, uninstalled, updated, reinstalled. The model must handle every combination without surprise.

Layers add a dimension: each layer has its own precedence stack. Bindings in layer "base" are independent from bindings in layer "nav." A pack can contribute to one layer, multiple layers, or define a new layer.

---

## The model

### Precedence is ordered from highest to lowest

For any (key, layer) pair, the effective binding is determined by the highest-precedence contribution:

```
1 (highest) — Direct binding (user-authored via inspector)
2            — Pack binding, most recently installed
3            — Pack binding, second-most-recently installed
...
N (lowest)  — Hardware default (no binding)
```

The user's explicit action (direct binding) always beats any pack. Among packs, most-recently-installed wins. Hardware default is the floor.

### Shadowing is explicit and visible

When two sources want to set the same (key, layer), the losing source is **shadowed**, not deleted. Its contribution is preserved but inactive. The system remembers what every source wants so that removing one reveals the next one down.

Example sequence:

| Step | Action | Effective binding on `caps` |
|---|---|---|
| 1 | Install Pack A: `caps → esc` | `esc` (from Pack A) |
| 2 | Install Pack B: `caps → hyper` | `hyper` (from Pack B; Pack A shadowed) |
| 3 | User directly remaps: `caps → tab` | `tab` (direct; Pack B and Pack A both shadowed) |
| 4 | Uninstall Pack B | `tab` (direct still wins; Pack A still shadowed) |
| 5 | Remove direct binding via inspector | `esc` (Pack A unshadowed — its binding returns) |
| 6 | Uninstall Pack A | (unbound — hardware default) |

This is the model in full. Every operation is reversible; nothing is lost until the contributing source is uninstalled.

### A direct binding is "taking ownership"

When the user directly remaps a key that was pack-contributed, they have **taken ownership** of that key. The action is: create a direct binding, which now shadows all pack bindings for this (key, layer). From the user's perspective: they just said what the key should do, and that's what it does.

Conceptually, a direct binding isn't a *modification* to a pack binding — it's a *separate, higher-precedence* binding. The pack binding is still there, shadowed, waiting. This matters for:

- **Pack updates**: a pack update can't silently change a user-overridden key. The update applies to the pack binding; the direct binding still shadows.
- **Uninstall**: uninstalling a pack that the user has overridden on some keys doesn't delete the direct bindings — those were never part of the pack.
- **Restore pack defaults**: the user can "release ownership" per-key, removing the direct binding and letting the pack binding resurface.

### Pack order is install order (deterministic)

Packs are ordered by the timestamp they were installed. Most recent wins. This is deterministic, observable (install order is visible in My Packs), and intuitive (recency = most recent decision).

Alternatives considered:
- **User-defined pack priority** (drag to reorder): more flexible, more cognitive load, rarely needed. Rejected for v1. Can be added later as an advanced feature.
- **Alphabetical / manifest-declared priority**: harder to explain, invisible to the user. Rejected.

Install-order precedence means that **reinstalling a pack promotes it to the top**. This is the right mental model: if you want Pack A's version of `caps` to win over Pack B, reinstall Pack A.

### Layers are a dimension, not a precedence level

Each (key, layer) pair has its own precedence stack, independent of other layers. A pack binding on `caps` in layer "base" doesn't interact with a pack binding on `caps` in layer "nav."

This means: a pack that contributes to multiple layers contributes to multiple stacks. Precedence is evaluated per-layer.

---

## Complete state diagram (for one (key, layer) pair)

```
                 ┌──────────────┐
                 │   unbound    │
                 │  (no source) │
                 └───┬──────┬───┘
            install │      │ user remaps
              pack  │      │ (direct)
                    ▼      ▼
        ┌─────────────┐   ┌─────────────┐
        │ single-pack │   │   direct    │
        │   binding   │   │   binding   │
        └──┬────┬─────┘   └──┬─────┬────┘
           │    │            │     │
install B  │    │ uninstall  │     │ remove direct
           ▼    ▼            │     ▼
    ┌─────────────┐          │  [returns to:
    │  multi-pack │          │   unbound OR
    │   (Pack B   │          │   whichever pack
    │   shadows A)│          │   binding exists]
    └──┬────┬─────┘          │
       │    │                │
 user  │    │ uninstall      │
direct │    │ top pack       │
remap  │    │                │
       ▼    ▼                ▼
    ┌─────────────┐    ┌──────────────┐
    │  direct +   │    │   single     │
    │  shadowed   │    │   pack       │
    │  pack(s)    │    │              │
    └─────┬───────┘    └──────────────┘
          │
remove    │
direct    ▼
     [reveals top
      shadowed pack]
```

Every transition is reversible. The model never loses information — it only changes which source is currently winning.

---

## Consequences and edge cases

### Uninstalling a pack the user has overridden

Scenario: Pack A installed, contributes `caps → esc`. User remaps `caps → tab` directly. Now user uninstalls Pack A.

Behavior: the direct binding on `caps → tab` **stays**. It was never part of Pack A. Pack A's shadowed binding is gone because Pack A is gone.

Messaging: none. This is the expected behavior — the user's explicit action persists through pack lifecycle changes.

### Uninstalling a pack the user has partially overridden

Scenario: Pack A contributes bindings to 8 keys. User overrides 1 of them. User uninstalls Pack A.

Behavior: the 7 un-overridden pack bindings disappear. The 1 direct binding stays.

Messaging: toast — *"Pack A uninstalled. 1 direct mapping you had made from this pack's keys has been kept."* This is the one case where we say something, because the user may expect their custom mapping to be removed too. We're clarifying what was preserved.

### Uninstalling a shadowed pack

Scenario: Pack A installed (`caps → esc`), then Pack B installed (`caps → hyper`, shadows A on this key). User uninstalls Pack A.

Behavior: Pack B is still the effective binding on `caps`. Pack A's shadowed contribution is simply gone. No change to effective bindings on any key (since A was already shadowed everywhere it overlapped with B).

Messaging: toast — *"Pack A uninstalled. No effective changes to your keyboard."* (Shown only if Pack A was fully shadowed everywhere.)

### Reinstalling a pack

Scenario: User uninstalls Pack A, then later reinstalls it.

Behavior: Pack A is inserted at the top of the precedence stack (most recent). This is correct and matches the "install-order wins" rule.

Consequence: reinstalling a pack can surface bindings that were previously shadowed by another pack. User sees what changed via the install toast.

### Pack update

Scenario: Pack A v1 installed. User overrides one key. Pack A v2 published with a modified binding on a different key.

Behavior:
- Pack A v2's bindings replace Pack A v1's bindings in the precedence stack. Install timestamp updates to the update date (so reinstalling via update = newest).
- The user's direct override remains; the pack's new binding on the overridden key is **still shadowed**.
- Other pack keys update to whatever v2 says.

Messaging: diff preview before update — *"2 bindings will be added, 1 will change, 0 will be removed. 1 of your direct overrides is unaffected."*

### Multiple packs, same key, same layer

Already covered in the model. Most recent install wins; others are shadowed; uninstalling the winner reveals the next-most-recent.

### Pack with dependencies / conditional bindings

Some packs have bindings that are conditionally active (e.g., "only when on MacBook Pro internal keyboard"). This is handled via scope, not precedence. A scoped binding participates in the precedence stack normally, but only applies when the scope condition is met. Outside the scope, the next binding in the stack (for that scope context) wins.

---

## What the user sees

Precedence is an internal model. The user rarely needs to think about it. But certain moments **do** need to surface it:

### Inspector — effective binding + source

For any selected key, the inspector always shows:
- The effective binding (tap output, hold output, etc.)
- The source: "Direct" | "Pack: Home-Row Mods"

That's the primary view. 99% of users will never want more.

### Inspector — "see all sources" (power user, hidden behind disclosure)

For keys with multiple shadowed contributions, a disclosure arrow in the inspector reveals:

```
Current: esc (Direct)
────────────────────
Also provided by:
  · Pack: Caps Lock Remap   (shadowed)
  · Pack: Caps Lock as Hyper (shadowed)

[Remove direct binding →]  would revert to: esc (Caps Lock Remap)
```

This is the "what if I removed this?" affordance. Users who wonder why a binding came back after uninstalling something can trace it here.

### Pack Detail — per-binding status

On Pack Detail, each binding row shows its current status:

```
Key   Binding       Status
a     tap:a hold:⌃  ✓ Active
s     tap:s hold:⌥  ✓ Active
d     tap:d hold:⇧  ⚠ Overridden by you → tap:d hold:(nothing)
f     tap:f hold:⌘  ◆ Shadowed by Vim Nav pack
```

Icons:
- ✓ = this pack is providing the effective binding
- ⚠ = user has a direct override (you can see what they chose instead)
- ◆ = another pack is providing the effective binding

### My Packs — summary line

Each installed pack in My Packs shows a one-line status:

- **Clean:** *"8 bindings · active"*
- **Modified:** *"8 bindings · 1 modified by you"*
- **Shadowed:** *"8 bindings · 3 shadowed by other packs"*
- **Both:** *"8 bindings · 1 modified · 2 shadowed"*

### What we don't show

- **No pack priority UI in v1.** Users don't reorder packs. Install order handles it.
- **No "precedence" term in copy.** Users will not encounter the word. They see "active," "overridden," "shadowed" — concrete verbs.
- **No precedence visualization on the keyboard canvas.** The keyboard shows the effective binding only. Per-key provenance lives in the inspector.

---

## Data layer implications

Engineering concerns (handoff-only):

1. **Every binding must store its source with timestamp.** `BindingSource = .direct | .pack(packID, installedAt)`. Enough to reconstruct the precedence stack on the fly or cache it.
2. **Bindings are never mutated by pack lifecycle.** Install a pack → add its bindings. Uninstall → remove those bindings. Update → swap version+bindings atomically. User's direct bindings are untouched by any pack operation.
3. **The effective binding is computed, not stored.** Engineering can cache for perf, but the source of truth is the contribution stack.
4. **"Shadowed" is not a property of a binding — it's a result of the computation.** A binding is only shadowed if another binding with higher precedence exists on the same (key, layer).
5. **Uninstall flow:**
   - Find all bindings where `source = .pack(thisPackID)`.
   - Delete them.
   - Recompute effective bindings for affected (key, layer) pairs.
   - Show "X effective changes" in the uninstall confirmation.
6. **Reinstall must create a new install-timestamp.** Even if the pack version is identical, the new install goes to the top.

---

## Open questions

1. **Do we need per-layer precedence visibility?** Current proposal: the inspector's "see all sources" disclosure always operates on the current layer's stack. If the user is on layer "base," they see base's precedence. If they switch to layer "nav," they see nav's. A user wondering "what would this key do on layer X" has to switch to X to find out. Acceptable for v1, worth noting as a follow-up question.

2. **Restore pack defaults — whole pack or per-key?** My recommendation: offer both.
   - Per-key from inspector: *"[Release ownership to restore Pack X's binding]"* when viewing an overridden key.
   - Whole pack from Pack Detail: *"[Restore all defaults]"* when the pack is modified.
   - These are symmetric operations with the same underlying mechanic (remove direct bindings for pack's keys).

3. **Multi-pack with competing layers.** Pack A introduces a layer `nav`. Pack B also introduces a layer `nav`. What happens? My recommendation: layer creation is namespaced by pack. Pack A's `nav` and Pack B's `nav` are *different layers*, displayed to the user as *"nav (from Pack A)"* and *"nav (from Pack B)"*. User can keep both, use both, uninstall one without affecting the other. Engineering to confirm this is feasible in the underlying kanata model.

4. **Scoped pack bindings.** A device-scoped pack binding still participates in the precedence stack, but only applies in its scope. If two packs have device-scoped bindings on the same (key, layer) for the same device, normal precedence rules apply. If one is device-scoped and one is global, they don't compete — the device-scoped wins when in-scope, the global wins elsewhere. This is the expected behavior; documenting it explicitly.

---

## Decision asked of exec

Lock these four claims before any Sprint 2 work downstream proceeds:

1. **Precedence order:** Direct > most-recent-pack > older-packs > hardware default. *Accept / modify?*
2. **Shadowing is preserved, not deleted.** Uninstall reveals shadowed bindings. *Accept?*
3. **Install order is the pack precedence mechanism.** No user-defined pack priority in v1. *Accept?*
4. **Direct bindings persist through pack lifecycle.** Uninstalling a pack does not remove user overrides on its keys. *Accept?*

Once locked, pack-coherence, layer-pack interaction, and inspector edge states all build on top of these rules. Changes to precedence after Sprint 2 get expensive fast.

---

## Related

- [`pack-coherence.md`](pack-coherence.md) — how a pack reports its health when partially shadowed or overridden
- [`layers-and-packs.md`](layers-and-packs.md) — how layers interact with pack lifecycle
- [`inspector-edge-states.md`](inspector-edge-states.md) — full inspector state matrix
