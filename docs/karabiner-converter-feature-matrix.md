# Karabiner JSON Converter — Feature Matrix & Gap Analysis

This document maps every Karabiner-Elements JSON feature to its Kanata equivalent and KeyPath UI support status. It serves as the scoping reference for the Karabiner JSON → Kanata converter (GitHub issue #202).

## Background

- **Karabiner-Elements** is a condition-based remapper: "When I press X in context Y, do Z"
- **Kanata** is a layer-based remapper: "Activate a layer, keys have different meanings"
- **KeyPath** generates Kanata `.kbd` config and adds app-awareness via TCP virtual keys

The converter outputs valid Kanata `.kbd` config. Features with KeyPath UI support can also be imported as editable rule collections. Features without UI support are emitted as raw Kanata config that works immediately — the user just can't edit them visually in KeyPath yet.

## Architecture Differences

| Aspect | Karabiner | Kanata / KeyPath |
|--------|-----------|------------------|
| Config format | JSON | S-expressions (.kbd) |
| Paradigm | Per-key conditions | Layer activation |
| App awareness | Native `frontmost_application_if` | Not in Kanata core (by design); KeyPath adds via `defvirtualkeys` + TCP `ActOnFakeKey` + `NSWorkspace` observer |
| Complexity model | Per-rule conditions | Global layer state + `switch` expressions |

## Feature Matrix

### Input Triggers (`from`)

| Karabiner Feature | Kanata Support | KeyPath UI |
|---|---|---|
| `key_code` (single key) | 1:1 — `deflayer` | Have |
| `key_code` + `modifiers.mandatory` | 1:1 — `deflayer` on layer, or `defoverrides` | Have |
| `key_code` + `modifiers.optional` | 1:1 — passthrough modifiers | Have |
| `consumer_key_code` (media keys) | 1:1 — media key names in `defsrc` | Have |
| `pointing_button` (mouse button input) | Linux only, not macOS | Don't have |
| `simultaneous` (chord) | 1:1 — `defchords` | Have (chord builder) |
| `any` (wildcard match) | Partial — `_` passthrough | Have |

### Output Actions (`to`)

| Karabiner Feature | Kanata Support | KeyPath UI |
|---|---|---|
| `key_code` output | 1:1 — `deflayer` / `defalias` | Have |
| `key_code` + `modifiers` | 1:1 — modifier prefix in alias | Have |
| `consumer_key_code` output | 1:1 | Have |
| `pointing_button` (mouse click output) | 1:1 — `mlft`, `mrgt`, `mmid`, etc. | Don't have (#181) |
| `shell_command` | 1:1 — `(cmd ...)`, plus `cmd-output-keys` (Kanata has MORE) | Have — `LauncherTarget.script` via `push-msg "script:..."` |
| `mouse_key` (cursor movement) | 1:1+ — `movemouse-*`, `movemouse-accel-*` (Kanata is MORE capable) | Don't have (#181) |
| `sticky_modifier` | 1:1 — `(one-shot ...)` with 5 variants | Partial — used internally for layer activation (tap-to-toggle, chained layers); not exposed as standalone user behavior (#179) |
| `set_variable` | 1:1 — `defvar` / layer state | Have (implicit via layers) |
| `select_input_source` | Not in Kanata | Don't have |
| `set_notification_message` | Via `push-msg "notify:..."` (KeyPath Action URI) | Have |
| `software_function` (open app) | Via `(cmd open -a ...)` or `push-msg "launch:..."` | Have (launcher UI) |
| `software_function` (sleep system) | Via `(cmd pmset sleepnow)` | Don't need |
| `send_user_command` | Not directly equivalent | Don't need (niche) |
| `unicode` output | 1:1 — `(unicode ...)` / `(unicode U+XXXX)` | Don't have (#183) |
| `lazy` modifier (don't send until next key) | Partial — different mechanism | Don't have |
| `hold_down_milliseconds` | Via `(macro ... $delay ...)` | Don't have |

### Temporal Behaviors (`to_if_*` variants)

| Karabiner Feature | Kanata Support | KeyPath UI |
|---|---|---|
| `to` + `to_if_alone` (dual-role) | 1:1 — `tap-hold` (4 variants; Kanata has MORE) | Have (dual-role editor) |
| `to_if_held_down` (fire while held) | Partial — `tap-hold` fires once; approximate with macro | Have (tap-hold) |
| `to_after_key_up` (on key release) | Partial — `on-release` in some contexts | Don't have |
| `to_delayed_action` (timed branching) | Approximate via `fork` / `switch` / macro with delays | Don't have |
| `to_if_other_key_pressed` | Approximate via `tap-hold-release-keys` | Have (HRM split-hand) |

### Conditions (Contextual Filtering)

| Karabiner Feature | Kanata Support | KeyPath UI |
|---|---|---|
| `frontmost_application_if` / `unless` | **Not in Kanata core** (jtroo delegates to external tools by design) | **Have** — `defvirtualkeys` + `switch` + TCP `ActOnFakeKey` + `NSWorkspace` observer |
| `device_if` / `unless` (per-keyboard) | 1:1 — `macos-dev-names-include/exclude` (name-based, not VID/PID) | Don't have (#203) |
| `variable_if` / `unless` | 1:1 — `defvar` + `switch` | Have (implicit via layers) |
| `keyboard_type_if` (ANSI/ISO/JIS) | Partial — device name filtering | Don't need |
| `input_source_if` (language/IME) | Not in Kanata | Don't have — but `InputSourceDetector` monitors Japanese input modes for overlay display; adjacent infrastructure exists |
| `expression_if` (time-based math) | Not in Kanata | Don't need (very niche) |
| `event_changed_if` | Not in Kanata | Don't need (very niche) |

### Mouse-Specific Manipulator Types

| Karabiner Feature | Kanata Support | KeyPath UI |
|---|---|---|
| `mouse_motion_to_scroll` | Not supported | Don't have |
| `mouse_basic` (axis flip/swap/discard) | Not supported | Don't have |

### Profile & Device Scoping

| Karabiner Feature | Kanata Support | KeyPath UI |
|---|---|---|
| Multiple profiles | Multiple `.kbd` files / `lrld-next` cycling | Don't have |
| Per-device `simple_modifications` | Global device filtering only (not per-rule) | Don't have (#203) |
| Per-device `fn_function_keys` | Same limitation | Don't have |

## Summary Scorecard

The converter has two independent output tiers for each feature:

- **Kanata config**: Does the converter produce working `.kbd` output? (The rule *functions* after conversion)
- **KeyPath UI**: Can the user visually edit the converted rule in KeyPath? (Or is it raw config they'd need to hand-edit?)

### Full support: converts AND editable in KeyPath

| Category | Kanata | KeyPath UI | How it maps |
|---|---|---|---|
| Simple key remaps | 100% | Yes | `deflayer` mappings → list/table collections |
| Dual-role / tap-hold | 100% | Yes | `tap-hold` (4 variants) → dual-role editor. Kanata has MORE variants than Karabiner |
| Chords (simultaneous) | 100% | Yes | `defchords` → chord builder |
| Macros (key sequences) | 100% | Yes | `macro` → macro editor |
| App-specific rules | 100% | Yes | `defvirtualkeys` + `switch` → AppKeymap entries. KeyPath's native TCP architecture handles this |
| Layer/variable conditions | 100% | Yes | `deflayer` + `layer-toggle` → layer system |
| Shell commands | 100% | Yes | `push-msg "script:..."` → `LauncherTarget.script` in launcher grid |
| App launching | 100% | Yes | `push-msg "launch:..."` → `LauncherTarget.app` in launcher grid |
| URL opening | 100% | Yes | `push-msg "open:..."` → `LauncherTarget.url` in launcher grid |
| Notifications | 100% | Yes | `push-msg "notify:..."` → Action URI system |

### Converts to working Kanata config, but NO KeyPath UI to edit

These features will **work immediately** after conversion — the user just can't visually edit them in KeyPath. They'd need to hand-edit the `.kbd` file to change them.

| Category | Kanata | KeyPath UI gap | Issue |
|---|---|---|---|
| Mouse click output (`pointing_button`) | 100% — `mlft`, `mrgt`, `mmid` | No UI to assign mouse clicks as rule output | #181 |
| Mouse cursor movement (`mouse_key`) | 100% — `movemouse-*`, `movemouse-accel-*` | No UI to configure mouse movement | #181 |
| One-shot modifiers (`sticky_modifier`) | 100% — `one-shot` (5 variants) | Used internally for layers; no standalone "make Shift one-shot" UI | #179 |
| Unicode output | 100% — `(unicode ...)` | No UI to assign unicode characters as output | #183 |
| Global key overrides | 100% — `defoverrides` / `defoverridesv2` | No UI for global modifier combo remapping | #180 |
| Device filtering (`device_if`) | ~80% — `macos-dev-names-include/exclude` | Used internally for VirtualHID loop prevention only; no per-keyboard UI | #203 |
| Delayed actions (`to_delayed_action`) | ~70% — approximate via `fork`/`switch`/macro | No UI | — |
| On-release actions (`to_after_key_up`) | Partial — `on-release-fakekey` used internally | No UI for user-defined release actions | — |
| `lazy` modifier | Partial | No UI | — |
| `hold_down_milliseconds` | Via `macro` delays | No UI | — |

### Not convertible (neither Kanata nor KeyPath support)

| Category | Why | Prevalence |
|---|---|---|
| Mouse axis manipulation (`mouse_basic`) | Not in Kanata | Very niche |
| Mouse-to-scroll (`mouse_motion_to_scroll`) | Not in Kanata | Niche |
| Input source switching (`select_input_source`) | Not in Kanata | Niche (infrastructure exists: `InputSourceDetector` monitors Japanese input modes for overlay) |
| Expression-based conditions (`expression_if`) | Not in Kanata | Very niche |
| `event_changed_if` | Not in Kanata | Very niche |
| Mouse button input interception | macOS limitation (Linux only in Kanata) | Niche |

### Conversion fidelity estimate

| Metric | Estimate |
|---|---|
| Rules that produce **working Kanata config** | **~95%** of typical configs |
| Rules that are also **editable in KeyPath UI** | **~75-80%** of typical configs |
| Rules that **cannot be converted at all** | **<5%** (mouse axis, input source, expression conditions) |

The gap between "works" and "editable" is the key insight: most converted configs will function immediately, even if some rules require hand-editing the `.kbd` file until KeyPath adds UI for those features.

## KeyPath's App-Awareness Architecture

KeyPath solves app-specific rules without kanata-vk-agent, using a native Swift implementation:

```
┌─────────────────────────────────────────────────┐
│ KeyPath (Swift)                                 │
│ - NSWorkspace detects frontmost app             │
│ - Maps bundle ID → virtual key name             │
│ - Sends TCP: ActOnFakeKey Press/Release         │
└──────────────┬──────────────────────────────────┘
               │ TCP (ActOnFakeKey)
┌──────────────▼──────────────────────────────────┐
│ Kanata                                          │
│ - defvirtualkeys (vk_safari, vk_vs_code, ...)   │
│ - switch expressions branch on virtual key state│
└─────────────────────────────────────────────────┘
```

**Generated `keypath-apps.kbd`:**
```lisp
(defvirtualkeys
  vk_safari XX
  vk_vs_code XX
)

(defalias
  kp-j (switch ((input virtual vk_safari)) down break
               ((input virtual vk_vs_code)) down break
               () j break)
)
```

This means Karabiner's `frontmost_application_if` rules convert into:
1. An `AppKeymap` entry in KeyPath's `AppKeymaps.json`
2. Virtual key + switch expression in `keypath-apps.kbd`
3. Runtime context switching via `AppContextService`

Key files: `AppContextService.swift`, `AppConfigGenerator.swift`, `AppKeyMapping.swift`, `AppKeymapStore.swift`

## Kanata Features With No Karabiner Equivalent

These are bonus features the converter could suggest to users migrating from Karabiner:

| Kanata Feature | Description |
|---|---|
| `caps-word` / `caps-word-custom` | Smart Caps Lock that deactivates at word boundaries |
| `dynamic-macro-record` / `play` | Record and replay key sequences at runtime (like Vim's `q`) |
| `cmd-output-keys` | Execute shell command, type stdout as keystrokes |
| `deftemplate` | Reusable config templates to reduce repetition |
| `defaliasenvcond` | Environment-conditional aliases (per-machine config) |
| `movemouse-accel-*` | Accelerating mouse cursor with configurable ramp |
| `tap-hold-release-keys` | Split-hand-aware tap-hold (smarter than Karabiner's `to_if_alone`) |

## Conversion Strategy

### Tier 1: KeyPath-editable rules (works + editable)
Rules that map to KeyPath's UI models — imported as editable rule collections the user can modify visually:
- Simple remaps → list/table collections
- Tap-hold / dual-role → dual-role editor
- Chords → chord builder
- App-specific rules → AppKeymap entries (via VK+TCP architecture)
- Macros → macro editor
- Shell commands → launcher `.script` targets
- App/URL launching → launcher `.app` / `.url` targets

### Tier 2: Raw Kanata passthrough (works, not editable)
Rules that Kanata supports but KeyPath has no UI for — emitted as raw `.kbd` config that **functions immediately** but requires hand-editing to modify:
- Mouse keys (`movemouse-*`, mouse click output)
- One-shot modifiers (`one-shot`)
- Unicode output (`unicode`)
- Global overrides (`defoverrides`)
- Device filtering (`macos-dev-names-include/exclude`)

The converter should clearly label these in the output with comments like:
```lisp
;; [KeyPath: raw Kanata — no UI editor yet]
;; Converted from: Karabiner mouse_key rule
(defalias mouse-up (movemouse-accel-up 1 1000 1 5))
```

### Tier 3: Flagged as unsupported (cannot convert)
Rules that neither Kanata nor KeyPath can handle — shown in the conversion report with an explanation:
- Mouse axis manipulation (`mouse_basic`, `mouse_motion_to_scroll`)
- Input source switching (`select_input_source`)
- Expression-based time conditions (`expression_if`)

### Converter UI
The conversion report should show a side-by-side diff with clear tier indicators:
- Green: Tier 1 — fully converted and editable in KeyPath
- Yellow: Tier 2 — converted to working Kanata config, hand-edit only
- Red: Tier 3 — could not be converted, with explanation of why

## Related Documents

- [Karabiner Migration Research](karabiner-migration-research.md) — earlier research on migration barriers
- [ADR-027: App-Specific Keymaps](adr/adr-027-app-specific-keymaps.md) — architecture for app-aware rules
- [ADR-023: No Config Parsing](adr/adr-023-no-config-parsing.md) — why we generate, never parse, Kanata config
- [Action URI System](ACTION_URI_SYSTEM.md) — `push-msg` based actions for launch, notify, etc.
- [Rule Collection Pattern](architecture/rule-collection-pattern.md) — how rules are organized in KeyPath
- [GitHub Issue #202](https://github.com/malpern/KeyPath/issues/202) — Karabiner converter tracking issue

## Open Questions

1. **kanata-vk-agent vs. KeyPath native**: KeyPath's `defvirtualkeys` + TCP approach is arguably cleaner than bundling kanata-vk-agent (keeps everything in one process, no third-party Rust binary). Should we standardize on KeyPath's native approach for all app-awareness features?
2. **Device filtering UX**: Karabiner uses VID/PID, Kanata uses device names. How do we bridge this for the converter? Auto-detect connected devices and offer a picker?
3. **Community rule import**: Karabiner has thousands of community rules at ke-complex-modifications.pqrs.org. Should the converter also handle importing from that format?
