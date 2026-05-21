# Pack Dependency System

How packs manage collections they depend on, and how the UI stays consistent across the Rules list, Gallery detail pages, and settings panels.

## User Requirements

### Ownership

When a pack is installed that manages other collections (e.g. Ben Vallack Nav manages Home Row Mods, Home Row Layer Toggles, and Vallack Navigation):

- **Rules list**: managed collections show toggle ON and locked. Name changes contextually (e.g. "Home Row Mods" becomes "Top Row Mods" when Vallack's top-row config is active).
- **Detail page**: toggle ON and locked. Blue "Part of [Pack Name]" tag in the header. Title updates to match the Rules list name. Keyboard preview shows the managing pack's key layout and modifier assignments.
- **Tapping a locked toggle**: alert dialog explaining the relationship, with option to turn off the parent pack.

### Settings Preservation

- **On install**: if the managed collection already has custom settings, a dialog asks "Use Ben's Settings" or "Keep My Settings". Either way, the current config is snapshot-saved.
- **On uninstall**: if settings changed since install, a dialog asks "Restore Previous" or "Keep Current". If unchanged, restores silently.
- **Reset button**: compares against the correct baseline for the active mode (Vallack defaults when top-row keys are active, standard CAGS defaults otherwise). Resets all settings including the hold timing slider. Never switches modes — resetting in Vallack mode stays in Vallack mode.

### Hold Timing Preview

- Slider below the keyboard preview with "Prefer modifiers" (left, low ms) and "Prefer letters" (right, high ms).
- Floating ms label tracks the slider thumb while dragging.
- On release, all keyboard keys animate the hold-to-modifier transition:
  - Keys press down (squish) with staggered random timing
  - Hold as letters for a duration proportional to the slider position (exaggerated: 150ms at "prefer modifiers", 1.2s at "prefer letters")
  - Brief flash to modifier symbols, then release
- The Typing Feel slider inside the Settings panel is hidden when the external slider is present, to avoid redundancy.

### Reactive Updates

- When a pack is installed or uninstalled from any surface (Rules toggle, Gallery detail page, CLI), all open views update immediately — toggles lock/unlock, tags appear/disappear, names change, keyboard previews update.
- The detail page for a managed collection can be open before, during, or after the parent pack is installed, and must reflect the correct state in all cases.

## Design Principles

### 1. Single source of truth for ownership

`InstalledPackTracker` is the only place that knows which packs are installed. `Pack.managedCollectionIDs` is the only place that declares which collections a pack manages. Ownership is derived by joining these two — never cached or duplicated in UI state.

### 2. Record before broadcast

When installing a pack, the install record is written to `InstalledPackTracker` before `regenerateConfigFromCollections()` posts its notification. This ensures any notification-triggered query already sees the ownership record. The reverse order caused a race where the UI would refresh, find no ownership, and show stale state.

### 3. Parent packs take precedence

`packManagingCollection()` prefers a parent pack (where `associatedCollectionID != collectionID`) over a self-managing pack. This handles the case where both the Home Row Mods pack and the Vallack pack are installed — Vallack is returned as the owner, not the HRM pack itself.

### 4. Notification-driven refresh with debounce

Views listen for `.installedPacksChanged` and `.ruleCollectionsChanged` notifications. Multiple rapid notifications (e.g. during a multi-step install) are coalesced by cancelling the previous refresh task and starting a new one with a short delay. This prevents stale intermediate states from flashing in the UI.

### 5. Config baseline follows active mode

The "default" config that Reset compares against and restores to depends on what mode is active. The Vallack baseline (top-row keys, Vallack timing, opposite-hand on press) is defined once as `HomeRowModsConfig.vallackDefault` and used by both the installer and the UI. No duplicated config literals.

### 6. Snapshot-based settings preservation

Before applying a pack's config, the existing state is serialized to a JSON file. On uninstall, the snapshot is deserialized and optionally restored. This is a simple, robust mechanism that doesn't require schema migration — the snapshot is the same `Codable` struct used at runtime.

## Implementation Audit

### Where we're living the principles well

**Ownership derivation** (Principle 1): The Rules list's `collectionOwnershipMap` and the detail page's `managingPackName` are both computed fresh from `InstalledPackTracker.packManagingCollection()` on every refresh. No stale caches.

**Record-before-broadcast** (Principle 2): `PackInstaller.install()` upserts the record before calling `applyVallackSystemConfigs()`, which posts notifications. The error path cleans up (removes the record) if config application fails.

**Single baseline config** (Principle 5): `HomeRowModsConfig.vallackDefault` is used by `PackInstaller` when applying and by `HomeRowModsCollectionView` when computing `hasCustomizations` and `resetToDefaults`. One definition, two consumers.

### Where we're stretching

**Notification fan-out** (Principle 4): The detail page listens for two notifications and debounces. The Rules list listens for `.installedPacksChanged` to refresh ownership, and separately relies on the ViewModel's state stream for collection data. These are two parallel refresh mechanisms for related state. If the system grows, consider unifying into a single ownership-change event.

**Vallack-specific branching** (Principle 5): `Pack.managedCollectionIDs` uses a hardcoded ID check for the Vallack pack. `usesTopRowKeys` is a heuristic based on `enabledKeys` content rather than explicit ownership. Both work correctly today but would need generalization for a second multi-collection system pack. Tracked in [#468](https://github.com/malpern/KeyPath/issues/468).

**Detail page refresh scope** (Principle 4): `refreshInstallState()` re-queries everything (install state, ownership, live config, tap/hold selections) on every notification. Most of these don't change when a sibling pack is installed. A more targeted refresh would be more efficient, but the current approach is correct and the cost is negligible with the current number of packs.
