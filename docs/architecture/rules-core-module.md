# Rules Core Module

`KeyPathRulesCore` contains pure rule and configuration domain types that are
shared by the app, CLI, snapshots, and tests without requiring `KeyPathAppKit`.

The module owns:

- rule collection models and display-style configuration
- key actions, key mappings, mapping behavior, and custom rules
- home-row, sequence, chord-group, launcher, auto-shift, and key-repeat config
- system-action metadata used to identify and render rule actions
- URL and text-to-kanata formatting helpers used by those models

The module intentionally does not own:

- SwiftUI/AppKit views or view models
- stores, managers, file watchers, or runtime coordinators
- Kanata full-config rendering and deduplication
- physical-layout derivation and keyboard geometry

Those boundaries keep the core target independent of AppKit, Sparkle, and the
installer/runtime stack. Tests that exercise only these models should live in
`KeyPathRulesCoreTests`; tests that need Kanata rendering, device discovery, UI
helpers, or persistence should remain in `KeyPathTests`.
