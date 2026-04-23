# M1 — Gallery MVP · Implementation Plan

**Branch:** `feat/m1-gallery-mvp`
**Status:** Active
**Target duration:** 3–4 weeks of engineering
**Owner:** (team)
**Design source:** [`sprint-1/`](sprint-1/) + [`sprint-2/`](sprint-2/) (applied selectively per M1 scope)

---

## What M1 ships

**One coherent change:** a Gallery tab containing 3 curated packs, each installable with one click via a Direction-C-style Pack Detail panel. Existing inspector UI is unchanged. Users can install, uninstall, and undo. That's it.

**The three Starter Kit packs for M1:**

1. **Caps Lock → Escape** — one binding, zero config. The simplest valuable remap.
2. **Home-Row Mods — Light** — 4 bindings (index + middle fingers), one quick setting (hold timing). The hobby onramp.
3. **Smart Quotes & Dashes** — 3 bindings, no config. The writer persona.

These represent three different personas (simple remap / hobbyist / writer) and three different complexity levels (zero config / one quick setting / automatic context-sensitive binding). If they work, M2 confidence follows.

---

## What M1 does NOT ship

Everything in Sprint 2 except the minimum needed to install/uninstall a pack. Specifically:

- ❌ Inspector rebuild (existing inspector stays)
- ❌ Override precedence model in full (keep the existing conflict dialog — ugly but known behavior)
- ❌ Pack coherence reporting (all packs just say "installed")
- ❌ Layer × pack interaction (M1 packs are all base-layer)
- ❌ First-run experience (users just see an empty keyboard + the Gallery tab)
- ❌ Customize sheet chrome (M1 packs either have zero or one quick setting, handled inline on Pack Detail)
- ❌ Discover/Categories/My Packs as three tabs (single "Gallery" view for 3 packs)
- ❌ Search
- ❌ Gallery-standalone fallback for Pack Detail (M1 Pack Detail is only invoked from the main window's Gallery)

All deferred to M2+.

---

## Architecture — how M1 fits into what exists

M1 **adds** surfaces; it does not rebuild existing ones.

### New types (M1 introduces)

```
Sources/KeyPathCore/
├── Pack.swift                    — manifest data model
├── PackBinding.swift             — a single binding contributed by a pack
└── PackRegistry.swift            — hardcoded list of the 3 Starter Kit packs

Sources/KeyPathAppKit/UI/Gallery/
├── GalleryView.swift             — the Gallery tab content
├── PackCard.swift                — the 240×140 pt card component
└── PackDetailPanel.swift         — the Direction-C pack detail panel
```

### Integration with existing systems

- **Install**: converts a pack's binding templates into concrete `CustomRule` entries in the existing `CustomRulesStore`. The pack's ID is stored in each rule's metadata so uninstall can find them.
- **Uninstall**: enumerates `CustomRulesStore` for rules tagged with this pack's ID, removes them. The existing config regeneration path picks up the change.
- **Pack status tracking**: new `InstalledPackTracker` service stores which packs are installed + their current settings (for quick-setting persistence). Lives in `~/.config/keypath/installed-packs.json`.

### Intentionally not touching

- The existing "Custom Rules" / rules tab stays. Users can still create direct remaps exactly as before. M1 does not hide or rename this.
- The inspector stays. No changes.
- The Installation Wizard stays. No changes.
- `RuleCollectionsManager` and its associated UI remain. Packs are a parallel system in M1; merger is M2.

This is intentional. M1 ships a new Gallery tab *alongside* existing surfaces so we can measure whether users engage with it. M2 begins the unification.

---

## Phases

### Phase 1 — Data model + pack registry (Week 1)

- Define `Pack`, `PackBinding`, `PackQuickSetting` types in `KeyPathCore`.
- Write the 3 Starter Kit pack manifests (code, not JSON — keep it simple for M1).
- Define `InstalledPackTracker` service: persist which packs are installed and their current quick-setting values.
- Install/uninstall logic:
  - Install: expand pack bindings into `CustomRule` entries with pack metadata.
  - Uninstall: find rules by pack ID, remove them.
- Unit tests for pack install/uninstall round-trip.

**Exit criteria:** I can call `PackInstaller.install(.capsLockToEscape)` from code and my keyboard's caps key presses escape. I can uninstall and it reverts.

### Phase 2 — Gallery view + pack card (Week 2)

- Add "Gallery" tab to the main window (alongside existing tabs).
- Build `GalleryView` — a simple vertical stack of 3 pack cards. No Discover/Categories split yet.
- Build `PackCard` component — 240×140 pt per card grammar spec. Hover/press states. Click → Pack Detail.
- No search, no categories, no My Packs separation.

**Exit criteria:** User can navigate to Gallery tab, see 3 cards, click one. Pack Detail surface can be a placeholder at this point.

### Phase 3 — Pack Detail panel (Week 3)

- Build `PackDetailPanel` per Direction C.
- Anchor right-of-center over the main window.
- Main window keyboard canvas dims to ~90%; affected keys get pending-state tint.
- Panel contains: name, description, affected keys list, quick settings (if any), Install/Customize buttons.
- On Install: panel dismisses, affected keys transition from pending → installed tint, toast with Undo appears.
- On Uninstall (for installed packs): affected keys fade from installed → default, toast confirms.
- Quick settings (Home-Row Mods' hold timeout slider) persist per pack via `InstalledPackTracker`.

**Exit criteria:** User opens Gallery → clicks "Caps Lock → Escape" → sees pending tint on caps → clicks Install → keys solidify → presses caps → escape fires. Full end-to-end.

### Phase 4 — Polish + testing (Week 4)

- Visual refinement of Pack Detail (material, typography, spacing).
- Motion timing per Sprint 1 motion notes (pending → installed transition, toast entry/exit).
- Dark Mode pass.
- Keyboard navigation (Tab through Gallery, Enter to open Pack Detail, Esc to dismiss).
- Manual end-to-end tests for all 3 packs: install, use, uninstall, reinstall.
- Smoke test: install all 3 concurrently, verify they coexist (since they don't overlap on keys).
- Build + notarize + verify.

**Exit criteria:** Shippable. Ready for an internal review and a decision on whether to cut a release.

---

## Open engineering questions to resolve during M1

1. **Pack manifest format.** I'm starting with Swift-native types in Phase 1. Alternative: JSON in a bundled Resources file, loaded at runtime. Native types are simpler for 3 packs; JSON is better if we want community authorship later. **M1 answer:** Swift types, revisit in M2 if we add more packs.

2. **Where does the Gallery tab live?** Two options:
   - a) In the main window's existing tab bar (alongside Rules, Settings, etc.)
   - b) As a new window accessible from the menu bar
   - **M1 answer:** (a) — don't fragment the app's window model.

3. **How to show the "keyboard canvas" for Pack Detail's pending state.** The main window already has a keyboard view. Does Pack Detail reuse it, or render its own? **M1 answer:** reuse. Pack Detail observes a "pending pack binding overlay" state on the shared keyboard model; the main keyboard renders tinted keys accordingly. One source of truth.

4. **Conflict handling in M1.** If a user already has a direct remap on caps, then tries to install "Caps Lock → Escape", what happens?
   - **M1 answer:** use the existing conflict dialog. The user sees the current "Rule conflict" modal. Ugly but works. M2 replaces with the inline warning from Sprint 2's override-precedence design.

5. **Uninstall granularity.** If a user has customized a pack's quick setting, uninstall removes everything including the custom setting. Is this correct? **M1 answer:** yes. Uninstall means uninstall. If the user wants to preserve settings, they should leave the pack installed.

6. **Analytics / instrumentation.** Per the PM's recommendation, M1 should ship with minimal local-only usage tracking to know which packs get installed, whether undo is used, whether users return to the Gallery. **M1 answer:** scope a follow-up doc, defer instrumentation to Phase 4. Must be local-only, anonymized, user-disableable from settings.

---

## Risks and mitigation

- **Risk:** Direction C's "real keyboard as preview" pattern doesn't feel right in practice.
  **Mitigation:** Phase 3 includes early self-testing before locking the interaction. If it feels wrong, we have Direction A wireframes to fall back on — panel contains its own mini-diagram. Cost of pivot: a few days.

- **Risk:** The 3 packs don't validate the hypothesis (users don't engage).
  **Mitigation:** That's the whole point of M1 being small. Shipping 3 packs and learning "nobody wants this" is cheaper than shipping 12 and finding out. If M1 ships and Gallery engagement is low, we revise M2 goals.

