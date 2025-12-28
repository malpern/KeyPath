# ADR-027: App-Specific Keymaps

## Status

Accepted

## Context

Users want different keyboard behaviors for different applications (e.g., vim-style navigation in Safari, different shortcuts in VS Code). This requires KeyPath to be "app-aware" while keeping Kanata as a pure, static decision engine.

## Decision

### Core Principle

**Kanata remains a pure, static decision engine. KeyPath owns all dynamic context.**

App awareness is modeled as external context input via TCP, not internal Kanata logic.

### Architecture

```
┌────────────────────────────────────────────────────────────┐
│  KeyPath (Swift)                                           │
│  - Detects frontmost app via NSWorkspace                   │
│  - Maps bundle ID → virtual key name                       │
│  - Sends TCP: ActOnFakeKey Press/Release                   │
└─────────────────────────┬──────────────────────────────────┘
                          │ TCP (ActOnFakeKey)
┌─────────────────────────▼──────────────────────────────────┐
│  Kanata                                                    │
│  - Static config with defvirtualkeys                       │
│  - switch expressions branch on virtual key state          │
└────────────────────────────────────────────────────────────┘
```

### Per-App Model (No Profiles v1)

Each app gets its own virtual key. No grouping/profiles in v1—users define per-app keymaps directly.

- **Virtual key limit**: 767 (more than sufficient)
- **VK naming**: Slugified app name (e.g., `vk_safari`, `vk_vs_code`)
- **Collision handling**: Append bundle ID hash on collision (e.g., `vk_safari_a1b2c3`)

### App Identification

- **Stored**: Bundle ID (e.g., `com.apple.Safari`)
- **Displayed**: App name in UI
- Bundle IDs are stable, portable, and unambiguous.

### Behavior Model

- **Overlay inheritance**: App-specific rules override specific keys; base layer remains active for everything else
- **Unmatched apps**: Silent passthrough—no virtual key pressed, base layer behavior only

### File Structure

```
~/Library/Application Support/KeyPath/
  keypath-apps.kbd    ← KeyPath owns (regenerated freely)
  keypath.kbd         ← User owns (optional, for power users)
```

**keypath-apps.kbd** (KeyPath-generated, valid Kanata):
```lisp
(defvirtualkeys
  vk_safari nop
  vk_vs_code nop
)

(defalias
  kp-j (switch ((input virtual vk_safari)) down
               ((input virtual vk_vs_code)) down
               () j)
  kp-k (switch ((input virtual vk_safari)) up
               ((input virtual vk_vs_code)) up
               () k)
)

(deflayer base
  @kp-j  @kp-k  l  ;; ... rest of layer
)
```

**keypath.kbd** (User-owned, optional):
```lisp
(include keypath-apps.kbd)

;; User's custom additions/overrides
(deflayer my-custom-layer
  @kp-j  @kp-k  x  y  z
)
```

### TCP Protocol

KeyPath uses existing `ActOnFakeKey` command (already implemented in Kanata):

```json
{"ActOnFakeKey": {"name": "vk_safari", "action": "Press"}}
{"ActOnFakeKey": {"name": "vk_safari", "action": "Release"}}
```

**App switch flow**:
```
Safari → VS Code:
1. Send: {"ActOnFakeKey": {"name": "vk_safari", "action": "Release"}}
2. Send: {"ActOnFakeKey": {"name": "vk_vs_code", "action": "Press"}}

VS Code → Unknown App (no keymap defined):
1. Send: {"ActOnFakeKey": {"name": "vk_vs_code", "action": "Release"}}
2. (nothing—silent passthrough)
```

### KeyPath UI Requirements

1. **App picker**: Select from installed applications
2. **Key mapping editor**: Define key → action mappings per app
3. **Mapping list**: View/edit/delete app configurations
4. **Config generation**: Write `keypath-apps.kbd` on save

### User Workflows

**UI-only user**:
- Uses KeyPath UI to configure app-specific keys
- Never sees .kbd files
- KeyPath generates complete working config

**Power user**:
- Creates `keypath.kbd` with `(include keypath-apps.kbd)`
- Writes custom layers using KeyPath-generated aliases (`@kp-j`)
- KeyPath regenerates `keypath-apps.kbd` without touching user's file

## Consequences

### Positive

- Kanata remains pure and static—no fork required for app awareness
- No config parsing by KeyPath (aligns with ADR-023)
- TCP protocol already implemented—no upstream work needed
- Users can define hundreds of app-specific keymaps (767 VK limit)
- Power users can hand-edit while UI users stay in KeyPath
- Generated config is valid Kanata—debuggable, shareable

### Negative

- No profile/grouping in v1—users must duplicate keymaps for similar apps
- Power users must use alias syntax (`@kp-j`) instead of direct keys
- Two-file model adds slight complexity

### Future Considerations

- **Profiles (v2)**: Group apps that share keymaps (e.g., "browsers")
- **Upstream context variables**: If Kanata adds `set-context` TCP command, migrate from virtual keys
- **Layer-specific app overrides**: Currently global; could add per-layer scoping

## References

- [ADR-023: No Config Parsing](adr-023-no-config-parsing.md)
- [Kanata TCP Protocol](../../External/kanata/docs/config.adoc)
- Strategy document: "App-Specific Rule Context in KeyPath"
