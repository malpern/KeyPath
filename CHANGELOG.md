# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic
Versioning once public release tags are established.

## [Unreleased]

## [1.0.0] - 2026-06-13

First stable public release.

### Security

- The bundled Kanata engine is compiled without the `cmd` feature: the root
  daemon physically cannot execute shell commands regardless of config
  contents — a stronger guarantee than the previous opt-in toggle. Hand-written
  `(cmd …)` actions now fail validation with a clear message; use the
  consent-gated **Script Execution** actions (which run as the user, not root)
  instead.

### Added

- 22 ready-to-use rule packs (Home Row Mods, Caps Lock remapping, Vim & Neovim
  navigation, Quick Launcher, Window Snapping, Auto Shift, Numpad/Symbol/Function
  layers, and more), each installable in one click from the Gallery with a live
  preview.
- Live keyboard overlay showing per-layer key behavior in real time, including
  tap-hold and chord behavior.
- The Mapper: visual remap builder for tap/hold/shift/combo behaviors, multi-tap,
  app-specific overrides, system actions, app launches, and layer jumps.
- QMK (`keymap.c`) and Karabiner (`karabiner.json`) import. QMK import is
  comprehensive; Karabiner import covers simple key-to-key remaps.
- Mapper/overlay support for optional per-key shifted output customization:
  `Shift + key` can send a separate output from the tap/default output for
  global keystroke mappings.
- Release-governance docs: `SECURITY.md`, `CODE_OF_CONDUCT.md`, and this
  changelog.

### Changed

- Shifted-output editing is intentionally constrained to global keystroke
  mappings and is disabled for app-specific mappings, system actions, URLs, and
  advanced hold/combo/tap-dance behaviors.

### Known limitations

- Home Row Layer Toggles in "Toggle" mode assume the layers they point at are
  also enabled; if not, those keys no-op on hold (the rest of the keyboard is
  unaffected).
- Karabiner import covers simple remaps only — tap-hold, layer/variable, and
  device/app-conditional rules are not translated yet and are skipped with a
  summary.
- Changing the Leader key is done in the Rules tab; the CLI and hand-edited
  config files don't yet propagate Leader-key changes.

## [0.0.0-internal]

### Notes

- Pre-public-release baseline. Historical internal changes prior to OSS launch
  are tracked in git history and project documentation.
