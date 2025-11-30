# KeyPath Action URI System

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
  vim (multi (push-msg "layer:vim") (layer-switch vim))
)
```

**Optional subpaths:**
- `:activate` / `/activate` - Layer was activated
- `:deactivate` / `/deactivate` - Layer was deactivated

### `rule:{id}` / `keypath://rule/{id}[/fired]`

Signal that a rule was triggered (for analytics, feedback, or debugging).

**Kanata config (shorthand):**
```lisp
(defalias
  caps-escape (multi (push-msg "rule:caps-escape:fired") esc)
)
```

### `notify:` / `keypath://notify`

Show a system notification.

**Kanata config (shorthand):**
```lisp
(push-msg "notify:?title=Saved&body=Document saved successfully")
(push-msg "notify:?title=Layer&body=Navigation mode&sound=Pop")
```

**Query parameters:**
| Parameter | Description | Default |
|-----------|-------------|---------|
| `title` | Notification title | "KeyPath" |
| `body` | Notification body | "" |
| `sound` | macOS sound name | (none) |

### `open:{url}` / `keypath://open/{url}`

Open a URL in the default browser.

**Kanata config (shorthand):**
```lisp
(push-msg "open:github.com")
(push-msg "open:https://docs.keypath.app")
```

**Notes:**
- URLs without a scheme get `https://` prepended
- URL-encoded characters are decoded automatically

### `fakekey:{name}` / `keypath://fakekey/{name}[/{action}]`

Trigger a Kanata virtual key (defined via `defvirtualkeys` or `deffakekeys`).

**Kanata config (shorthand):**
```lisp
;; Define virtual keys in your Kanata config
(defvirtualkeys
  email-sig (macro H e l l o spc W o r l d)
  toggle-mode (layer-toggle special)
)

;; Trigger from KeyPath
(push-msg "fakekey:email-sig")           ;; tap (default)
(push-msg "fakekey:toggle-mode:press")
(push-msg "fakekey:toggle-mode:release")
```

**Deep link (for external tools):**
```bash
open "keypath://fakekey/email-sig/tap"
```

**Actions:**
| Action | Description |
|--------|-------------|
| `tap` | Press and immediately release (default) |
| `press` | Press and hold |
| `release` | Release a held key |
| `toggle` | Toggle between pressed and released |

**Use cases:**
- Trigger macros from external tools (Raycast, Alfred, deep links)
- Execute complex key sequences via simple URL
- Remote-control Kanata layers and modes

**Example: Email signature via Raycast**
```bash
#!/bin/bash
# @raycast.title Insert Email Signature
# @raycast.mode silent
open "keypath://fakekey/email-sig/tap"
```

## Kanata Configuration

### Naming Conventions

**Use full application names in launch aliases**, not abbreviations:

| ✅ Recommended | ❌ Avoid |
|---------------|----------|
| `launch-obsidian` | `launch-obs` |
| `launch-terminal` | `launch-term` |
| `launch-safari` | `launch-saf` |
| `launch-slack` | `launch-slk` |
| `launch-visual-studio-code` | `launch-vscode` |

**Why?**
- Self-documenting: Anyone reading the config immediately knows which app launches
- Unambiguous: `launch-obs` could mean Obsidian or OBS Studio
- Consistent: Matches the `launch:{full-app-name}` pattern

### Basic Usage

Add `push-msg` to any alias:

```lisp
(defalias
  ;; Launch app (use full app name in alias)
  launch-obsidian (push-msg "launch:obsidian")

  ;; Notify on layer switch
  nav (multi (push-msg "layer:nav") (layer-switch nav))

  ;; Track rule usage (optional - consider if you really need it)
  caps-escape (multi (push-msg "rule:caps-escape:fired") esc)
)
```

### Complete Example

```lisp
(defcfg
  process-unmapped-keys yes
)

(defsrc caps a s d f)

(defalias
  ;; Caps Lock → Escape (no tracking needed for basic functionality)
  caps-escape esc

  ;; Quick app launchers (use full app name in alias, not abbreviations)
  launch-obsidian (push-msg "launch:obsidian")
  launch-slack (push-msg "launch:slack")

  ;; Layer with notification
  to-nav (multi
    (push-msg "layer:nav:activate")
    (push-msg "notify:?title=Nav Mode&sound=Tink")
    (layer-switch nav)
  )
)

(deflayer base
  @caps-escape @launch-obsidian @launch-slack d @to-nav
)

(deflayer nav
  @caps-escape left down up right
)
```

