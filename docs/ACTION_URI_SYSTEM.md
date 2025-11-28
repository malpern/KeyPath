# KeyPath Action URI System

KeyPath supports a URI-based action system that enables:
1. **Kanata integration** - Trigger KeyPath actions from keyboard shortcuts via `push-msg`
2. **Deep linking** - External tools (Raycast, LeaderKey, Alfred) can invoke KeyPath actions
3. **Extensibility** - Add new action types without protocol changes

## URI Format

```
keypath://[action]/[target][/subpath...][?query=params]
```

| Component | Description | Example |
|-----------|-------------|---------|
| `action` | The action type | `launch`, `layer`, `notify` |
| `target` | Primary target | `obsidian`, `nav`, `vim-mode` |
| `subpath` | Additional path segments | `/fired`, `/activate` |
| `query` | Key-value parameters | `?title=Hello&sound=pop` |

## Supported Actions

### `keypath://launch/{app}`

Launch an application by name or bundle identifier.

```lisp
;; By app name
(push-msg "keypath://launch/Obsidian")
(push-msg "keypath://launch/Terminal")

;; By bundle identifier
(push-msg "keypath://launch/com.apple.Terminal")
(push-msg "keypath://launch/md.obsidian")
```

**Resolution order:**
1. Bundle identifier lookup
2. Application name in `/Applications/`
3. Application name in `/System/Applications/`
4. Application name in `~/Applications/`

### `keypath://layer/{name}`

Signal a layer change (for UI feedback, logging, or custom handlers).

```lisp
(defalias
  nav (multi (push-msg "keypath://layer/nav") (layer-switch nav))
  vim (multi (push-msg "keypath://layer/vim") (layer-switch vim))
)
```

**Optional subpaths:**
- `/activate` - Layer was activated
- `/deactivate` - Layer was deactivated

### `keypath://rule/{id}[/fired]`

Signal that a rule was triggered (for analytics, feedback, or debugging).

```lisp
(defalias
  caps-esc (multi (push-msg "keypath://rule/caps-to-escape/fired") esc)
)
```

### `keypath://notify`

Show a system notification.

```lisp
(push-msg "keypath://notify?title=Saved&body=Document saved successfully")
(push-msg "keypath://notify?title=Layer&body=Navigation mode&sound=Pop")
```

**Query parameters:**
| Parameter | Description | Default |
|-----------|-------------|---------|
| `title` | Notification title | "KeyPath" |
| `body` | Notification body | "" |
| `sound` | macOS sound name | (none) |

### `keypath://open/{url}`

Open a URL in the default browser.

```lisp
(push-msg "keypath://open/github.com")
(push-msg "keypath://open/https://docs.keypath.app")
```

**Notes:**
- URLs without a scheme get `https://` prepended
- URL-encoded characters are decoded automatically

### `keypath://fakekey/{name}[/{action}]`

Trigger a Kanata virtual key (defined via `defvirtualkeys` or `deffakekeys`).

```lisp
;; Define virtual keys in your Kanata config
(defvirtualkeys
  email-sig (macro H e l l o spc W o r l d)
  toggle-mode (layer-toggle special)
)

;; Trigger from KeyPath (or external tools)
(push-msg "keypath://fakekey/email-sig")        ;; tap (default)
(push-msg "keypath://fakekey/toggle-mode/press")
(push-msg "keypath://fakekey/toggle-mode/release")
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

### Basic Usage

Add `push-msg` to any alias using `multi`:

```lisp
(defalias
  ;; Launch app when pressing key
  obs (multi (push-msg "keypath://launch/Obsidian") o)

  ;; Notify on layer switch
  nav (multi (push-msg "keypath://layer/nav") (layer-switch nav))

  ;; Track rule usage
  caps (multi (push-msg "keypath://rule/caps-esc") esc)
)
```

### Complete Example

```lisp
(defcfg
  process-unmapped-keys yes
)

(defsrc caps a s d f)

(defalias
  ;; Caps Lock → Escape with tracking
  caps-esc (multi (push-msg "keypath://rule/caps-esc/fired") esc)

  ;; Quick app launchers
  app-obs (multi (push-msg "keypath://launch/Obsidian") o)
  app-slack (multi (push-msg "keypath://launch/Slack") s)

  ;; Layer with notification
  to-nav (multi
    (push-msg "keypath://layer/nav/activate")
    (push-msg "keypath://notify?title=Nav Mode&sound=Tink")
    (layer-switch nav)
  )
)

(deflayer base
  @caps-esc @app-obs @app-slack d @to-nav
)

(deflayer nav
  @caps-esc left down up right
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

## Future Extensions

Planned action types (not yet implemented):
- `keypath://clipboard/copy?text=...` - Copy text to clipboard
- `keypath://sound/play?name=...` - Play a sound
- `keypath://window/focus?app=...` - Focus specific window
- `keypath://shortcut/run?name=...` - Run macOS Shortcut
