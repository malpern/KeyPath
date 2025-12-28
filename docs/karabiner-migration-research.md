# Karabiner-Elements Migration Research

This document summarizes research on adoption challenges for Karabiner-Elements users migrating to KeyPath, and potential solutions.

## Executive Summary

KeyPath uses Kanata as its backend, which has a fundamentally different architecture than Karabiner-Elements. The biggest barriers to adoption are:

1. **No config import** - Users must manually recreate all rules
2. **No app-specific triggers** - Kanata lacks native per-app conditions
3. **Different mental model** - Layer-based vs condition-based paradigm
4. **Small rule library** - 11 presets vs thousands of community rules

## Current KeyPath Capabilities

### What Works Well

| Feature | Status | Notes |
|---------|--------|-------|
| Detect Karabiner conflicts | ✅ Full | `KarabinerConflictService` detects grabber, driver, services |
| Auto-disable Karabiner | ✅ Full | Kills grabber, disables via launchctl, creates marker file |
| Conflict resolution UI | ✅ Full | `WizardConflictsPage` with progressive disclosure |
| VirtualHID driver sharing | ✅ Full | Uses same Karabiner-DriverKit-VirtualHIDDevice |

### What's Missing

| Feature | Status | Impact |
|---------|--------|--------|
| Import Karabiner JSON | ❌ None | Critical - users must recreate everything |
| App-specific triggers | ❌ None | Critical - killer feature for power users |
| Complex rule translation | ❌ None | High - no condition→layer mapping |
| Community rule sharing | ❌ None | Medium - no import/export mechanism |
| Side-by-side trial | ❌ None | Low - must fully disable Karabiner |

## Architecture Differences

### Karabiner-Elements: Condition-Based

```json
{
  "type": "basic",
  "from": { "key_code": "j", "modifiers": { "mandatory": ["caps_lock"] } },
  "to": [{ "key_code": "down_arrow" }],
  "conditions": [
    { "type": "frontmost_application_if", "bundle_identifiers": ["^com\\.google\\.Chrome$"] }
  ]
}
```

**Mental model**: "When I press X in context Y, do Z"

### Kanata/KeyPath: Layer-Based

```lisp
(defalias
  vim (layer-toggle vim-mode))

(deflayer base
  caps @vim
  j    j)

(deflayer vim-mode
  caps _
  j    down)
```

**Mental model**: "Activate a layer, keys now have different meanings"

### Key Paradigm Differences

| Aspect | Karabiner | Kanata/KeyPath |
|--------|-----------|----------------|
| Triggers | Per-key conditions | Layer activation |
| App awareness | Native `frontmost_application_if` | External tool required |
| Complexity | Per-rule conditions | Global layer state |
| Config format | JSON | S-expressions (.kbd) |

## App-Specific Triggers: The Path Forward

Kanata explicitly delegates app-awareness to external tools. For macOS, the solution is:

### kanata-vk-agent

**Repository**: https://github.com/devsunb/kanata-vk-agent

A Rust tool that:
- Observes `frontmostApplication` via macOS APIs
- Sends virtual key presses to Kanata via TCP
- Triggers layer switches based on app bundle ID
- Supports input source awareness (JIS/multi-language)

```bash
# Example: activate layers for specific apps
kanata-vk-agent -p 5829 -b com.apple.Safari,org.mozilla.firefox,com.github.wez.wezterm
```

### Integration Requirements

| Task | Difficulty | Notes |
|------|-----------|-------|
| Bundle binary | Easy | Add to `/Library/KeyPath/bin/` |
| UI for app→layer mappings | Medium | Visual rule builder |
| Launch/manage daemon | Easy | Similar to Kanata daemon management |
| Config generation | Medium | Generate CLI arguments from UI |

### Existing KeyPath Infrastructure

KeyPath already has relevant pieces:
- `NSWorkspace.shared.frontmostApplication` (in `WindowManager.swift`)
- TCP communication with Kanata (`KanataTCPClient`)
- Layer management concepts in rule collections
- Daemon lifecycle management (`KanataDaemonManager`)

## Config Import Strategy

### Phase 1: Simple Modifications

Karabiner's "Simple Modifications" map directly to KeyPath's Simple Mods:

```json
// Karabiner simple_modifications
{ "from": { "key_code": "caps_lock" }, "to": [{ "key_code": "escape" }] }
```

```lisp
;; KeyPath equivalent
(deflayermap (base)
  caps esc)
```

**Implementation**:
1. Parse `~/.config/karabiner/karabiner.json`
2. Extract `profiles[].simple_modifications`
3. Convert to KeyPath Simple Mods format
4. Present UI for review before import

### Phase 2: Basic Complex Modifications

Rules without conditions can be converted:

```json
// Karabiner: Caps+HJKL = Arrow keys
{
  "from": { "key_code": "h", "modifiers": { "mandatory": ["caps_lock"] } },
  "to": [{ "key_code": "left_arrow" }]
}
```