## Deep Linking from External Tools

### Terminal / Shell

```bash
open "keypath://launch/Obsidian"
open "keypath://notify?title=Hello&body=World"
```

### Raycast

Create a Raycast script command:

```bash
#!/bin/bash
# @raycast.title Launch Obsidian via KeyPath
# @raycast.mode silent

open "keypath://launch/Obsidian"
```

### Alfred

Create a workflow with "Open URL" action:
- URL: `keypath://launch/{query}`

### Keyboard Maestro

Use "Open URL" action with `keypath://` URLs.

### AppleScript

```applescript
do shell script "open 'keypath://launch/Obsidian'"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Entry Points                            │
├──────────────────────┬──────────────────────────────────────┤
│   Kanata (push-msg)  │  External (open keypath://...)       │
│         │            │              │                        │
│         ▼            │              ▼                        │
│  TCP MessagePush     │      URL Scheme Handler               │
│         │            │              │                        │
│         ▼            │              ▼                        │
│  KanataEventListener │      AppDelegate.application(_:open:)│
│         │            │              │                        │
└─────────┴────────────┴──────────────┴────────────────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ KeyPathActionURI │  (Parses keypath:// URIs)
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ ActionDispatcher │  (Routes to handlers)
              └────────┬────────┘
                       │
     ┌─────────┬───────┼───────┬─────────┐
     ▼         ▼       ▼       ▼         ▼
 handleLaunch handleNotify handleOpen handleFakeKey
                                          │
                                          ▼
                                   ┌──────────────┐
                                   │KanataTCPClient│
                                   │ ActOnFakeKey │
                                   └──────────────┘
```

## Custom Handlers

Subscribe to `ActionDispatcher` callbacks for custom handling:

```swift
// In your code
ActionDispatcher.shared.onLayerAction = { layerName in
    // Custom layer change handling
    print("Layer changed to: \(layerName)")
}

ActionDispatcher.shared.onRuleAction = { ruleId, path in
    // Custom rule tracking
    Analytics.track("rule_fired", properties: ["rule": ruleId])
}

ActionDispatcher.shared.onError = { message in
    // Show error toast/dialog
    showToast(message)
}
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Unknown action type | Logs warning, calls `onError` callback |
| Missing target | Logs warning, calls `onError` callback |
| App not found | Attempts all search paths, then calls `onError` |
| Invalid URL format | Logs warning, calls `onError` callback |

## Security Considerations

- **Launch action**: Only launches apps from standard macOS app directories
- **Open action**: Opens URLs in user's default browser (sandboxed)
- **No file system access**: Actions cannot read/write arbitrary files
- **No shell execution**: `cmd` action is not supported (use Kanata's native `cmd` for that)

## Virtual Keys Inspector

KeyPath includes a built-in inspector for viewing and testing virtual keys defined in your configuration.

### Accessing the Inspector

1. Open KeyPath Settings (⌘,)
2. Go to the **General** tab
3. Scroll down to the **Virtual Keys** section

### Features

| Feature | Description |
|---------|-------------|
| **Key List** | Shows all keys from `defvirtualkeys` and `deffakekeys` blocks |
| **Copy URL** | Copy the deep link URL to clipboard for use in Raycast, Alfred, etc. |
| **Test Button** | Trigger the virtual key immediately to verify it works |
| **Refresh** | Re-parse the config file to pick up changes |

### Requirements

- Virtual keys must be defined in your Kanata config using `defvirtualkeys` or `deffakekeys`
- Kanata service must be running to test keys (TCP connection required)
- The inspector is read-only; edit your config file to add/modify keys

### Troubleshooting

| Issue | Solution |
|-------|----------|
| "No Virtual Keys Defined" | Add `defvirtualkeys` or `deffakekeys` blocks to your config |
| "Network error" on test | Ensure Kanata service is running |
| Key not triggering | Verify the key name matches exactly (case-sensitive) |
| Changes not showing | Click Refresh or reopen Settings |

## Future Extensions

Planned action types (not yet implemented):
- `keypath://clipboard/copy?text=...` - Copy text to clipboard
- `keypath://sound/play?name=...` - Play a sound
- `keypath://window/focus?app=...` - Focus specific window
- `keypath://shortcut/run?name=...` - Run macOS Shortcut
