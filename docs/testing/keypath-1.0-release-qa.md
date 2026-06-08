# KeyPath 1.0 Release QA Plan

This document coordinates the testing work required before KeyPath can be
called confidently ready for a public 1.0 release. It builds on the existing
layered test strategy and the deeper Home Row Mods release QA pass.

## Release Readiness Goal

KeyPath is ready for 1.0 when the main user workflows have been verified at
all relevant layers:

- UI behavior: the visible app behaves as expected.
- Persistence: settings, rules, packs, and snapshots survive close/reopen and
  relaunch where expected.
- Config effect: generated Kanata config contains the expected fragments.
- Runtime effect: apply/reload succeeds through the installed app path.
- Logs: recent app, CLI, helper, and Kanata logs do not show unclassified
  errors for the workflow under test.

The goal is not exhaustive UI automation of every possible combination. The
goal is risk-based release confidence: broad model/config coverage, deterministic
snapshots for stable UI states, installed-app smoke for runtime workflows, and
manual or Computer Use checks for real macOS behavior.

## Current Scorecard

| Area | Current score | 1.0 target | Notes |
| --- | ---: | ---: | --- |
| Unit/model logic | 9/10 | 9/10 | Strong foundation. |
| Kanata config generation | 9/10 | 9/10 | Explicit per-rule option matrix is covered by #819/#823. |
| Rule collections and packs | 8.5/10 | 8.5/10 | Pack interop and installed smoke gates are covered by #815/#821 and #811/#824. |
| CLI | 8.5/10 | 8.5/10 | Strong contract and facade coverage. |
| Installer/runtime/service | 7.5/10 | 8/10 | Good tests, plus signed setup QA in #747. |
| Overlay logic | 8/10 | 8/10 | Snapshot and label-resolution coverage is broad; live physical downstates remain a release QA check. |
| Visual snapshots | 8/10 | 8/10 | Scenario snapshots cover overlay, mapper, pack detail, inspector, rules, General settings, and Repair settings. |
| Settings/preferences | 8/10 | 8/10 | Persistence, validation, layout/keymap, and runtime argument coverage landed in #816/#822. |
| Installed-app QA | 8/10 | 8/10 | `qa-keypath-release-smoke.sh` covers representative installed-app workflows. |
| Manual/Computer Use QA | 8/10 | 8/10 | Product-wide UI release checklist and CU/manual/script boundaries are current after #830, #834, and #837; final signed release pass remains. |
| Log/error review | 8/10 | 8/10 | `qa-keypath-log-gate.sh` is the release gate for high-signal errors. |
| Overall 1.0 confidence | 8/10 | 8/10 | Remaining open 1.0 risk is signed setup UX in #747 plus final release-candidate execution. |

## 1.0 Tracking Issues

