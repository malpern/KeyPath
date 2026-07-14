# RELEASE-READINESS.md — KeyPath 1.0

**Target ship date:** Saturday 2026-06-13
**Started:** Tuesday 2026-06-09
**Last updated:** Thursday 2026-06-11 (evening)

Working doc for the pre-1.0 verification push. Keep open all week.

---

## Ship gate — 10 exit criteria (read this first)

**Verdict (Thu AM): AT RISK, trending well — 4 of 10 gates closed, #881 fixed & verified.** Thursday morning: root-caused #881 from the smoke logs, shipped the copy-over-then-prune restore fix ([#884](https://github.com/malpern/KeyPath/pull/884)), hardened the smoke lib with manifest verification, merged [#880](https://github.com/malpern/KeyPath/pull/880), redeployed, and re-verified 6/6 smokes against the fixed app with zero restore warnings. Remaining: **~21 hrs vs ~18 available** (rest of Thu + Fri + Sat morning) — **~3–6 hr gap, still pending the scope call** (cut illustrations / weekend hours / slip).

Two new product findings from this morning's deeper assertions, queued for design review + Friday triage: (1) Leader Key collection's `selectedOutput` is display-only — config binding comes from the system `leaderKeyPreference`, so CLI/JSON collection edits have no effect; (2) Quick Launcher `activationMode=leaderSequence` generates byte-identical config to `holdHyper` — the Hyper hold path stays active. Also filed [#887](https://github.com/malpern/KeyPath/issues/887) (quick-deploy should hard-fail on missing engine binary — bit us during verification).

| # | Exit criterion | Status | Day | Est. hrs left |
|---|---|---|---|---|
| 1 | All 22 families kanata-syntax valid | ✅ closed | Wed | — |
| 2 | High-complexity families per-option coverage | ✅ closed | Wed | — |
| 3 | Release-blocker findings fixed + live-verified | ✅ closed | Wed | — |
| 4 | 6 family smoke scripts pass on installed app | ✅ closed — [#880](https://github.com/malpern/KeyPath/pull/880)+[#884](https://github.com/malpern/KeyPath/pull/884) merged, [#881](https://github.com/malpern/KeyPath/issues/881) fixed & live-verified | Thu AM | — |
| 5 | Design review pass across catalog | ✅ closed — findings triaged; [#888](https://github.com/malpern/KeyPath/issues/888) (post-1.0 backlog), [#889](https://github.com/malpern/KeyPath/issues/889) (Fri must-fix candidate) | Thu | — |
| 6 | Findings triage → must-fix list closed | ✅ closed early — must-fix list **EMPTY** (see Gate 6 section below) | Thu PM | — |
| 7 | RC built, signed, notarized, smoke-verified | ⬜ open | Sat | ~3 |
| 8 | Release notes incl. known limitations | ⬜ draft | Fri/Sat | ~1 |
| 9 | **Docs complete** — in-app detail pages ✅ ([#893](https://github.com/malpern/KeyPath/pull/893) merged); 12 illustrations ✅ ([#894](https://github.com/malpern/KeyPath/pull/894) in CI); remaining: screenshot check + gh-pages publish (Sat flow) | 🟡 nearly closed | Fri | ~1 |
| 10 | **Marketing basics** — website video recorded + landing copy | ⬜ open | Sat/Sun | ~5 |

**Burndown (est. hrs to close all gates, end of day):** start 36 → Tue 30 → Wed 18 → **+13 scope add → 31** → late-Wed smoke sprint **−4 → 27** → Thu proj. 17 → Fri proj. 9 → Sat proj. **~5 hrs unfinished** at current capacity. Close the gap via scope cut, weekend hours, or slip.

### Gate 9 detail — grounded by repo audit (Wed night)

- **Guides missing header illustrations (12):** activity-insights, cli, diagnostics, hammerspoon, installation-wizard, layers, packs, qmk-import, remapping, script-execution, siri-and-shortcuts, vallack-nav. (Generate per [keypath-docs](docs/help-content-philosophy.md) watercolor workflow.)
- **Packs likely missing dedicated detail/guide pages (~6):** backup-caps-lock, delete-enhancement, escape-remap, home-row-arrows, keystroke-history, mission-control. (caps-lock-to-escape probably covered by tap-hold.md — verify.)
- **Resolved (D6):** the orange boxes mark in-app rules lacking a pack detail page — drawn by RulesSummaryView+RowBuilder when `packForCollection == nil`. The authoritative list was Neovim Terminal + Sequences; fixed in #893 (new packs + invariant test). The grep-derived website-guide gaps above were a separate, real-but-unrequested gap — parked post-1.0.

## Plan at a glance

| Day | Focus | Status |
|---|---|---|
| Tue | Inventory + risk-rank + Mapper verification + first decisions | ✅ done |
| Wed | Matrix infra + safety-net fix + sprint planning + verification loop | ✅ done (absorbed Thu's matrix work too) |
| Thu | 5 remaining smoke scripts (gate 4) + design review (gate 5) | next |
| Fri | Triage (gate 6) + release notes (gate 8); must-fix capped at 1 day | pending |
| Sat | RC build + verify (gate 7), ship — or call the slip | pending |

---

## Decisions

- [x] **D1 — HRM ship classification**: **Shipping (no code change needed).** HRM is already `category: "productivity"` in [rule-collection-catalog.json:1132](Sources/KeyPathAppKit/Resources/rule-collection-catalog.json).
- [x] **D2 — Shipping tier**: **Expanded — ALL 22 families ship for 1.0.** User call on Tue PM: "move everything into production, including autoshift. expand the test target." Auto Shift Symbols promoted to `productivity` in [PR #857](https://github.com/malpern/KeyPath/pull/857). Experimental section is now empty for 1.0. Verification budget: all 22 families get at minimum a per-pack kanata-syntax assertion; the high-complexity 7-8 get full golden + per-option matrices.
- [x] **D3 — Mapper tab strategy**: **Defend in place — correctness only.** Mapper is the core. Fix correctness/data-loss bugs. Accept UX polish as known limitations. Verified Tue PM that 2 of 3 claimed Mapper bugs don't hold up; 1 is real but low-impact.
- [x] **D4 — Ship date flexibility**: User said "we can take more time if we need" — Saturday 2026-06-13 is the target, not the constraint. If Thu triage shows must-fix work doesn't fit in Fri, slip with a written reason and a new target.
- [x] **D5 — Scope call (Thu): Option B — add weekend hours, keep full docs scope.** All 12 illustrations + screenshots + marketing video stay in. Saturday may extend / Sunday morning available.
- [x] **D6 — Orange boxes identified (Thu):** they mark **in-app rules lacking a pack detail page** — Neovim Terminal + Sequences were the only two. Fixed in [#893](https://github.com/malpern/KeyPath/pull/893) (new packs + invariant test). My earlier "6 missing website guides" list was a wrong proxy — those website gaps are real but were never the ask; parked as post-1.0 backlog.

---

## Rule family inventory (22 families)

Columns:
- **Category**: actual `RuleCollectionCategory` from the catalog JSON (system / navigation / productivity / layers / accessibility / experimental). Drives UI grouping in Rules tab. _Not a release-tier; the inventory agent's "shipping/experimental/hidden" labels in my first cut were fabricated — see D1._
- **Coverage**: full / good / partial / none (config-correctness tests)
- **Complexity**: low / med / high
- **Risk**: PM to fill in tonight (1-5, where 5 = release blocker if broken)
- **Action**: golden / matrix / walkthrough / defer

_Categories pulled from `rule-collection-catalog.json` via Python on 2026-06-09. Only **1 of 22** families is in the Experimental section (Auto Shift Symbols). The "hidden" tier I described earlier was fabricated — these all show in user-facing UI sections._

| # | Family | Category | Coverage | Complexity | Risk | Action |
|---|---|---|---|---|---|---|
| 1 | Home Row Mods | productivity | **FULL** | high | 2 | walkthrough only |
| 2 | Caps Lock Remap | productivity | **FULL** | low | _ | _ |
| 3 | Chord Groups | productivity | GOOD | high | _ | _ |
| 4 | Sequences | productivity | GOOD | high | _ | _ |
| 5 | Vim Navigation | navigation | GOOD | low | _ | _ |
| 6 | Home Row Arrows | navigation | partial | low | _ | _ |
| 7 | Quick Launcher | layers | partial | high | _ | _ |
| 8 | Fast Navigation | system | partial | med | _ | _ |
| 9 | macOS Function Keys | system | partial | low | _ | _ |
| 10 | Home Row Layer Toggles | productivity | partial | high | _ | _ |
| 11 | Auto Shift Symbols | **experimental** | partial | med | _ | (only family in Experimental section) |
| 12 | Window Snapping | productivity | partial | low | _ | _ |
| 13 | Leader Key | system | partial | low | _ | _ |
| 14 | Escape | productivity | partial | low | _ | _ |
| 15 | Delete Enhancement | productivity | partial | low | _ | _ |
| 16 | Backup Caps Lock | productivity | partial | low | _ | _ |
| 17 | Neovim Terminal | navigation | partial | low | _ | _ |
| 18 | Mission Control | navigation | partial | low | _ | _ |
| 19 | Ben Vallack Nav | navigation | partial | low | _ | _ |
| 20 | Numpad | layers | partial | low | _ | _ |
| 21 | Symbol Layer | layers | partial | low | _ | _ |
| 22 | Function Keys (right hand) | layers | partial | low | _ | _ |

### Cross-family dependencies (matter for test ordering)
- **Home Row Mods ↔ Home Row Layer Toggles** share `TimingConfig`, `OppositeHandMode`, `KeySelection`
- **Home Row Arrows** can fall back to Home Row Layer Toggles when layer mode is on
- **Quick Launcher** requires **Caps Lock Remap** (Hyper key) to function
- All Leader-based layers (Vim, Mission Control, Window Snapping, Ben Vallack, Numpad, Symbol, Function) depend on **Leader Key**

### Top 5 highest-risk coverage gaps (per coverage agent)
1. **Auto Shift Symbols** — no golden file; per-option coverage incomplete
2. **Home Row Layer Toggles** — no golden file, no dedicated mapping generator test
3. **Home Row Arrows** — invisible in integration tests; only via pack loop
4. **Window Snapping** — no golden file; standard/vim mode switching untested
5. **Leader Key** — singleKeyPicker presets (space/caps/tab/grave) untested per-option

---

## Overlay sidebar inventory (10 tabs)

### Tabs

| Tab | Shelf | # Controls | Persists where | Risk (PM tonight) |
|---|---|---|---|---|
| Custom Rules | Main | 7 | RuleCollectionStore | _ |
| **Mapper** | Main | **17** | **In-memory + RuleCollectionStore** | _ |
| Launchers | Main | 2 + Customize panel | RuleCollectionStore | _ |
| History | Main | 1 (read-only) | In-memory | _ |
| Keymap (Logical) | Settings | 4 | @AppStorage | _ |
| Layout (Physical) | Settings | 1 (grid) | @AppStorage | _ |
| Keycaps | Settings | 1 (grid) | @AppStorage | _ |
| Sounds | Settings | custom | PreferencesService | _ |
| Devices | Settings | 1 (custom view) | DeviceSelectionService | _ |
| Settings (gear) | UI control | toggle | In-memory | _ |

### Critical sidebar findings (flagged by inventory agent — verify before fixing)

**HIGH-RISK state-persistence bugs in Mapper:**
- `selectedBehaviorSlot` (Tap/Hold/Shift/Combo): in-memory `@State`, resets on overlay close
- `selectedTapCount` (1×/2×/3×): in-memory `@State`, resets on overlay close
- `selectedTapOutputMode` (Default/Shifted): in-memory `@State`, resets on overlay close

**HIGH-RISK race conditions:**
- Recording state machine has no mutex — multiple recorders can fire simultaneously
- Launcher activation mode/trigger uses async `saveLauncherConfig()` — rapid toggles queue saves
- Notification-driven mapper navigation uses 0.15s magic delay to wait for tab load

**HIGH-RISK UI/state divergence:**
- "Remove" shift variant button visible if save fails silently
- Layer label shows `→ layer` after selection, but if save fails the actual mapping is still keystroke
- System action popover can have multiple collapsible sections expanded at once (no max-height guard)

**Debug flags in shipping code:**
- `OverlayMapperSection.swift:432` `let showDebugBorders = false`
- `LiveKeyboardOverlayView+Inspector.swift:119` `let showDrawerDebugOutline = false`

---

## Test infrastructure (the matrix harness)

**State:** parametrization is weak. `testEachPackProducesValidConfigIndividually()` ([ConfigValidationTests.swift:176](Tests/KeyPathTests/Integration/ConfigValidationTests.swift)) is one test with a loop over all packs — when it fails, the loop exits at the first bad pack and later packs aren't tested.

**Fixture duplication:** confirmed. Same 4-line pattern repeated across [ConfigGoldenFileTests.swift](Tests/KeyPathTests/Integration/ConfigGoldenFileTests.swift), [ConfigValidationTests.swift](Tests/KeyPathTests/Integration/ConfigValidationTests.swift), [ConfigGenerationEndToEndTests.swift](Tests/KeyPathTests/Integration/ConfigGenerationEndToEndTests.swift).

**Estimated lift to bring all shipping families to "good":** 13–19 hours, per coverage agent.

**Stale `.actual` files present** — clean up before measuring this week's progress.

### Matrix-test design (decided Tue PM, ready for Wed AM)

**Decision: add helpers in-place, not a new `Tests/Fixtures/` module.**

[PerRuleOptionCoverageTests.swift](Tests/KeyPathTests/Integration/PerRuleOptionCoverageTests.swift) already has private helpers (`catalogCollection(_:)`, `collection(id:name:configuration:)`, `assertContains`, `assertBalanced`). Extend that pattern. Don't build new ceremony.

**Three small helpers to add** (one new file: `Tests/KeyPathTests/Integration/MatrixTestHelpers.swift`, or extend existing):

```swift
// 1. The 4-line duplication killer
@MainActor
func enabledCollectionConfig(
    _ id: UUID,
    mutate: ((inout RuleCollection) -> Void)? = nil
) -> String {
    var collections = RuleCollectionCatalog().defaultCollections()
    if let idx = collections.firstIndex(where: { $0.id == id }) {
        collections[idx].isEnabled = true
        mutate?(&collections[idx])
    }
    return KanataConfiguration.generateFromCollections(collections)
}

// 2. Pack-based variant (handles the vim-navigation lookup pattern)
@MainActor
func enabledPackConfig(_ packID: String) -> String? {
    guard let pack = PackRegistry.pack(id: packID),
          let collectionID = pack.associatedCollectionID else { return nil }
    return enabledCollectionConfig(collectionID)
}

// 3. Validation helper (paired with #1 so config-correctness + kanata-syntax fold together)
@MainActor
func assertConfigValidWithKanata(
    _ config: String,
    _ family: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let result = try await validateWithKanata(config)
    XCTAssertTrue(result.isValid, "\(family) config invalid. Errors: \(result.errors)", file: file, line: line)
}
```

**After helpers, a golden test becomes 2 lines:**

```swift
@MainActor func testCapsLockEscapeHyper_Golden() {
    assertGoldenConfig(enabledCollectionConfig(RuleCollectionIdentifier.capsLockRemap), named: "caps-escape-hyper")
}
```

**For per-option matrices** (e.g., HRM hold-mode × opposite-hand): use the `mutate` closure:

```swift
@MainActor func testHRM_HoldMode_QuickTap_Golden() {
    let config = enabledCollectionConfig(RuleCollectionIdentifier.homeRowMods) { coll in
        if case .homeRowMods(var cfg) = coll.configuration {
            cfg.holdMode = .quickTap
            coll.configuration = .homeRowMods(cfg)
        }
    }
    assertGoldenConfig(config, named: "hrm-hold-quick-tap")
}
```

**Pack-loop fix** ([ConfigValidationTests.swift:176](Tests/KeyPathTests/Integration/ConfigValidationTests.swift)):

Don't migrate to Swift Testing this week. Instead, generate one `XCTAssertTrue` per pack inside the loop (so all packs run even if one fails), and include the pack name in the assertion message:

```swift
@MainActor
func testEachPackProducesValidConfigIndividually() async throws {
    for pack in PackRegistry.starterKit where !pack.visualOnly {
        guard let collectionID = pack.associatedCollectionID else { continue }
        let config = enabledCollectionConfig(collectionID)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "[\(pack.id)] invalid: \(result.errors)")
    }
}
```

Use `continueAfterFailure = true` in `setUp()` so XCTest runs all packs. Failures now name the bad pack and don't hide later failures.

**Wednesday morning order:**
1. Add the 3 helpers (~30 min, 1 file)
2. Wire `continueAfterFailure = true` + per-pack assertion message (~10 min)
3. Add golden + validation tests for the 7 defended shipping families using the helpers (~3-4 hrs)
4. Add per-option matrices for top-3 high-risk families (Auto Shift, HR Layer Toggles, Window Snapping) (~3-4 hrs)

Total: ~8 hours of focused work, achievable in one day if we don't get blocked.

---

## PRs landed this week — on master

| PR | Summary | Day |
|---|---|---|
| [#857](https://github.com/malpern/KeyPath/pull/857) | Wave 1 cleanups (#853 URL force-unwrap, #854 `try!` regexes, #856 smappservice-poc demote) + Auto Shift promoted experimental → productivity | Wed |
| [#862](https://github.com/malpern/KeyPath/pull/862) | Test infra: `MatrixTestHelpers` + per-family kanata-syntax assertion (all 20 catalog families) | Wed |
| [#864](https://github.com/malpern/KeyPath/pull/864) | Per-option matrix tests (15) for the 4 high-complexity families | Wed |
| [#871](https://github.com/malpern/KeyPath/pull/871) | Generator stub-deflayer safety net for `layer-toggle` orphan references | Wed |
| [#872](https://github.com/malpern/KeyPath/pull/872) | HRL Toggles release-readiness smoke script | Wed |
| [#875](https://github.com/malpern/KeyPath/pull/875) | Smoke script drops f/j to sidestep Home Row Arrows collision | Wed |

## Sprint 1.1 planning — captured

| Issue | What |
|---|---|
| [#865](https://github.com/malpern/KeyPath/issues/865) | **Sprint epic** — bidirectional prerequisite detection (forward + reverse) |
| [#870](https://github.com/malpern/KeyPath/issues/870) | Data model + graph builder (start here) |
| [#866](https://github.com/malpern/KeyPath/issues/866) | Detector module (forward + reverse) |
| [#867](https://github.com/malpern/KeyPath/issues/867) | Per-family dependency catalog |
| [#869](https://github.com/malpern/KeyPath/issues/869) | Forward dialog UI |
| [#868](https://github.com/malpern/KeyPath/issues/868) | Reverse dialog UI |
| [#873](https://github.com/malpern/KeyPath/issues/873) | Refactor kanata-check test helper (pipe deadlock + MainActor) |

## Verification loop — closed end-to-end

`./Scripts/quick-deploy.sh` rebuilt + reinstalled the app with all 5 Wednesday PRs. `./Scripts/qa-hrl-toggles-smoke.sh` then ran cleanly against the installed CLI: all three cases passed — including case 2 which exercises the stub-deflayer safety net from #871. The whole "found a bug → designed a fix → shipped it → verified live" cycle closed within Wednesday.

---

## Findings log

| Day | Source | Finding | Severity | Disposition |
|---|---|---|---|---|
| Tue PM | Mapper verification (task #1) | **Refuted** — "state-persistence bug" was overstated. Picker mode (slot/count/output-mode) is ephemeral `@State`, but real configured actions are persisted in `MapperViewModel.advancedBehavior` and restored on overlay reopen via `loadBehaviorFromExistingRule()` (line 97 of OverlayMapperSection.swift, body of method at MapperViewModel.swift:393). `configuredBehaviorSlots` set gives visual indicator. No data loss. | low (UX, not data) | Known-limitation note: "Mapper opens to Tap slot — click Hold/Shift to see actions you configured for that slot." |
| Tue PM | Mapper verification (task #2) | **Refuted** — "no recording mutex." Every `toggle*Recording()` in [MapperViewModel.swift:651-758](Sources/KeyPathAppKit/UI/Mapper/MapperViewModel.swift) explicitly calls `stopRecording()` before activating its own recorder. MainActor serializes SwiftUI events. Hold and double-tap have explicit conflict dialogs. | — | Close. |
| Tue PM | Mapper verification (task #3) | **Confirmed** — `saveLauncherConfig()` at [OverlayInspectorPanel+LauncherCustomize.swift:215](Sources/KeyPathAppKit/UI/Overlay/OverlayInspectorPanel+LauncherCustomize.swift:215) spawns unbounded `Task` per call. But load-mutate-save goes through `ruleCollectionStore` (actor-isolated) and final UI state drives final save. Worst case: momentary persisted state lags by 1 toggle. | low | Post-1.0 cleanup. Not a release blocker. |
| Wed AM | Per-option matrix tests (task #7, PR #864) | **HRL Toggles + toggle mode produces an invalid kanata config when no companion layer family is enabled.** The catalog default key assignments reference layers (`fun`, `sym`, `num`) owned by Function/Symbol/Numpad — when those are disabled, kanata rejects with `layer name is not declared in any deflayer: fun`. `whileHeld` mode happens to accept forward references and works fine. The companion `testHRLToggles_ToggleMode_WithCompanionLayers_IsValid` test confirms enabling the companions resolves it. | **medium** | **Pending triage Thu/Fri.** Options: (1) auto-enable companions when user picks toggle mode, (2) UI requirement, (3) generator emits stub deflayers, or (4) document as known limitation in release notes. Test `testHRLToggles_ToggleMode_WithoutCompanionLayers_Documented` captures current behavior so a fix surfaces in CI. |
| Wed AM | Test infra rollout (#862 merged, #864 open) | **Every shipping rule family confirmed kanata-syntax-valid** (whole-catalog assertion runs in 1.47s). Per-option matrix tests added for HRL Toggles, Quick Launcher, Window Snapping, Auto Shift — 15 new tests, 14 pass + 1 documents the finding above. | — | Strong release-readiness signal on the config-generator side. |
| Wed PM | Option A safety net merged (#871) | One-regex addition to the existing orphan-layer scanner in `KanataConfiguration+BlockBuilders.swift` — catches `layer-toggle` in addition to `layer-while-held` and `layer-switch`. Kanata now accepts HRL Toggles toggle-mode-alone configs; orphan home-row keys silently no-op rather than catastrophically failing. | — | **Fixed before ship.** |
| Wed PM | Smoke script verification (#872 + #875) | Built `qa-hrl-toggles-smoke.sh` following `qa-hrm-settings-smoke.sh` template. Smoke surfaced the existing **collision detector** also fires on HRL+Arrows on `f` — a useful second finding. The detector's message is clear and actionable; it's effectively a working first-line UX for the misconfiguration class. | — | Bonus signal for sprint epic [#865](https://github.com/malpern/KeyPath/issues/865) — existing detector copy is the pattern the new prerequisite dialogs should mirror. |
| Wed PM | End-to-end verification | `./Scripts/quick-deploy.sh` + `./Scripts/qa-hrl-toggles-smoke.sh` against installed app — all 3 cases pass. Confirms #871 safety net works in a real signed/installed build, not just unit tests. | — | Closes the loop. |
| Wed ~23:00 | Smoke-suite sequential run ([#880](https://github.com/malpern/KeyPath/pull/880)) | **`config restore` round-trip lost sidecar config files** (RuleCollections.json, DeviceSelection.json, installed-packs.json, …) and leaked transient collection state (Window Snapping stayed enabled). Restore code is faithful in isolation; prime suspect is a sync client racing the wipe-and-copy cycle (`.sb-*`/`.dat.nosync*` artifacts show the config dir is inside sync scope). User config manually repaired from the earliest complete backup and verified. | **HIGH — release-blocker candidate** | Filed [#881](https://github.com/malpern/KeyPath/issues/881) with evidence timeline + Thu repro plan (fs_usage). #880 held until root-caused + lib hardened with a restore-manifest check. Top of Friday triage. |

---

## Design review (gate 5) — Thu, completed

Method: full catalog copy extraction (names, summaries, activation hints, pack taglines) reviewed directly + agent inventory of all user-visible strings in the 7 complex editors (HRM, HRL Toggles, Chords, Sequences, Auto Shift, Key Repeat, Launcher editor).

### Findings → Friday triage buckets

**Must-fix candidates (cheap, user-facing correctness):**
1. **Leader Key picker is a broken control** — `selectedOutput` is display-only (config binding comes from system `leaderKeyPreference`). Shipping a picker that silently does nothing is worse than no picker. Options: wire it to the preference (best), or hide the picker for 1.0. ~1–3h either way.
2. **Activation-hint accuracy** — Vim Nav / Neovim Terminal hints say "Hold Leader key to enter Nav" but the default nav activation mode is tap-to-toggle (one-shot). Verify which is true for a fresh install and fix the hint copy. ~30 min.

**Known limitations (release notes, no code):**
3. Launcher `activationMode=leaderSequence` keeps the Hyper hold path active (config-identical to holdHyper). Note in release docs until intent is decided.
4. HRL Toggles toggle-mode without companion layers: keys silently no-op (stub-deflayer safety net). Covered by sprint epic #865.
5. **Hand-written `(cmd ...)` kanata actions no longer work** — the bundled engine is now compiled without kanata's `cmd` feature ([#879](https://github.com/malpern/KeyPath/issues/879)): the root daemon cannot execute shell commands regardless of config contents. Configs merely carrying the legacy `danger-enable-cmd yes` header still load; configs *using* `(cmd ...)` fail validation with kanata's "cmd is not enabled for this executable" message. Supported alternative: KeyPath's consent-gated script actions, found under **Settings → Script Execution** (run as the user, not root; see the Running Scripts guide).

**Post-1.0 design backlog (umbrella issue):**
6. **Timing vocabulary chaos** — "tap window / hold delay / tap offset / hold offset / quick tap term / prior idle" used across editors without a shared mental model; raw ms fields leak implementation names (`requirePriorIdleMs`, `hrm-stats`).
7. **Two magic keys, no explanation** — "Leader" (most layers) vs "Hyper" (Quick Launcher, provided by Caps Lock Remap). Nothing at catalog level explains the difference or the dependency.
8. **Activation-hint format inconsistency** — "Leader → f → function keys" vs "Hold Hyper key" vs "11 keys · 180ms hold" (a spec, not an instruction); 9 families have no hint at all.
9. **"Ben Vallack" naming** — two families named after a YouTuber; meaningless to most users.
10. **Agent's top-10 string fixes** — e.g. "Raw values" → "Expert mode", "Favor tap when another key is pressed (quick tap)" → clearer phrasing, "Protect fast typing" → say what it does, Key Repeat "Speed" is actually an interval. Full list preserved in the umbrella issue.

### Overall design verdict

The catalog presentation layer (names, taglines, summaries) is in **good shape** — taglines are benefit-oriented and consistent in voice. The weakness is concentrated in the **advanced editor copy** (timing controls especially), which assumes keyboard-enthusiast vocabulary. None of it blocks 1.0 for the core audience; items 1–2 above are the only ship-relevant fixes.

## Gate 6 triage — CLOSED EARLY (Thu PM)

The must-fix list is **empty**. Every finding resolved or reclassified:

| Finding | Resolution |
|---|---|
| [#889](https://github.com/malpern/KeyPath/issues/889) Leader picker | **Downgraded to post-1.0** — probe showed the in-app path is fully wired (`updateLeaderKey` syncs preference + activators + rollback); only headless CLI/JSON edits bypass it. Release-notes line instead. |
| Activation-hint accuracy | **Verified accurate** — holding Leader enters nav in both activation modes (direct `layer-while-held` or one-shot wrapper). No copy change needed. |
| HRL companions silent no-op | Safety-netted (#871) + release note + #865 sprint |
| Launcher leaderSequence ≡ holdHyper | Release note + design question in #888 |
| Restore data loss (#881) | **Fixed + live-verified** (#884) |
| CI fake-green full lane | Fixed (#891 + cache stamp); runner-specific simulator issue tracked in #896 |

## Known-limitations release notes draft (collect for Friday)

Draft copy for the 1.0 notes (final wording Fri):

- **Changing the Leader key:** use the app's Rules tab. The `keypath` CLI and direct config-file edits don't yet propagate Leader key changes ([#889](https://github.com/malpern/KeyPath/issues/889)).
- **Home Row Layer Toggles in "Toggle" mode** references the Function, Symbol, and Numpad layers — enable those rules too, or the assigned keys will do nothing on hold. (KeyPath keeps the rest of your keyboard working either way; a guided prompt is planned.)
- **Quick Launcher activation:** the Hyper-hold route stays active even when "Leader → L" activation is selected.
- **Mapper editor:** reopens to the Tap slot; click Hold/Shift/Combo to see actions you've configured for those slots.

(Empty — populate as we triage on Thursday.)