- **Risk:** Existing `CustomRulesStore` / rules pipeline breaks under pack installations.
  **Mitigation:** Unit tests in Phase 1 lock install/uninstall round-trip. Pack-contributed rules are just `CustomRule` entries with metadata — the existing pipeline is oblivious to the source. Low risk.

- **Risk:** The panel-over-keyboard interaction in Direction C has state-sync bugs.
  **Mitigation:** single source of truth (see open question 3). Pending state is a single overlay on the shared keyboard model; Pack Detail subscribes to and writes to it. No duplicate state.

---

## Out of scope and explicitly deferred

- Pack updates (no versioning, no CDN fetch)
- Community packs
- Pack search
- Pack categorization
- The "My Packs" management surface
- Accessibility audit beyond basic VoiceOver labels and keyboard nav
- Localization
- Telemetry beyond bare minimum anonymous usage counters
- Per-pack authorship (all M1 packs are first-party, in-code)
- Full Direction-C motion spec (timing TBD in Phase 4 self-testing)

All are M2+ topics.

---

## Success criteria

**Minimum to ship:**
- User can browse to the Gallery tab.
- User can install any of the 3 packs.
- The keyboard responds as expected post-install.
- User can uninstall and keyboard reverts.
- Undo works on install/uninstall toast.
- No regressions in existing rules/inspector/wizard flows.