```lisp
;; KeyPath: Caps activates nav layer
(defalias nav (layer-toggle nav))
(deflayer base caps @nav)
(deflayer nav h left)
```

### Phase 3: Conditional Rules (Requires kanata-vk-agent)

Rules with `frontmost_application_if` require the external agent:

```json
// Karabiner: Chrome-specific
{
  "conditions": [{ "type": "frontmost_application_if", "bundle_identifiers": ["Chrome"] }]
}
```

Would translate to:
1. Kanata layer definition
2. kanata-vk-agent config for Chrome → layer activation

### Unsupported Karabiner Features

| Feature | Karabiner | KeyPath Possibility |
|---------|-----------|---------------------|
| `frontmost_application_if` | Native | Via kanata-vk-agent |
| `device_if` | Native | Kanata has `defcfg` device filtering |
| `input_source_if` | Native | kanata-vk-agent supports this |
| `variable_if` | Native | Kanata has `defvar` |
| Mouse button remapping | Native | Limited in Kanata |
| `to_if_alone` / `to_if_held_down` | Native | Kanata `tap-hold` |
| `to_delayed_action` | Native | Kanata `macro` with delays |

## Rule Library Gap

### Current State

KeyPath's `SimpleModsCatalog` has **11 presets**:
- Caps Lock → Escape
- Caps Lock → Control
- Modifier swaps (Cmd, Option)
- F13-F15 → Media keys
- Backspace ↔ Delete

### Karabiner Community

https://ke-complex-modifications.pqrs.org/ has **thousands** of rules including:
- Vim bindings (multiple variants)
- IDE-specific shortcuts
- Mouse keys
- Window management
- App launchers
- International keyboard layouts

### Expansion Strategy

1. **Identify top 50 Karabiner rules** by popularity/downloads
2. **Convert to KeyPath rule collections**
3. **Categorize**: Vim, IDE, Productivity, Media, Gaming
4. **Enable community sharing** (future)

## User Experience Recommendations

### Migration Wizard Concept

```
┌─────────────────────────────────────────────────┐
│  Import from Karabiner-Elements                 │
├─────────────────────────────────────────────────┤
│  Found: ~/.config/karabiner/karabiner.json      │
│                                                 │
│  ✅ 12 Simple Modifications     [Import All]   │
│  ⚠️  8 Complex Rules            [Review...]    │
│  ❌ 3 App-Specific Rules        [Requires...]  │
│                                                 │
│  [Skip Import]              [Continue →]       │
└─────────────────────────────────────────────────┘
```

### Documentation Needs

1. **"Karabiner User's Guide to KeyPath"**
   - Concept mapping (conditions → layers)
   - Common rule translations
   - Feature parity matrix

2. **Video walkthrough**
   - Live migration of a real config
   - Before/after comparison

## Implementation Priority

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P0 | Simple mods import | 1 week | High - easy wins |
| P0 | kanata-vk-agent integration | 2 weeks | Critical - unblocks power users |
| P1 | Complex rule conversion | 2 weeks | High - covers most users |
| P1 | Expand rule catalog | 1 week | Medium - discoverability |
| P2 | Migration wizard UI | 1 week | Medium - polish |
| P2 | Documentation | 3 days | Medium - reduces support |

## Related Files

### Conflict Detection
- `Sources/KeyPathAppKit/Services/KarabinerConflictService.swift`
- `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardConflictsPage.swift`
- `Sources/KeyPathAppKit/InstallationWizard/Core/KarabinerComponentsStatusEvaluator.swift`

### Simple Mods System
- `Sources/KeyPathAppKit/Services/SimpleModsParser.swift`
- `Sources/KeyPathAppKit/Services/SimpleModsWriter.swift`
- `Sources/KeyPathAppKit/Services/SimpleModsCatalog.swift`
- `Sources/KeyPathAppKit/UI/SimpleModsView.swift`

### Layer/TCP Infrastructure
- `Sources/KeyPathAppKit/Services/KanataTCPClient.swift`
- `Sources/KeyPathAppKit/Services/LayerKeyMapper.swift`

## External References

- [Kanata GitHub](https://github.com/jtroo/kanata)
- [kanata-vk-agent](https://github.com/devsunb/kanata-vk-agent) - macOS app-aware layer switching
- [Karabiner Complex Modifications](https://ke-complex-modifications.pqrs.org/) - Community rules
- [Kanata Configuration Guide](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)

## Conclusion

Migration from Karabiner-Elements is achievable but requires investment in:

1. **Config import tooling** - Parse and convert Karabiner JSON
2. **App-specific triggers** - Integrate kanata-vk-agent
3. **Rule library expansion** - Port popular community rules
4. **User education** - Document the paradigm shift

The technical path is clear. The main question is prioritization against other KeyPath roadmap items.
