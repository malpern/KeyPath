# KeyPath UI Release QA

This checklist is the product-wide UI pass for 1.0 release candidates. It
complements deterministic snapshot tests and the installed-app smoke/log gate.
Use it after deploying the intended build to `/Applications/KeyPath.app`.

## Cadence

| When | Scope | Evidence |
| --- | --- | --- |
| PRs touching UI | Focused Swift/UI tests, snapshots when deterministic, `check-accessibility.py`, and `check-computer-use-readiness.py` when automation IDs change. | PR validation notes. |
| Release candidate | Installed app plus the Computer Use matrix below. Run the installed-app smoke and log gate before and after risky manual flows. | Completed checklist, log gate output, issue links. |
| Public release prep | Full release-candidate pass plus signed setup UX from #747. | Release notes or issue closeout comment. |

## Baseline Commands

```bash
python3 Scripts/check-accessibility.py
python3 Scripts/check-computer-use-readiness.py
KEYPATH_SNAPSHOTS=1 swift test --filter 'ScenarioSnapshotTests|HardViewSnapshotTests'
./Scripts/qa-keypath-release-smoke.sh
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
./Scripts/qa-keypath-log-gate.sh
```

For signed release-candidate builds, run `verify-installed-app.sh` without the
relaxed notarization and stapling flags.

## Computer Use Matrix

Legend: `SNAPSHOT` deterministic screenshot test covers the visual state,
`CU` requires Computer Use or manual installed-app interaction, and `SCRIPT`
has a shell/CLI release gate.

| Area | Workflow | Expected UI behavior | Config/runtime/log effect | Coverage |
| --- | --- | --- | --- | --- |
| Overlay | Base layer | Overlay renders selected physical layout geometry and logical keymap labels; health indicator is not showing false failures. | Installed CLI status reports operational; log gate has no unclassified overlay or runtime errors. | SNAPSHOT `testLiveKeyboardOverlayBase`, `testOverlay_BaseLayer_HJKLShowLetters`; CU release check. |
| Overlay | Layer rendering | Switching layers updates key labels, colors, and unmapped-key style without text overlap. | Generated config includes layer mappings; reload succeeds. | SNAPSHOT `testOverlay_NavLayer_HJKLArrows`, `testOverlay_VimNavLayer`; SCRIPT `qa-keypath-release-smoke.sh`; CU release check. |
| Overlay | Tap-hold and HRM labels | Tap labels remain primary; small hold/modifier/layer subtitles are visible and tinted correctly. | HRM/Vallack config validates and reloads; no overlay label errors. | SNAPSHOT `testOverlay_WithTapHoldIdleLabels`; HRM QA matrix; CU release check. |
| Overlay | Downstates | Pressed/held/selected key states are visually distinct and settle to one resolved output after ambiguity. | Simulator/installed logs do not show unresolved or conflicting decisions. | SNAPSHOT keycap downstate tests; CU/manual physical-key check. |
| Overlay | Sidebar tabs | Inspector opens/closes, tab selection is visible, and selected key/layer context stays coherent. | Editing paths route to expected rules or settings notifications. | SNAPSHOT `testOverlay_WithInspectorOpen`, inspector tab snapshots; CU release check. |
| Overlay | Layer picker | Layer selection, layer creation, and user-layer deletion are discoverable without hover-only automation. | Layer selection changes overlay state; user-layer deletion routes through the overlay layer-management path. | CU release check; source contract `check-computer-use-readiness.py`. |
| Mapper | Key action types | Plain remap, hyper/modifier, app launch, system action, recording, and shifted-output rows render with expected labels/icons. | Saved mappings produce matching generated config or app action records. | SNAPSHOT mapper pair suite; config tests from #819; CU release check for one edit flow. |
| Mapper | Advanced action variants | Dual-role, tap-dance, macro/text-like raw output, and app-specific rows expose stable editor targets or remain covered below UI by model/config tests. | Saved behavior renders expected Kanata fragments through the existing per-rule option tests. | CU source contract for editor targets; CONFIG/PERSISTENCE tests from #819. |
| Packs | Pack detail variants | Major pack detail views render current copy, install state, and rule-specific controls without stale HRM text. | Install/uninstall applies, snapshots, restores, and reloads. | SNAPSHOT pack detail suite; SCRIPT `qa-keypath-release-smoke.sh`; CU release check for one install/uninstall. |
| Settings | General tab | Overlay/key label/capture/recording/log/import controls are visible and accessible. | Preferences persist and runtime arguments reflect config-affecting settings. | SNAPSHOT `testGeneralSettingsTabView`; tests from #816; CU release check. |
| Settings | Repair/Remove tab | Destructive controls are visible but not triggered during routine QA; simulator/backups affordances are visible. | No destructive action is run unless explicitly approved; log gate stays clean. | SNAPSHOT `testRepairSettingsTabView`; CU non-destructive presence check. |
| Settings | Status tab | Health, active rules, and service state match installed CLI/runtime state. | `keypath-cli status` and `verify-installed-app.sh` agree with the UI. | CU release check; SCRIPT `verify-installed-app.sh`. |
| Menus | Menu bar actions | Settings opens from the menu, overlay show/hide works, and menu items are discoverable. | Logs show expected settings/overlay actions without errors. | MANUAL release check; legacy Peekaboo suite `13-menu-bar.sh` as optional fallback. |
| Menus | Emergency stop/resume | Stop/resume is visible and reversible only in a dedicated runtime QA pass. | Runtime state changes and recovers; reload/TCP readiness restored; logs classified. | MANUAL release check; SCRIPT log gate. |

## Computer Use Boundary

Computer Use is the preferred release-QA driver for stable, AX-visible app
windows and controls. The source-level contract in
`Scripts/check-computer-use-readiness.py` intentionally covers the UI surfaces
that release QA expects Computer Use to drive:

- overlay keycaps, layer indicator, sidebar tabs, layer picker rows, launchers,
  and representative inspector entry points
- Rules summary rows, Custom Rules quick-add/list rows, app-specific rows,
  chord groups, sequences, launcher editor, mapping behavior variants, HRM, and
  Home Row Layer Toggles
- Settings status, General, Advanced/Repair, script-execution controls, virtual
  keys, and Pack Detail top-level/quick-setting controls

Some audited surfaces are intentionally outside the Computer Use source
contract:

- Live physical-key downstates and ambiguity resolution require real keyboard
  timing and are release-candidate manual checks, backed by snapshots and logs.
- Menu bar/status-item commands can be checked manually or with the legacy
  Peekaboo fallback because a status item is not a stable AX window surface.
- Destructive installer/runtime actions are presence-checked by UI automation
  but only executed in an explicit runtime QA pass.
- URL/deep-link surfaces such as `keypath://layer/...` and
  `keypath://fakekey/...` are script/manual checks rather than Computer Use
  discovery targets.

## Computer Use Notes

- Prefer non-destructive checks for routine release QA. Do not click uninstall,
  reset, or helper removal controls unless the release task explicitly calls for
  that flow.
- Each checked workflow should record the UI result, config/runtime evidence,
  and log-gate result in the relevant release issue or PR.
- If Computer Use cannot attach to the menu-bar app because no AX-visible window
  exists, record that explicitly and fall back to installed CLI, logs, snapshots,
  and a manual visual check.
- When adding a new CU-targeted control, update
  `Scripts/check-computer-use-readiness.py` with the stable identifier, label,
  value, or row action that release QA depends on.
