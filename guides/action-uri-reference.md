---
layout: default
title: "Action URI Reference"
description: "Technical deep-link reference for integrating KeyPath with Raycast, Alfred, and scripts"
theme: parchment
header_image: header-action-uri.png
---


# Action URI Reference

KeyPath uses a URI scheme (`keypath://`) to trigger actions. This is the technical reference for integrating KeyPath with external tools like Raycast, Alfred, Shortcuts.app, or your own scripts.

If you just want to set up app launching through KeyPath's UI, see the [Launching Apps guide]({{ '/guides/action-uri' | relative_url }}) instead.

---

## Deep link format

Trigger any KeyPath action from Terminal or any tool that can open URLs:

```bash
open "keypath://launch/Safari"
open "keypath://window/snap/left"
open "keypath://notify?title=Deployed&body=Build complete"
```

---

## Supported actions

### `keypath://launch/{app}`

Launch an application by name or bundle identifier.

KeyPath resolves app names in this order:
1. Bundle identifier lookup (e.g., `com.apple.Safari`)
2. `/Applications/`
3. `/System/Applications/`
4. `~/Applications/`

```bash
open "keypath://launch/Safari"
open "keypath://launch/com.apple.Safari"
open "keypath://launch/Visual Studio Code"
```

---

### `keypath://window/snap/{position}`

Tile the current window to a screen position.

Positions: `left`, `right`, `top`, `bottom`, `topleft`, `topright`, `bottomleft`, `bottomright`, `maximize`, `center`

```bash
open "keypath://window/snap/left"
open "keypath://window/snap/maximize"
```

---

### `keypath://layer/{name}`

Signal a layer change for UI feedback.

Subpaths: `/activate`, `/deactivate`, `/toggle`

```bash
open "keypath://layer/nav/activate"
open "keypath://layer/vim/toggle"
```

---

### `keypath://notify`

Show a system notification.

Query parameters:
- `title` (required) — notification title
- `body` (optional) — notification body text
- `sound` (optional, default: `true`) — play notification sound

```bash
open "keypath://notify?title=Build%20Complete&body=Ready%20to%20deploy"
open "keypath://notify?title=Saved&sound=false"
```

---

### `keypath://fakekey/{name}`

Trigger a virtual key press.

Subpaths: `/press`, `/release`, `/tap`

```bash
open "keypath://fakekey/vk1/tap"
```

---

## Integration examples

### Raycast

Create a Raycast script command:

```bash
#!/bin/bash
# @raycast.title Launch Safari
# @raycast.mode silent
open "keypath://launch/Safari"
```

### Alfred

Use an Alfred workflow "Open URL" action with `keypath://launch/{query}`.

### Shortcuts.app

Add a "Run Shell Script" action:

```bash
open "keypath://launch/Safari"
```

### Shell scripts

Chain multiple actions:

```bash
#!/bin/bash
open "keypath://window/snap/left"
sleep 0.5
open "keypath://launch/Terminal"
open "keypath://window/snap/right"
```

---

## Security

Action URIs are only processed from local sources:
- KeyPath's own remapping engine (via the internal message system)
- Local system processes (via the `open` command)

No network access is required or used. Actions execute with your normal user permissions.

---

## Error handling

If an action fails (e.g., app not found), KeyPath logs the error but doesn't crash. Check **File → View Logs** for details. Invalid URIs are silently ignored.

---

## Related guides

- **[Launching Apps]({{ '/guides/action-uri' | relative_url }})** — Set up app launching through KeyPath's UI
- **[Windows & App Shortcuts]({{ '/guides/window-management' | relative_url }})** — App-specific keymaps and window snapping
- **[From Kanata]({{ '/migration/kanata-users' | relative_url }})** — Using Action URIs in your Kanata config
- **[Back to Docs](https://keypath-app.com)** — See all available guides

## External resources

- **[Kanata configuration reference](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)** — For using Action URIs in raw Kanata configs
- **[Raycast](https://www.raycast.com/)** — Pairs well with KeyPath's deep link system
- **[Alfred](https://www.alfredapp.com/)** — Another launcher that integrates with KeyPath deep links