**To declare M1 a success (post-ship):**
- Some non-zero fraction of users installs at least one pack within the first session.
- Gallery tab is opened more than once by users who used it once.
- No high-severity bugs filed against Gallery in first two weeks.

**To declare M1 a failure and redirect:**
- Users open Gallery, don't install anything, don't return.
- Gallery ships but creates more support load than the existing Rules tab.
- Technical bugs around the shared-keyboard-state-for-pending overlay prove unmaintainable.

---

## What happens after M1

If M1 ships and the hypothesis is validated:

- **M2** (~6 weeks): rebuild inspector with simplified pack-awareness; implement override precedence model (without "see all sources" disclosure); replace conflict modal with inline override warning; add the 4–5 next Starter Kit packs.
- **M3** (~4 weeks): first-run moment; coherence reporting (2 states); Gallery split into Discover/My Packs; full Starter Kit up to 12 packs.
- **M4+**: layer-pack interaction, full coherence model, Customize chrome, community packs.

If M1 doesn't validate, we have cheap options:
- Pivot: keep the existing Rules tab, improve its curation.
- Kill: Gallery is removed in a subsequent release; we learn something useful.
- Iterate: the 3 packs weren't right; try different 3.

Any of those outcomes is useful. The point of M1 is to get to one of them fast.

---

## Log of implementation progress

*(This section will be updated as code lands.)*

### 2026-04-22 — M1 kickoff
- Branch `feat/m1-gallery-mvp` created off master.
- Design docs (Sprint 1 + Sprint 2) committed. Permission-overlay / wizard-routing exploration stashed for separate review.
- This plan document committed.
- Phase 1 starting: Pack data model.
