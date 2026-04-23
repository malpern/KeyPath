# Customize Sheet — Consistent Chrome

**Sprint:** 2
**Status:** Draft — short, enforceable spec
**Scope:** The frame that every pack's detailed Customize UI must sit inside.

---

## Why this exists

Each pack in KeyPath's catalog has its own detailed configuration UI — the existing per-rule editors that live in `Sources/KeyPathAppKit/UI/Rules/*CollectionView.swift` and `*ModalView.swift`. These get repurposed as sheets reachable from Pack Detail (via "Customize…" pre-install or "Edit configuration" post-install).

The pack-specific content of each Customize sheet is genuinely bespoke — a chord-groups editor and a home-row-timing editor have nothing visually in common. That's fine. But the **frame** around them must be consistent, or the product fragments into "a dozen different config apps bolted together."

This doc specifies the frame. Everything inside it is the pack author's call.

---

## Structural requirements

Every Customize sheet is:

1. **A modal sheet** over Pack Detail (or over the Gallery, if that's the calling context). Not a separate window.
2. **Dismissible via ✕ (top-right) or Esc.**
3. **Focus-trapped.** Tab/Shift-Tab cycles within the sheet until it closes.
4. **Scrollable** if the content overflows.
5. **Non-blocking.** Opening a Customize sheet does not pause the app; other app work (menus, keyboard input) continues to work. Unsaved changes prompt on dismiss; more below.

---

## Layout — three zones

Every Customize sheet has exactly three zones, in this vertical order:

```
╔═════════════════════════════════════════════════════════════╗
║                                                         ✕   ║  ← Header zone (48 pt)
║  Home-Row Mods                                  v2.1.0      ║
║  ───────────                                                ║
╠═════════════════════════════════════════════════════════════╣
║                                                             ║
║                                                             ║
║                                                             ║
║         [pack-authored content — fully bespoke]             ║  ← Body zone (flexible)
║                                                             ║
║                                                             ║
║                                                             ║
║                                                             ║
╠═════════════════════════════════════════════════════════════╣
║                                                             ║
║  [ Cancel ]                      [ Install with settings ]  ║  ← Footer zone (68 pt)
║                                                             ║
╚═════════════════════════════════════════════════════════════╝
```

### Header (48 pt tall)

Contains:
- Pack name (SF Pro Display, 17 pt semibold, left-aligned).
- Version (SF Pro Text, 13 pt muted, right-aligned).
- Close (✕) affordance top-right.
- Thin separator below the header dividing it from the body.

**What header does not contain:** pack description, author, ratings, install count, coherence status. Those live on Pack Detail — Customize is focused on editing, not context-setting.

### Body (flexible height)

The entire body area is handed to the pack's bespoke UI. Pack author owns everything inside.

Constraints on pack authors:
- Must respect a **maximum body width of 640 pt** — the sheet can be wider than the default 640 pt if the body requires it, but content should not assume infinite width. Designs that break at 640 pt fail review.
- Must use the app's standard fonts (SF Pro Display, SF Pro Text, SF Mono). Custom fonts rejected.
- Must use the app's standard spacing grid (8 pt / 12 pt / 16 pt / 24 pt). Arbitrary pixel spacing rejected.
- Must honor Dark Mode — no hardcoded color values that only work in one appearance.
- Must honor Reduce Motion — any motion in the body respects system preference.
- Must be scrollable or explicitly bounded — no body that grows forever.
- Should NOT contain its own primary action buttons ("Save", "Cancel", "Install") — those live in the footer, not the body. Pack authors can have inline actions ("Test this chord", "Reset this slider"), but the sheet's decisive actions always live in the footer.

### Footer (68 pt tall)

Contains:
- **Left-aligned**: optional auxiliary action (e.g., "Restore defaults" for post-install sheets with modifications). Secondary button style.
- **Right-aligned**: two buttons — Cancel (secondary) and Primary (accent-tinted).

Primary button's label depends on context:
- **Pre-install**: `Install with settings` (or `Install` if no settings changed).
- **Post-install, unmodified state**: button is hidden — there's nothing to save.
- **Post-install, dirty state**: `Save changes`.
- **Post-install, pack has never been installed at this version**: `Apply update` (rare — only during in-place version upgrade).

---

## State rules

### Pre-install

User is configuring a pack before it's installed. The Customize sheet was opened from Pack Detail's "Customize…" button.

- Body shows the pack's default settings, editable.
- Footer: Cancel + Install with settings.
- Dismissing (Cancel or ✕ or Esc) returns to Pack Detail with no change.
- Installing dismisses the Customize sheet, then dismisses Pack Detail (in C, the panel dismisses and keys solidify on the real keyboard).

### Post-install, unmodified

Pack is installed. Its current configuration matches the installed defaults. User opened Customize via "Edit configuration" on Pack Detail.

- Body shows current settings.
- Footer: Cancel (secondary) + no primary action shown (nothing to save).
- If the user changes anything, state transitions to **post-install, dirty** and primary action appears.

### Post-install, dirty

User has made changes but not saved.

- Body reflects current edits.
- Footer: Cancel + Save changes.
- Cancel prompts if there are unsaved changes: *"Discard your changes?"* with Discard / Keep editing.
- Save applies the changes, dismisses the sheet, triggers the pack to re-apply its bindings.
- If the changes will affect user-overridden keys (which are currently shadowing the pack's bindings), the save prompts:
  *"3 of the changed settings affect keys you've directly remapped. Your direct mappings will stay in effect; these settings only apply to the pack's default bindings. Continue?"*
  One-time prompt, non-blocking, Keep / Continue.

---

## Dismissal and unsaved-change handling

Three ways to dismiss:
- ✕ top-right.
- Esc key.
- Click outside the sheet (NOT enabled — sheets are blocking-modal to prevent accidental dismissal).

All three behave identically:
- If no unsaved changes: dismiss immediately.
- If unsaved changes: non-blocking prompt — *"You have unsaved changes. Discard them?"* — Discard / Keep editing.

Cancel button is equivalent to the dismissal paths above. No separate behavior.

---

## Sizing

- Default size: **640 × 560 pt**.
- Body content can grow up to **960 × 720 pt** (roughly the max that fits on a 13" MacBook Pro with reasonable margins).
- Packs that need more space than 960 × 720 pt are red-flagged in review — pack is too complex to be a single pack, or its UI needs reduction.
- Sheet can always be vertically smaller than 560 pt if content is lighter (e.g., a pack with only two settings doesn't need a 560 pt sheet).

---

## Coherence-aware body adaptations

Pack-authored body content is bespoke, but the chrome **automatically renders a coherence banner** at the top of the body when relevant:

```
╔═════════════════════════════════════════════════════════════╗
║                                                         ✕   ║
║  Home-Row Mods                                  v2.1.0      ║
║  ───────────                                                ║
╠═════════════════════════════════════════════════════════════╣
║                                                             ║
║  ⚠ You've overridden 1 of this pack's bindings. Your        ║  ← automatic
║    overrides will stay in effect; changes you make here     ║     coherence
║    only affect this pack's default bindings.                ║     banner
║    [ Show overridden keys → ]                               ║
║                                                             ║
║  ─────────────────────────────────────────────────────      ║
║                                                             ║
║  [pack-authored content below]                              ║
║                                                             ║
╚═════════════════════════════════════════════════════════════╝
```

The banner is rendered by the chrome, not the pack author, so consistency is automatic. Pack authors don't have to remember to add it.

Banner conditions:
- **Modified**: banner with the text above, plus optional pack-policy-specific concern ("this pack works best when all bindings are intact").
- **Shadowed**: *"Some of this pack's bindings are shadowed by packs installed more recently. Changes here may not take effect on shadowed keys."*
- **Outdated**: *"A newer version of this pack is available. Changes you save here apply to the installed version. [Update]"*

---

## What the chrome provides to pack authors (API contract)

From the pack author's point of view, the Customize sheet is invoked with a context object:

```swift
struct CustomizeContext {
    let pack: PackManifest
    let mode: Mode  // .preInstall | .postInstallUnmodified | .postInstallDirty
    let currentSettings: [SettingKey: Any]

    // Callbacks the pack author's view calls
    let onSettingChange: (SettingKey, Any) -> Void
    let onPrimaryAction: () -> Void   // Install or Save, depending on mode
    let onRequestCancel: () -> Void
    let onShowOverriddenKeys: () -> Void
}
```

Pack authors implement the body. The chrome handles:
- Header rendering and sizing.
- Footer rendering, button enabling/disabling based on state.
- Coherence banner based on `pack.coherenceState`.
- Dismissal prompting.
- Focus trapping.
- Scroll container.

Pack authors do NOT:
- Render their own close buttons, header, footer.
- Handle their own dismiss/prompt logic.
- Manage their own primary action buttons.
- Override keyboard shortcuts for Save/Cancel.

This is enforced by the chrome being a real component, not a style guide.

---

## First-party pack authoring

For v1, all packs are first-party (authored by the KeyPath team). That means we're authoring the bodies too. The "API contract" above is the internal contract between the Customize chrome component and each pack's body view.

Migration from existing per-rule UIs (`HomeRowModsCollectionView`, `ChordGroupsCollectionView`, etc.) to Customize bodies:

1. Strip the existing views of their own dismissal logic (they currently assume they're a top-level sheet).
2. Strip their own primary buttons (they currently have "Done" buttons).
3. Adapt to the `CustomizeContext` API.
4. Verify they render correctly at 640 pt width.

Engineering work, estimated per-view. Documented as part of Sprint 2's customize migration checklist (separate doc, out of design scope).

---

## Accessibility

- Sheet is a `role="dialog"` with modal focus management.
- Header is a `<h1>`-equivalent for screen readers.
- Coherence banner is a `role="status"` live region that announces state changes.
- Primary action is always the last focusable element (so Tab-ing through body eventually reaches it).
- Esc closes; Cmd-Enter saves (when there's a save action available); Cmd-S also saves.
- Cancel button has a `cmd-.` shortcut as alternative.

---

## What's explicitly out of scope

- **Version history / revert to previous settings.** If a user wants to restore pack defaults, they can "Restore defaults" from Pack Detail. Within Customize, there's no "undo my last 10 edits."
- **Customize settings syncing between packs.** Each pack is its own Customize surface. Settings don't flow between packs.
- **Shared presets across packs.** Each pack defines its own settings. No cross-pack preset library.
- **Inline preview of settings effects.** Customize UI can, if the pack author chooses, show a preview, but that's pack-specific. The chrome doesn't require it.

---

## Open questions

1. **Should the Customize sheet's primary action trigger install animation?** In Direction C, install is a visual continuity moment on the real keyboard. If install is triggered from inside Customize, the sheet has to dismiss first, then the Pack Detail panel dismisses, then the install cascade runs. That's two dismissal animations in sequence. Alternative: Customize → Install dismisses Customize *and* Pack Detail as a single coordinated exit, with the install cascade running on the way down. Motion designer to nail this after implementation starts.

2. **Coherence banner — text length.** Some coherence states (e.g., "3 bindings modified, 2 shadowed, 1 from outdated version") produce long banner text. Should the banner truncate or wrap? Proposal: wrap up to 2 lines, then truncate with a "Show details →" link. Keeps chrome tidy.

3. **Settings change detection for `unmodified` vs `dirty` state.** Chrome monitors `currentSettings` vs the last-saved values via deep equality. What about packs with computed or derived settings (e.g., "Layout: Custom" pointing to a deeper sub-view with its own state)? Proposal: packs expose a single `isDirty` property in their `CustomizeContext` callback, computed by the pack's own logic. Gives pack authors full control over when the primary action appears.

---

## Related

- [`override-precedence.md`](override-precedence.md) — why Customize can't silently affect user-overridden keys
- [`pack-coherence.md`](pack-coherence.md) — the coherence states the banner renders
- Sprint 1 [`pack-detail-directions.md`](../sprint-1/pack-detail-directions.md) — Pack Detail is the surface that opens Customize
