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
| Kanata config generation | 8.5/10 | 9/10 | Add explicit per-rule option matrix. |
| Rule collections and packs | 8/10 | 8.5/10 | Strong, but pack interop gaps remain. |
| CLI | 8.5/10 | 8.5/10 | Strong contract and facade coverage. |
| Installer/runtime/service | 7.5/10 | 8/10 | Good tests, plus signed setup QA in #747. |
| Overlay logic | 7/10 | 8/10 | Needs more live/downstate and visual coverage. |
| Visual snapshots | 6.5/10 | 8/10 | Infrastructure exists; scenario coverage needs expansion. |
| Settings/preferences | 3/10 | 8/10 | Largest current gap. |
| Installed-app QA | 5.5/10 | 8/10 | Needs broad workflow smoke beyond HRM. |
| Manual/Computer Use QA | 5/10 | 8/10 | HRM pattern needs to become product-wide. |
| Log/error review | 5/10 | 8/10 | Needs scripted release gate. |
| Overall 1.0 confidence | 6.5/10 | 8/10 | Good base, incomplete release qualification. |

## Blocking Issues

| Issue | Area | Acceptance signal |
| --- | --- | --- |
| [#814](https://github.com/malpern/KeyPath/issues/814) | Product-wide QA matrix | This document or a linked matrix covers all key workflows with status and issue links. |
| [#815](https://github.com/malpern/KeyPath/issues/815) | Installed-app smoke | Core rule families are applied, validated, reloaded, log-checked, and restored through `/Applications/KeyPath.app`. |
| [#816](https://github.com/malpern/KeyPath/issues/816) | Settings/preferences | Critical settings have persistence, validation, UI wiring, and config/runtime effect coverage. |
| [#817](https://github.com/malpern/KeyPath/issues/817) | Logs/errors | Release QA fails on unclassified high-signal app/helper/Kanata errors. |
| [#818](https://github.com/malpern/KeyPath/issues/818) | UI snapshots and Computer Use | Overlay, sidebar, menus, mapper, pack detail, and settings have deterministic snapshots or manual QA rows. |
| [#819](https://github.com/malpern/KeyPath/issues/819) | Per-rule options | Every shipping rule family has documented config and UI/persistence coverage for key options. |
| [#747](https://github.com/malpern/KeyPath/issues/747) | Signed setup UX | Permission and setup UX verified in a signed release build. |
| [#804](https://github.com/malpern/KeyPath/issues/804) | HRM layer assignment | New Layer flow assigns the selected HRM key. |
| [#810](https://github.com/malpern/KeyPath/issues/810) | HRM layer overlay | Layer-mode overlay shows assigned layer labels. |
| [#811](https://github.com/malpern/KeyPath/issues/811) | Vallack interop | Vallack install/uninstall applies and restores managed HRM/nav config without hanging. |

## Required Test Layers

### PR Gate

Use for ordinary development and focused fixes:

```bash
./Scripts/test-fast.sh --changed
python3 Scripts/check-accessibility.py
```

Run the full safe suite before PR/merge for broad changes:

```bash
./Scripts/test-full.sh
```

PR gate expectations:

- Unit/model/config tests pass.
- Relevant golden and snapshot tests pass when touched.
- Accessibility identifiers remain present.
- New behavior has focused tests at the lowest deterministic layer.

### Release Candidate Installed-App Gate

Use the installed app and bundled CLI:

```bash
/Applications/KeyPath.app/Contents/MacOS/keypath-cli
```

Minimum commands today:

```bash
./Scripts/qa-hrm-settings-smoke.sh
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

Target after #815:

```bash
./Scripts/qa-keypath-release-smoke.sh
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

Log review can also be run independently after installed-app or manual QA:

```bash
./Scripts/qa-keypath-log-gate.sh
```

For notarized release-candidate builds, run verification without relaxed
notarization/stapling flags.

### Public Release Manual Gate

Use the matrix below and product-specific checklists. Computer Use is appropriate
here because it validates the real macOS accessibility tree and installed app
behavior. It should not become the main CI test harness.

Required evidence per checked workflow:

- UI state is correct.
- Generated config contains expected behavior.
- Reload/apply path succeeds.
- Recent logs are clean or only contain classified benign warnings.
- Any failure is filed as `1.0 release` or `post-release`.

## Product Matrix

Legend: `PASS` passed, `FAIL` known failure, `MANUAL` planned/manual/not
current UI, `TODO` not yet assessed in the 1.0 matrix.

| Area | Workflow | Expected release evidence | Status |
| --- | --- | --- | --- |
| Rules | Simple remap | UI creates rule, config maps source to target, reload clean | TODO #819 |
| Rules | Modifier/hyper remap | Modifier options persist and render correct Kanata output | TODO #819 |
| Rules | Tap-hold / dual-role | Timing/options persist; config emits correct dual-role behavior | TODO #819 |
| Rules | Home Row Mods | See [hrm-settings-release-qa.md](hrm-settings-release-qa.md) | MANUAL #804 #810 #811 |
| Rules | Layers and navigation | Layer controls update config, overlay labels, and runtime layer state | TODO #819 |
| Rules | Launcher/app/system/URL actions | UI actions persist and generated behavior matches expected action type | TODO #819 |
| Rules | Function/media keys | Pack/rule options emit correct media/function mappings | TODO #819 |
| Rules | Chords/sequences/tap dance/macros/text | Shipping options have config and persistence assertions | TODO #819 |
| Rules | App-specific mappings | App context persists and affects generated conditional config | TODO #819 |
| Packs | Install/uninstall common packs | Managed collections apply, snapshot, restore, and reload cleanly | TODO #815 |
| Packs | Vallack system | Managed HRM/nav config applies and restores without hang | FAIL #811 |
| Overlay | Base rendering | Geometry follows physical layout; labels follow logical keymap | TODO #818 |
| Overlay | Layer rendering | Layer switch updates colors, labels, and unmapped key style | TODO #818 |
| Overlay | Tap-hold/HRM labels | Primary labels, secondary labels, tint, and downstates are correct | MANUAL #810 #818 |
| Overlay | Sidebar tabs | Tabs open, close, and reflect selected key/layer state | TODO #818 |
| Overlay | Inspector/edit flows | Edits route to expected rule/config changes | TODO #818 |
| Menus | Menu bar actions | Commands trigger expected app/runtime behavior and logs are clean | TODO #818 |
| Menus | Emergency stop/resume | Runtime state changes are visible and reversible | TODO #815 #818 |
| Settings | Status/stability | Health state is accurate and does not fabricate blocking issues | PASS #812 |
| Settings | Permissions/setup | Signed release UX verified on real app build | MANUAL #747 |
| Settings | Keyboard layout/keymap | Geometry/labels update according to architecture rule | TODO #816 |
| Settings | Overlay preferences | Preferences persist and update overlay state | TODO #816 #818 |
| Settings | Advanced/runtime controls | Controls persist, route through helper/runtime, and log cleanly | TODO #816 #817 |
| Runtime | Config validate/apply/reload | `qa-keypath-release-smoke.sh` applies representative fixtures, validates with bundled Kanata, reloads, checks TCP, and restores config | PASS #815 |
| Runtime | Log review | `qa-keypath-log-gate.sh` captures recent app/CLI/Kanata/unified logs and fails on unclassified high-signal errors | PASS #817 |

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

- All `1.0 release` issues in the blocking table are closed or explicitly
  reclassified by the maintainer.
- Product matrix rows are no longer `TODO` for shipping features.
- Installed-app smoke passes on the intended build.
- Full safe suite and accessibility check pass.
- Signed release setup UX has been verified.
- Manual/Computer Use public release pass is complete.
- Log gate has no unclassified errors.
