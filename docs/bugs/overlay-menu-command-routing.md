# Overlay menu actions must reach their controller

At product `1e49d80f8ca3275e7715965290646f4bdd9c965e`, View → Center Overlay
and View → Toggle Inspector posted string notifications that had no observer
anywhere in Sources. Menu activation could therefore succeed without changing
the visible overlay. GlobalHotkeyService already invoked the real controller
methods for the same keyboard shortcuts.

The menu now calls those existing controller paths directly. Center Overlay
uses `showResetCentered()`, which clears the saved frame, closes the inspector,
restores default size, centers and shows the window. Toggle Inspector follows
the global shortcut's sequence: show a hidden overlay using its guarded
visibility setter, bring it forward, then `toggleDrawerWithHighlight()`. The
controller continues to own onboarding visibility admission and inspector
animation behavior. No notification observer or new window/controller is added.

## Verification

Source tracing confirms both old notification names are absent from Sources,
and the menu resolves to existing `@MainActor` controller methods. The pinned
formatter, accessibility source check and whitespace check passed. No Swift
build or UI execution ran in this workstream.

There is no isolated controller test seam: its singleton initializes real
defaults/observers and window capture behavior. A test that only repeats the
menu source would not demonstrate the visible outcome. The root's signed UI
acceptance must verify these actual postconditions after onboarding:

1. Move or resize the overlay, open its inspector, then choose Center Overlay.
   The overlay returns to default size, appears centered, and the inspector
   closes. Repeat while the overlay is hidden; it becomes visible and centered.
2. Choose Toggle Inspector with the overlay visible. Its drawer opens; choosing
   it again closes the drawer after the transition completes.
3. Hide the overlay, then choose Toggle Inspector. The overlay becomes visible
   and frontmost with its drawer open.

The keyboard shortcuts retain the existing GlobalHotkeyService behavior.
