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
~/.config/keypath/
  keypath-apps.kbd    ← Generated include; external edits are preserved
  keypath.kbd         ← User owns (optional, for power users)
  AppKeymaps.json     ← KeyPath-owned store (per-app keymaps)
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

### September 2026 save ownership update

App-specific mutations use `RuntimeCoordinator.mutateAppKeymaps` and the existing
`SaveCoordinator`. Under one configuration-directory admission, they read fresh
sources, validate the generated main/include together, stage all three files,
and keep the prior revision until runtime classification. Applied and pending
results commit; rejected, failed or cancelled attempts restore all three files.
Recovery reload results are retained separately from file recovery. A conflicting
external edit stops recovery and leaves the journal for diagnosis.

Main/include content must be reproducible before a visual edit is admitted. The
legacy include timestamp is ignored; other differences conservatively block the
edit. This includes hand-written content, formatting changes and source/generated
mismatches. The user-approved behavior is preservation plus an explanation that
explicit conversion with a backup is required. There is no automatic conversion.
Startup may create a missing include but does not overwrite differing content.

Kanata's live reload replaces the layout, clearing held virtual keys. After an
applied app save or successful recovery reload, AppContextService must reassert
the current app's virtual key even when its name is unchanged. Pending saves do
not claim an applied mapping. Deferred cooldown/transition reloads reacquire
configuration admission and refresh app context after success; service startup
also loads the persisted app sources. Recovery reloads run outside caller
cancellation and are awaited before releasing admission.

The broader reset-all and mixed global/app import journeys still compose multiple
operations. Global rule/preference/pack rollback and external-watch reconciliation
are separate remaining refactor work.
