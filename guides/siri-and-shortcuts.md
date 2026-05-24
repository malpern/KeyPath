---
layout: default
title: "Siri & Shortcuts"
description: "Control KeyPath with your voice or automate it with Shortcuts"
theme: parchment
permalink: /guides/siri-and-shortcuts/
---

# Siri & Shortcuts

KeyPath works with Siri and the Shortcuts app. Ask what layer you're on, start or stop the service, or trigger any KeyPath action — by voice or as part of an automation.

---

## What you can do with Siri

### "What layer am I on?"

Ask Siri which keyboard layer is active right now.

> "Hey Siri, what layer am I on in KeyPath?"

Siri responds with the layer name (e.g., "base", "nav", "window").

### Start, stop, or restart

Control the KeyPath remapping service without opening the app.

> "Hey Siri, start KeyPath"
> "Hey Siri, stop KeyPath"
> "Hey Siri, restart KeyPath"

### Send an action

Trigger any [KeyPath action]({{ '/guides/action-uri-reference/' | relative_url }}) through Siri.

> "Hey Siri, send action to KeyPath"

Siri will ask for the action URI (e.g., `keypath://launch/Obsidian`).

---

## Shortcuts app

KeyPath actions appear in the Shortcuts app under "KeyPath" in the action picker. You can combine them with any other Shortcut action.

### Get Current Layer

Returns the active layer as text. Use this with an "If" action to build layer-conditional automations:

1. Add "Get Current Layer" (KeyPath)
2. Add "If" — set condition to "is" and type the layer name
3. Add whatever actions you want inside the If block

**Example:** If the current layer is "work", open your work apps.

### Control Service

Start, stop, or restart the remapping service. Useful for scheduled automations:

1. Add "Control KeyPath Service" (KeyPath)
2. Choose Start, Stop, or Restart

**Example:** Create a Time of Day automation to stop KeyPath at 6 PM and start it at 9 AM.

### Send Action

Dispatch any `keypath://` action URI. This gives Shortcuts access to everything KeyPath can do:

- `keypath://launch/Terminal` — launch an app
- `keypath://system/mission-control` — trigger Mission Control
- `keypath://window/left` — snap window to left half
- `keypath://notify?title=Done&body=Build complete` — show a notification

See the [Action URI Reference]({{ '/guides/action-uri-reference/' | relative_url }}) for the full list.

---

## Tips

- KeyPath must be running for Siri and Shortcuts to work. The "Get Current Layer" and "Control Service" actions connect to the running app.
- The layer list is dynamic — it comes from your active Kanata configuration. If you add a new layer, it shows up in Shortcuts automatically.
- You can pin KeyPath Shortcuts to your menu bar for one-click access.
- Shortcuts automations can run KeyPath actions on a schedule, when you connect to a Wi-Fi network, when you open an app, and more.
