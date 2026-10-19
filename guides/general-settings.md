---
layout: default
title: General settings
---

# Make KeyPath look and behave the way you prefer

Open KeyPath → Settings → General.

- **Startup:** enable **Launch at login** to make your mappings available after you sign in. If macOS asks for approval, use **Open Login Items**. Turning it off does not stop your current session.
- **While a Layer Is Active:** choose what appears while a layer is active: the keyboard overlay, the compact list, both, or nothing (the default). Then choose Hold or Tap.
  - With **Hold**, the overlay appears when you hold the layer key and pause for a moment. Quick moves like Space then J never bring it up, so it only shows when you're looking for a key. It hides as soon as you let go.
  - With **Tap**, it appears as soon as you tap the layer on and hides when you tap it off.
  - An overlay you opened yourself (⌥⌘K) stays open either way.
  - The **Layer change notification** (a banner and sound) is here too.
  - The same choice is in the menu bar under **While a Layer Is Active**.
- **Keyboard Appearance:** compare key-label previews, choose whether unmapped keys stay normal or dim, set how see-through the overlay is (**Overlay opacity**), and choose whether it fades after a while without typing (**Fade when idle**).
- **Recording:** choose sequences or combinations, and whether recording captures physical keys or includes your mappings.
- **Keyboard Setup:** Caps Lock is set up automatically when your rules need it. Manual keyboard setup is available under its disclosure. You can also import Karabiner rules here.
- **Advanced:** expand Logs & Diagnostics or Virtual Keys when needed. Development builds also expose Experimental settings.

Appearance previews change only how keys are displayed. Recording choices apply to recording new rules.

The keyboard overlay temporarily hides while you use System Settings or a macOS authentication dialog, then returns when you leave.

With more than one display, the overlay remembers where you put it on each one and opens on the display you're using. On a display it hasn't been on yet, it takes the same corner it had on the last one. ⌥⌘L centers it on the display you're using.
