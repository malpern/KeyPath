---
layout: default
title: Action URI System
description: Trigger KeyPath actions via URI scheme and Kanata push-msg
---

# Action URI System

KeyPath supports a URI-based action system that enables:

1. **Kanata integration** - Trigger KeyPath actions from keyboard shortcuts via `push-msg`
2. **Deep linking** - External tools (Raycast, LeaderKey, Alfred) can invoke KeyPath actions
3. **Extensibility** - Add new action types without protocol changes

## Syntax Formats

KeyPath accepts **two equivalent syntaxes**:

| Context | Format | Example |
|---------|--------|---------|
| **Kanata config** | Shorthand (colon) | `launch:obsidian` |
| **Deep links** | Full URI | `keypath://launch/Obsidian` |

### Shorthand Syntax (Recommended for Configs)

```
[action]:[target][:[subpath]][?query=params]
```

- Use **lowercase** - resolves to Title Case in UI
- Colons separate action, target, and subpaths
- Query params use standard `?key=value` syntax

```lisp
(push-msg "launch:obsidian")           ;; → launches "Obsidian"
(push-msg "layer:nav:activate")        ;; → layer "nav", subpath "activate"
(push-msg "notify:?title=Saved")       ;; → notification with title
```

### Full URI Syntax (For Deep Links)

```
keypath://[action]/[target][/subpath...][?query=params]
```

Used by external tools (Terminal, Raycast, Alfred):

```bash
open "keypath://launch/Obsidian"
open "keypath://notify?title=Hello&body=World"
```

## Supported Actions

### `launch:{app}` / `keypath://launch/{app}`

Launch an application by name or bundle identifier.

**Kanata config (shorthand):**
```lisp
(push-msg "launch:obsidian")
(push-msg "launch:terminal")
(push-msg "launch:visual studio code")
```

**Deep link (full URI):**
```bash
open "keypath://launch/Obsidian"
open "keypath://launch/com.apple.Terminal"
```

**Resolution order:**
1. Bundle identifier lookup
2. Application name in `/Applications/`
3. Application name in `/System/Applications/`
4. Application name in `~/Applications/`

**Case handling:** Lowercase input (`obsidian`) resolves to Title Case (`Obsidian`) for display and lookup.

### `layer:{name}` / `keypath://layer/{name}`

Signal a layer change (for UI feedback, logging, or custom handlers).

**Kanata config (shorthand):**
```lisp
(defalias
  nav (multi (push-msg "layer:nav") (layer-switch nav))
)
```

**Subpaths:**
- `layer:nav:activate` - Activate layer
- `layer:nav:deactivate` - Deactivate layer
- `layer:nav:toggle` - Toggle layer

### `notify:` / `keypath://notify`

Show a system notification.

**Query parameters:**
- `title` - Notification title (required)
- `body` - Notification body (optional)
- `sound` - Play sound (default: true)

**Examples:**
```lisp
(push-msg "notify:?title=Saved&body=Configuration saved successfully")
```

```bash
open "keypath://notify?title=Hello&body=World"
```

### `fakekey:{name}` / `keypath://fakekey/{name}`

Trigger a virtual key press/release (for app-specific keymaps).

**Kanata config:**
```lisp
(push-msg "fakekey:vk_safari:press")
(push-msg "fakekey:vk_safari:release")
```

**Subpaths:**
- `fakekey:{name}:press` - Press virtual key
- `fakekey:{name}:release` - Release virtual key
- `fakekey:{name}:tap` - Press and release

## Integration Examples

### Raycast Integration

Create a Raycast command to switch KeyPath layers:

```bash
#!/bin/bash
open "keypath://layer/vim"
```

### Alfred Workflow

Create an Alfred workflow action:

```
keypath://launch/{query}
```

### Kanata Layer Switching

Use in your Kanata config for layer switching with UI feedback:

```lisp
(defalias
  nav (multi 
    (push-msg "layer:nav:activate")
    (layer-switch nav)
  )
)
```

## Error Handling

If an action fails (e.g., app not found), KeyPath logs an error but doesn't crash. Invalid URIs are logged and ignored.

## Security

Action URIs are only processed from:
- Local Kanata processes (via `push-msg`)
- Local system processes (via `open` command)

No network access is required or used.

## Advanced Usage

### Custom Action Handlers

Power users can extend the action system by modifying KeyPath's source code. See the `ActionDispatcher` class for implementation details.

### Query Parameter Encoding

URL-encode special characters in query parameters:

```bash
open "keypath://notify?title=Hello%20World&body=Test%20message"
```

## Troubleshooting

### Actions not working

1. Check KeyPath is running
2. Verify URI syntax is correct
3. Check logs: `tail -f ~/Library/Logs/KeyPath/keypath-debug.log`

### App not launching

1. Verify app name is correct (case-insensitive)
2. Check app is in `/Applications/` or `~/Applications/`
3. Try using bundle identifier instead