| Issue | State | Area | Acceptance signal |
| --- | --- | --- | --- |
| [#814](https://github.com/malpern/KeyPath/issues/814) | passed | Product-wide QA matrix | This document covers key workflows with status, evidence, and issue links, and defines the public 1.0 acceptance boundary. |
| [#815](https://github.com/malpern/KeyPath/issues/815) | passed | Installed-app smoke | Core rule families are applied, validated, reloaded, log-checked, and restored through `/Applications/KeyPath.app`. |
| [#816](https://github.com/malpern/KeyPath/issues/816) | passed | Settings/preferences | Critical settings have persistence, validation, UI wiring, and config/runtime effect coverage. |
| [#817](https://github.com/malpern/KeyPath/issues/817) | passed | Logs/errors | Release QA fails on unclassified high-signal app/helper/Kanata errors. |
| [#818](https://github.com/malpern/KeyPath/issues/818) | passed | UI snapshots and Computer Use | Overlay, sidebar, menus, mapper, pack detail, and settings have deterministic snapshots or manual QA rows. |
| [#819](https://github.com/malpern/KeyPath/issues/819) | passed | Per-rule options | Every shipping rule family has documented config and UI/persistence coverage for key options. |
| [#831](https://github.com/malpern/KeyPath/issues/831) | passed | Catalog rule editor CU readiness | Catalog rows, editor controls, and advanced action variants have stable Computer Use identifiers/contracts. |
| [#832](https://github.com/malpern/KeyPath/issues/832) | passed | Settings CU readiness | Settings tabs and controls have stable Computer Use identifiers/contracts. |
| [#833](https://github.com/malpern/KeyPath/issues/833) | passed | Overlay/sidebar CU readiness | Overlay, sidebar, inspector, and layer context controls have stable Computer Use identifiers/contracts. |
| [#835](https://github.com/malpern/KeyPath/issues/835) | passed | Computer Use contracts | Remaining CU-targeted audited surfaces have explicit source contracts or documented manual/script-only exceptions. |
| [#836](https://github.com/malpern/KeyPath/issues/836) | passed | Overlay layer picker | User-layer deletion is reachable through a stable Computer Use action, not hover choreography. |
| [#747](https://github.com/malpern/KeyPath/issues/747) | blocked | Signed setup UX | Permission and setup UX still need verification in a signed release build. |
| [#804](https://github.com/malpern/KeyPath/issues/804) | passed | HRM layer assignment | New Layer flow assigns the selected HRM key. |
| [#810](https://github.com/malpern/KeyPath/issues/810) | passed | HRM layer overlay | Layer-mode overlay shows assigned layer labels. |
| [#811](https://github.com/malpern/KeyPath/issues/811) | passed | Vallack interop | Vallack install/uninstall applies and restores managed HRM/nav config without hanging. |

## Required Test Layers

### PR Gate

Use for ordinary development and focused fixes:

```bash
./Scripts/test-fast.sh --changed
python3 Scripts/check-accessibility.py
python3 Scripts/check-computer-use-readiness.py
```

Run the full safe suite before PR/merge for broad changes:

```bash
./Scripts/test-full.sh
```

PR gate expectations:

- Unit/model/config tests pass.
- Relevant golden and snapshot tests pass when touched.
- Accessibility identifiers and Computer Use readiness contracts remain present.
- New behavior has focused tests at the lowest deterministic layer.

### Release Candidate Installed-App Gate

Use the installed app and bundled CLI:

```bash
/Applications/KeyPath.app/Contents/MacOS/keypath-cli
```

Minimum installed-app commands:

```bash
./Scripts/qa-keypath-release-smoke.sh
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
./Scripts/qa-keypath-log-gate.sh
```

Focused HRM settings smoke remains available when debugging HRM-specific
regressions, but it is no longer the product-wide minimum gate:

```bash
./Scripts/qa-hrm-settings-smoke.sh
```

For notarized release-candidate builds, run verification without relaxed
notarization/stapling flags.

### Public Release Manual Gate

Use the matrix below and the [UI release QA checklist](keypath-ui-release-qa.md).
Computer Use is appropriate here because it validates the real macOS
accessibility tree and installed app behavior. It should not become the main CI
test harness.

Use the boundary in [keypath-ui-release-qa.md](keypath-ui-release-qa.md):
stable AX-visible app windows and controls are Computer Use targets; physical
keyboard timing, menu-bar/status-item commands, destructive runtime actions, and
URL/deep-link surfaces remain manual or script-only release checks unless a
future issue explicitly productizes them for Computer Use.

Required evidence per checked workflow:

- UI state is correct.
- Generated config contains expected behavior.
- Reload/apply path succeeds.
- Recent logs are clean or only contain classified benign warnings.
- Any failure is filed as `1.0 release` or `post-release`.

## Product Matrix

Legend: every row uses one of the #814 states: `passed`, `blocked`,
`not current UI`, `manual`, or `post-release`.

| Area | Workflow | Expected release evidence | Status |
| --- | --- | --- | --- |
| Rules | Simple remap | UI creates rule, config maps source to target, reload clean | passed #819 |
| Rules | Modifier/hyper remap | Modifier options persist and render correct Kanata output | passed #819 |
| Rules | Tap-hold / dual-role | Timing/options persist; config emits correct dual-role behavior | passed #819 |
| Rules | Home Row Mods | See [hrm-settings-release-qa.md](hrm-settings-release-qa.md) | passed #804 #810 #811 #824 |
| Rules | Layers and navigation | Layer controls update config, overlay labels, and runtime layer state | passed #819 |
| Rules | Launcher/app/system/URL actions | UI actions persist and generated behavior matches expected action type | passed #819 |
| Rules | Function/media keys | Pack/rule options emit correct media/function mappings | passed #819 |
| Rules | Chords/sequences/tap dance/macros/text | Shipping options have config and persistence assertions | passed #819 |
| Rules | App-specific mappings | App context persists and affects generated conditional config | passed #819 |
| Packs | Install/uninstall common packs | Managed collections apply, snapshot, restore, and reload cleanly | passed #815 #821 |
| Packs | Vallack system | Managed HRM/nav config applies and restores without hang | passed #811 #824 |
| Overlay | Base rendering | Geometry follows physical layout; labels follow logical keymap | manual #818 |
| Overlay | Layer rendering | Layer switch updates colors, labels, and unmapped key style | manual #818 |
| Overlay | Layer picker | Layer selection, creation, and user-layer deletion are reachable through stable Computer Use contracts | passed #833 #836 |
| Overlay | Tap-hold/HRM labels | Primary labels, secondary labels, tint, and downstates are correct | manual #810 #818 #824 |
| Overlay | Sidebar tabs | Tabs open, close, and reflect selected key/layer state | manual #818 |
| Overlay | Inspector/edit flows | Edits route to expected rule/config changes | manual #818 |
| Menus | Menu bar actions | Commands trigger expected app/runtime behavior and logs are clean | manual #818 |
| Menus | Emergency stop/resume | Runtime state changes are visible and reversible | manual #815 #818 |
| Settings | Status/stability | Health state is accurate and does not fabricate blocking issues | passed #812 |
| Settings | Permissions/setup | Signed release UX verified on real app build | blocked #747 |
| Settings | Keyboard layout/keymap | Geometry/labels update according to architecture rule | passed #816 #822 |
| Settings | Overlay preferences | Preferences persist and update overlay state | manual #816 #818 #822 |
| Settings | Advanced/runtime controls | Controls persist, route through helper/runtime, and log cleanly | manual #816 #817 #822 |
| Automation | Computer Use readiness contracts | CU-targeted catalog, settings, overlay/sidebar, and layer picker surfaces have enforced source contracts; manual/script-only exceptions are documented in [keypath-ui-release-qa.md](keypath-ui-release-qa.md) | passed #831 #832 #833 #835 #836 |
| Runtime | Config validate/apply/reload | `qa-keypath-release-smoke.sh` applies representative fixtures, validates with bundled Kanata, reloads, checks TCP, and restores config | passed #815 |
| Runtime | Log review | `qa-keypath-log-gate.sh` captures recent app/CLI/Kanata/unified logs and fails on unclassified high-signal errors | passed #817 |

## Per-Rule Option Coverage Matrix

Automated coverage is intentionally concentrated below the full UI. The current
per-rule matrix is covered by:

- `PerRuleOptionCoverageTests`: catalog inventory, representative generated
  Kanata fragments for each shipping collection style, key option variants, and
  custom behavior families.
- `RuleCollectionStorePersistenceTests.testSaveAndLoad_PreservesPerRuleOptionConfigurations`:
  persistence round-trip for editable per-rule options.
- Existing focused suites for app-specific mappings, HRM timing, chord groups,
  sequences parsing/preservation, launcher key validation, keymap mappings, and
  UI snapshots.

| Rule family / collection | Config evidence | Persistence/UI wiring evidence | Release QA row |
| --- | --- | --- | --- |
| Simple custom remap | `caps -> esc` generated fragment asserted | Custom rule model/store tests plus manual Rules editor row | Rules: Simple remap |
| Modifier and Hyper/Meh remaps | Hyper action expands to Kanata `multi`; shift-aware fork output asserted | Mapping behavior and rule configuration helpers | Rules: Modifier/hyper remap |
| Tap-hold / dual-role | Caps picker and custom dual-role emit `tap-hold-press`; HRM variants cover opposite-hand and timing | Tap/hold picker selections persist | Rules: Tap-hold / dual-role |
| Home Row Mods | Modifier, layer, timing, quick-tap, require-prior-idle, and opposite-hand fragments asserted | HRM config persists; dedicated HRM manual QA remains for real UI/runtime | Rules: Home Row Mods |
| Home Row Layer Toggles | `layer-while-held` and `layer-toggle` variants asserted with referenced layer generation | Layer assignment/toggle mode persists | Rules: Layers and navigation |
| Navigation layers | Vim, Neovim, Mission Control, Numpad, Function, Home Row Arrows, and Vallack layer outputs asserted | Layer preset selections persist | Rules: Layers and navigation |
| Leader key | Leader preference emits `layer_nav_spc` and one-shot nav activation | `LeaderKeyPreference` codable/persistence tests; UI row remains manual | Rules: Layers and navigation |
| Window Snapping | Standard and Vim conventions assert action-key placement and `push-msg "window:*"` output | Convention and activation mode persist; dependency auto-enable covered by view-model sync tests | Rules: Layers and navigation |
| Launcher actions | App, URL, folder, script, and system action push messages asserted | Launcher grid config and mappings persist | Rules: Launcher/app/system/URL actions |
| Function/media keys | Media mode emits brightness/volume; F-key mode removes media outputs | Function key mode and generated mapping list persist | Rules: Function/media keys |
| Chord groups | UI-authored `defchords` block and chord outputs asserted | Chord groups config persists; conflict tests cover validation | Rules: Chords/sequences/tap dance/macros/text |
| Sequences | Existing tests preserve parsed manual `defseq` blocks through regeneration | `SequencesConfig` persists and UI model helpers round-trip; UI-authored runtime generation should be rechecked in installed QA | Rules: Chords/sequences/tap dance/macros/text |
| Tap dance | Custom tap-dance generated fragment asserted | Mapping behavior codable tests | Rules: Chords/sequences/tap dance/macros/text |
| Macro / text output | Text macro generated fragment asserted; text-to-Kanata mapper tests cover conversion breadth | Mapping behavior codable tests | Rules: Chords/sequences/tap dance/macros/text |
| Auto Shift Symbols | Shifted tap-hold output and fast-typing protection asserted | Auto-shift config persists | Rules: Chords/sequences/tap dance/macros/text |
| Fast Navigation / Key Repeat | `managed-repeat` defcfg and per-key `defrepeat` override asserted | Key repeat config persists | Rules: Function/media keys |
| Backup Caps Lock | Both-shift chord emits `defchordsv2` | Single-key picker configuration persists through catalog store | Rules: Chords/sequences/tap dance/macros/text |
| Escape / Delete single-key pickers | Catalog table/picker default outputs included in generated config | Picker config helpers and store persistence cover selected output | Rules: Simple remap |
| App-specific mappings | `AppConfigGeneratorTests` assert virtual keys, switch aliases, duplicate handling, disabled apps, and sanitized keys | `AppKeymapStoreTests` and mapper app-specific tests cover storage/model wiring | Rules: App-specific mappings |
| Disabled/enabled state and conflicts | Disabled collections excluded from config; conflict/deduplication suites cover overlapping keys and save-time behavior | Store persistence covers enabled state; manager tests cover API wiring | Rules: Simple remap |

## Stop Doing

- Do not treat Computer Use as broad CI. Use it for release QA and targeted bug
  verification.
- Do not accept UI-only passes without config and log evidence.
- Do not add one-off QA scripts without linking them from this plan or another
  `docs/testing` checklist.
- Do not rely on untracked manual knowledge. If a flow matters, put it in the
  matrix with status and an issue link.
- Do not run full suites repeatedly during inner-loop work when a focused test
  proves the change; run the full safe gate near PR/merge.

## Exit Criteria For 1.0

Before public 1.0:

- All `1.0 release` issues in the tracking table are closed or explicitly
  reclassified by the maintainer.
- Product matrix rows use only `passed`, `blocked`, `not current UI`, `manual`, or
  `post-release` status.
- Installed-app smoke passes on the intended build.
- Full safe suite, accessibility check, and Computer Use readiness check pass.
- Signed release setup UX has been verified.
- Manual/Computer Use public release pass is complete.
- Log gate has no unclassified errors.
