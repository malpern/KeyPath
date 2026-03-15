# ADR-037: Dynamic OS-Driven Key Labels (System Keymap)

## Status
Accepted

## Context

KeyPath's overlay shows key labels from manually-authored `LogicalKeymap` definitions (QWERTY, AZERTY, QWERTZ, etc.). International users see US QWERTY labels because no `LogicalKeymap` exists for their locale. Creating and maintaining 20+ static keymaps is impractical.

macOS provides the `UCKeyTranslate` Carbon API which queries what character each keyCode produces under the user's current input source. This gives instant support for every locale macOS supports.

## Decision

Add a `SystemKeyLabelProvider` service that wraps `UCKeyTranslate`, and a `"system"` sentinel `LogicalKeymap` that pulls labels from it dynamically.

### How It Interacts With the Keyboard Stack

```
Physical Key -> HID Scancode -> [Kanata remaps here] -> CGKeyCode -> [OS layout here] -> Character
```

Kanata remaps scancodes **before** the OS applies the keyboard layout. `UCKeyTranslate` sees the post-remap keyCode and returns what the OS layout produces for it. This means:

- **International user, standard layout**: System keymap shows exactly what their keys produce.
- **US user with Colemak in Kanata**: Un-remapped keys show US QWERTY from the system keymap.
- **International user with alt layout in Kanata**: Un-remapped keys show the OS locale's labels.

### Key Design Choices

1. **`UCKeyTranslate` over manual keymaps**: Zero per-locale maintenance, supports custom `.keylayout` files, updates instantly on input source change.

2. **IME fallback**: When `kTISPropertyUnicodeKeyLayoutData` returns nil (Japanese, Chinese, Korean IMEs), fall back to `TISCopyCurrentKeyboardLayoutInputSource()` which returns the underlying physical layout (US/JIS).

3. **`kUCKeyTranslateNoDeadKeysBit`**: Dead keys (^, ¨, `) return their base character directly instead of entering a dead key state.

4. **Modifier key exclusion**: UCKeyTranslate returns empty for modifier keyCodes (Shift, Cmd, etc.) — these are skipped so `PhysicalKey.label` symbols (⇧, ⌘, ⌥, ⌃) remain.

5. **Uppercase for display**: Single-letter results are uppercased for visual consistency with the static keymaps.

6. **System keymap as default**: New users get `"system"` as their default keymap ID. Existing users keep their stored preference.

7. **All labels in `coreLabels`**: The system keymap puts all labels into `coreLabels` (not `extraLabels`) so the punctuation toggle is irrelevant — all keys are always labeled.

### Reactivity Chain

```
macOS input source change
  -> InputSourceDetector.refresh()          (existing)
  -> SystemKeyLabelProvider.shared.refresh() (new, one line)
  -> currentLabels dictionary updates        (@Observable)
  -> LogicalKeymap.system recomputes         (reads provider)
  -> LiveKeyboardOverlayView.activeKeymap    (SwiftUI diffs new struct)
  -> Overlay re-renders with new labels
```

## Consequences

- Every locale macOS supports works automatically, including custom `.keylayout` files.
- Existing static keymaps (Colemak, AZERTY, etc.) remain as alternatives for previewing layouts not currently active in macOS.
- The `KeyLabelQuerying` protocol enables testing without touching Carbon APIs.
- Per-key shift labels are dynamic (e.g., French: `1` -> `&`, not `1` -> `!`).
