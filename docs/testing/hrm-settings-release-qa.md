# Home Row Mods Settings Release QA

This plan codifies the deeper Home Row Mods settings pass without adding a nightly
or weekly automation job. Run it on demand for release candidates, public release
prep, or after changes to HRM settings, overlay labels, rule collections, pack
install, config generation, or the installed CLI.

## Cadence

| When | Check | Owner | Status |
| --- | --- | --- | --- |
| Every PR touching HRM logic | Focused Swift tests for mapping generation, overlay label resolution, config rendering, and pack/config persistence. | Developer | ✅ Active |
| Release candidate | `Scripts/qa-hrm-settings-smoke.sh` against `/Applications/KeyPath.app/Contents/MacOS/keypath-cli`, followed by installed-app verification. | Release driver | ✅ Active |
| Public release prep | Manual Computer Use pass through the HRM settings UI using the matrix below, plus unified log review. | Release driver | ✅ Active |
| Nightly/weekly automation | Schedule the same smoke plus a small Computer Use subset in a stable macOS runner. | Future | 🚧 Future enhancement |

## On-Demand Installed-App Smoke

```bash
./Scripts/qa-hrm-settings-smoke.sh
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

For release-candidate builds that are notarized/stapled, run the installed-app
verification without the relaxed environment variables:

```bash
./Scripts/verify-installed-app.sh
```

The HRM smoke script intentionally uses the installed CLI, backs up
`~/.config/keypath`, mutates only the Home Row Mods collection, applies/reloads
through the app path under test, asserts generated Kanata output, and restores
the original config in an exit trap.

## Manual Computer Use Matrix

Legend: ✅ passed, ❌ failed with issue, 🚧 blocked, future, not exposed, or needs
retest after a fix. Current status reflects the deeper installed-app pass run on
2026-06-07.

| Area | Feature or combination | Expected behavior | State |
| --- | --- | --- | --- |
| Entry point | Open Home Row Preferences from pack detail and overlay settings | Sheet opens, focus lands in sheet, Done closes it | ✅ |
| Hold behavior | Modifiers mode | Hold labels are modifier glyphs; config emits modifier HRM actions | ✅ |
| Hold behavior | Layers mode | UI and generated config emit layer hold/toggle actions | ✅ |
| Hold behavior | Switch modifiers -> layers -> modifiers | UI, pack detail, and generated config converge on the final selection | ✅ |
| Timing | Shared timing slider | Slider changes tap/hold preference and generated timings | ✅ |
| Timing | Raw values view | Numeric/raw timing values match slider state and remain editable if exposed | ✅ |
| Timing | Adjust independently disclosure | Per-finger and per-key controls reveal/collapse without losing values | ✅ |
| Timing | Pinky/ring/middle/index offsets | Offset changes affect corresponding keys only | ✅ |
| Timing | Quick tap checkbox | Enables/disables quick-tap term and generated tap window addition | ✅ |
| Timing | Fast typing protection | Enables/disables `tap-hold-require-prior-idle` in generated config | ✅ |
| Opposite-hand activation | Off | UI selection sticks; config omits `defhands` and uses non-opposite-hand tap-hold | ✅ |
| Opposite-hand activation | On Press | UI selection sticks; config uses `tap-hold-opposite-hand` and `defhands` | ✅ |
| Opposite-hand activation | On Release | UI selection sticks; config uses `tap-hold-opposite-hand-release` and `defhands` | ✅ |
| Key selection | Both hands | Not exposed in the current Home Row Mods pack-detail UI; represented by default `enabledKeys` plus individual key chips | 🚧 Not current UI |
| Key selection | Left hand only | Not exposed in the current Home Row Mods pack-detail UI; use individual key chips to disable right-hand keys | 🚧 Not current UI |
| Key selection | Right hand only | Not exposed in the current Home Row Mods pack-detail UI; use individual key chips to disable left-hand keys | 🚧 Not current UI |
| Key selection | Custom individual keys | Toggle each key on/off; disabled keys are omitted from generated config | ✅ |
| Key selection | Re-enable disabled key with custom assignment | Re-enabled key preserves the user's previous assignment | ❌ [#809](https://github.com/malpern/KeyPath/issues/809) |
| Assignments | Modifier assignment popovers | Per-key modifier changes persist and update overlay labels | ✅ |
| Assignments | Existing layer assignment popovers | Per-key layer changes persist in config and pack detail chips | ✅ |
| Assignments | New Layer flow from key chip | Created layer is assigned to the selected key | ❌ [#804](https://github.com/malpern/KeyPath/issues/804) |
| Pack detail | Layer-mode copy and relationship text | Copy reflects layer-mode behavior and does not describe F as Command | ❌ [#805](https://github.com/malpern/KeyPath/issues/805) |
| Overlay | Idle overlay in modifiers mode | Primary alpha remains large; small modifier appears below; HRM keys use subtle tint | ✅ |
| Overlay | Idle overlay in layers mode | Primary alpha remains large; small layer label appears below; HRM keys use subtle tint | ❌ [#810](https://github.com/malpern/KeyPath/issues/810) |
| Overlay | Press/hold ambiguity | Simulator confirms resolved hold output after the ambiguity window; live overlay transient still needs physical keydown/manual automation coverage | 🚧 Manual overlay check |
| Persistence | Close/reopen sheet | All HRM settings survive sheet close/reopen | ✅ |
| Persistence | Relaunch KeyPath | All HRM settings survive app relaunch and overlay rebuild | ✅ |
| Pack interop | Ben Vallack system enabled | Vallack top-row mods and nav layer coexist with HRM UI conventions | ❌ [#811](https://github.com/malpern/KeyPath/issues/811) |
| Pack interop | Switch Vallack off | Previous HRM settings restore from snapshot | ❌ [#811](https://github.com/malpern/KeyPath/issues/811) |
| Logs | Unified logs during every apply/reload | No errors from config apply, helper routing, overlay label resolution, or Kanata reload | ✅ |

## Recent Findings To Keep In Scope

| Issue | Severity label | Regression check |
| --- | --- | --- |
| [#804](https://github.com/malpern/KeyPath/issues/804) | `1.0 release` | In layer mode, creating a new layer from HRM must assign the selected key to that layer. |
| [#805](https://github.com/malpern/KeyPath/issues/805) | `post-release` | HRM pack detail copy should reflect layer mode after switching from modifiers. |
| [#806](https://github.com/malpern/KeyPath/issues/806) | `post-release` | Hold-timing slider accessibility increment/decrement should change the value or stop exposing invalid actions. |
| [#809](https://github.com/malpern/KeyPath/issues/809) | `post-release` | Disabling and re-enabling an HRM key should preserve that key's custom assignment. |
| [#810](https://github.com/malpern/KeyPath/issues/810) | `1.0 release` | HRM layer mode overlay should show assigned layer labels, not alpha hold labels. |
| [#811](https://github.com/malpern/KeyPath/issues/811) | `1.0 release` | Installing Vallack system should apply managed HRM/nav config and uninstall should restore the prior HRM snapshot without hanging. |

## Log Review

During the public-release manual pass, capture the last few minutes of logs:

```bash
log show --last 10m --style compact --predicate 'process == "KeyPath" OR process == "keypath-cli" OR process == "kanata" OR subsystem CONTAINS "keypath"'
```

Treat errors or repeated warnings from HRM config generation, privileged helper
routing, Kanata reload, overlay label resolution, or accessibility interactions
as release-blocking until classified.
