---
layout: default
title: "Function Pack Availability"
description: "F1–F12 mappings are supported; the combined media and brightness Function pack is unavailable in driverless mode."
theme: parchment
header_image: header-fun-layer.png
permalink: /guides/fun-layer/
---

# Function Pack Availability

**The Function pack is unavailable in driverless mode.** It combines F1–F12
with media and brightness actions, which the driverless runtime cannot emit.
KeyPath keeps the pack unavailable rather than activating only part of it.

## What you can use

Ordinary **F1–F12** mappings remain supported. Choose a function key as the output
of a regular mapping for an app shortcut. Function keys and media controls are
different outputs: F7 is not Previous Track, and F12 is not Volume Up.

Your keyboard's normal volume, playback and brightness controls remain managed
by macOS. Use those controls or macOS Control Center to adjust media and display
settings.

## Why can't I select a media action?

Play/Pause, Previous Track, Next Track, Mute, Volume Up/Down and Brightness Up/Down
are unavailable as remapped outputs. Granting permissions again will not enable
them, and changing the standard function-key preference will not add support.

Imported or manually edited configurations containing unsupported actions must
also pass runtime validation. Keep a supported mapping instead of bypassing the
disabled control.

## Related guides

- [Choose Your Leader Key]({{ '/guides/leader-key/' | relative_url }})
- [Keyboard Concepts]({{ '/guides/concepts/' | relative_url }})
- [Caps Lock in driverless KeyPath]({{ '/guides/driverless-caps-lock/' | relative_url }})
