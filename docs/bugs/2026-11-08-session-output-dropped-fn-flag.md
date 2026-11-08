# Session runtime dropped the Fn flag, breaking Ctrl+arrow Space switching

**Symptom.** With the driverless session runtime running and
`process-unmapped-keys yes`, Ctrl+Left/Right no longer switched Spaces. Every
other shortcut worked.

**Cause.** macOS gives arrow keys (and Home/End, Page Up/Down, F-keys) the
`maskSecondaryFn` flag, and arrows and the keypad also get `maskNumericPad`. The
Mission Control Space-switch hotkeys (79/81 in `com.apple.symbolichotkeys`) are
registered as Control + Fn (`8650752` = `0x840000`). The worker re-posts every
key Kanata handles and overwrote the new event's flags with Kanata's modifiers,
dropping Fn, so the shortcut never matched. The unmapped-key passthrough path
overwrote flags the same way.

**What it was not.** An earlier note blamed the tap location (session vs HID).
With KeyPath quit, synthetic Ctrl+Right posted at both `.cgSessionEventTap` and
`.cghidEventTap` switched Spaces only when Fn and keypad were set, and never
without them.

**Fix.** `SessionRuntimeWorker.outputFlags` keeps the key's intrinsic flags
(`keyIntrinsicFlags`) from the default `CGEvent` for that key code, and the
passthrough path keeps them from the original event.
