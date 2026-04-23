# Gallery Pack Migration Plan

The M1 Gallery ships 5 starter-kit packs. The RuleCollection catalog
contains ~15 more collections that are not surfaced as packs. This
document plans how to port them.

## Context

A "pack" is a discovery-layer abstraction on top of a `RuleCollection`.
It carries user-facing marketing copy (tagline, category, hero icon,
description) and an `associatedCollectionID` that points at the real
thing. Pack install toggles the collection on; Pack Detail embeds the
collection's picker so users can tune without opening the Rules tab.

So migration is mostly wrapping — manifest + pack-registry entry, plus
(sometimes) a Pack Detail editor. Each pack is a few hundred lines when
the pattern fits.

## Current pack surface

| Pack | Collection | Pack Detail editor |
|------|-----------|---------------------|
| Caps Lock Remap | `capsLockRemap` | TapHoldPickerContent |
| Home Row Mods | `homeRowMods` | HomeRowModsCollectionView |
| Escape Remap | `escapeRemap` | SingleKeyPickerContent |
| Delete Enhancement | `deleteRemap` | SingleKeyPickerContent |
| Backup Caps Lock | `backupCapsLock` | SingleKeyPickerContent |

## Catalog collections not yet packaged

Sorted into tiers by how well the current Pack Detail pattern fits.

### Tier 1 — No new UI needed

Existing pickers cover these; migration is mostly manifest + wire-through.

| Collection | Config type | Notes |
|------------|-------------|-------|
| Vim Navigation | singleKeyPicker / layer toggle | Activator → nav layer |
| Auto Shift Symbols | autoShiftSymbols | Already has its own embedded editor in Rules (`AutoShiftCollectionView`) — extract and reuse |
| Mission Control | table | Read-only mapping list is fine |

**Do these first.** They prove the pattern holds across more collections without requiring UI invention.

### Tier 2 — Needs a new embedded editor

The collection's Rules-tab editor exists but isn't generalized for Pack Detail yet. Pattern: extract the view, decouple from Rules-specific bindings (same refactor we did for TapHoldPickerContent), embed.

| Collection | Config type | New editor needed |
|------------|-------------|-------------------|
| Home Row Layer Toggles | homeRowLayerToggles | Similar to HRM editor — candidate for shared view |
| Numpad / Symbol / Fun layers | layerPresetPicker | Layer preset picker with key-map preview |
| Launcher (Quick Launcher) | launcherGrid | Per-key app/target grid |

### Tier 3 — Different shape of pack

Every existing pack is "remap some keys." These are structurally different and may need a different pack template (different marketing copy focus, maybe different install semantics).

| Collection | Why different |
|------------|---------------|
| Window Snapping | Needs Accessibility API permission; runtime dep on private CGS APIs. Install should check for AX access and surface an explanation. |
| Chord Groups | Config is a list of *user-defined* chords. Pack would be a scaffolding / starter kit rather than a one-click-on toggle. |
| Sequences / Leader Key | Same as Chord Groups — users author these. A pack makes sense only if we ship a preset set. |
| KindaVim / Neovim Terminal | App-scoped. Installation model is "only active when {app} is focused." Pack Detail should expose the app-scope knob. |

### Not shipping as packs

| Collection | Why |
|------------|-----|
| macOS Function Keys | System default — always on. Already listed in Rules; packaging it as a toggle would mislead. |

## Recommended execution order

**Phase B-1 (validate pattern at scale):** Port one pack from each Tier 1/2 slot before blitzing. This surfaces whether the "wrap a collection" pattern scales or needs structural investment.

1. **Vim Navigation** — simplest Tier-1 candidate; zero new UI.
2. **Home Row Layer Toggles** — Tier-2; tests whether an HRM-shaped editor generalizes.
3. **Window Snapping** — Tier-3; tests whether we need new pack primitives (AX permission check, conditional install) before committing.

If all three fit cleanly, port the rest in Tier 1 → Tier 2 order.

**Phase B-2 (breadth):** Remaining Tier-1 — Auto Shift Symbols, Mission Control.

**Phase B-3 (editor refactors):** Remaining Tier-2 — Numpad / Symbol / Fun layers, Launcher.

**Phase B-4 (harder calls):** Tier-3 — Chord Groups, Sequences, Leader Key, KindaVim, Neovim Terminal. Each needs a design discussion first (app-scope install, user-authored content).

## Per-pack migration checklist

For each pack ported:

- [ ] Add pack entry to `PackRegistry.swift` (`static let <name>`).
- [ ] Add to `PackRegistry.starterKit` array.
- [ ] If the collection has a canonical input key (e.g. `caps`), include it in the pack's `bindings` so `packsTargeting(kanataKey:)` surfaces it in the overlay Suggested banner.
- [ ] If a new editor is needed: extract from Rules view, add an `isEditable: Bool` flag, gate callbacks.
- [ ] Wire the editor into `PackDetailView.bindingsBlock` dispatch.
- [ ] If the pack exposes quick-settings (sliders), add them to the manifest.
- [ ] Add a runtime behavior test in `PackRuntimeBehaviorTests` for the headline claim.
- [ ] Add to `PackRegistryTests.testExpectedPacksShip`.
- [ ] Capture a screenshot for the pack card's hero icon decision (SF Symbols first; no custom art).

## Risks / known sharp edges

- **Collection conflicts.** Enabling two collections that both bind the same physical key today produces undefined behavior. The validation harness will catch outright parse errors, but semantic conflicts (same key, two different tap outputs) will silently pick one. Consider a `packConflicts(pack:)` helper before enabling Window Snapping alongside HRM (both may want letter keys).
- **UI complexity budget.** Pack Detail is currently a single sheet with ~700 lines. Porting Tier-2 / Tier-3 packs could push it past a reasonable ceiling. Before the second Tier-3 pack, extract the pack-editor dispatch into its own file or protocol.
- **App-scoped packs (KindaVim, Neovim Terminal)** currently have no install UI for picking which app to target. Punting on this until we have a design discussion.
- **Chord Groups / Sequences / Leader Key** ship as *empty* collections awaiting user authoring. A pack for them is really a pack of *example* chords/sequences. Decide whether the pack writes starter content or just enables the empty collection.

## Success criteria for this phase

- Every packaged collection has a runtime behavior test covering its headline claim.
- No pack regresses the overall `kanata --check` matrix.
- Gallery shows ~10-12 packs across 3-4 categories (Productivity, Navigation, Layers, Advanced).
- No new pack adds more than ~200 lines to PackDetailView; bigger editors go in their own files.
