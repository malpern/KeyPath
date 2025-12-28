# Japanese Keyboard Rules - Future Considerations

This document captures research on popular Japanese keyboard customizations that could be added to KeyPath.

## Current Japanese Support

- JIS keyboard layout detection (auto-selects `macbook-jis` on first launch)
- JIS physical layout with correct key labels
- Japanese input mode indicator in overlay (あ/ア/A)
- Japanese localization (Localizable.strings)

---

## Potential Future Rules

### 1. SandS (Space and Shift)

**What it is:** Hold Space = Shift, Tap Space = Space

**Popularity:** Very popular in Japan, but universally useful.

**Implementation:** Add as Leader Key preset option:
```
"Space (SandS - Shift when held)"
```

**Priority:** Medium - Could benefit all users, not just Japanese.

**References:**
- [Kanata discussions on space-as-shift](https://github.com/jtroo/kanata/discussions/1064)

---

### 2. Command Key IME Toggle

**What it is:**
- Left ⌘ tap → 英数 (alphanumeric mode)
- Right ⌘ tap → かな (Japanese mode)

**Popularity:** Extremely popular Karabiner rule in Japan.

**Implementation:** New rule collection "IME Shortcuts" with tap-hold on Command keys.

**Priority:** High for Japanese users, not applicable elsewhere.

**References:**
- [Karabiner config by ladypuipui](https://github.com/ladypuipui/My-Karabiner-Elements-config)
- [Toggle rule by jmblog](https://gist.github.com/jmblog/3a40fade91f5acfc0a9e53c0889b2c69)

---

### 3. 無変換/変換 Key Remapping

**What it is:** Repurpose the 無変換 (Muhenkan) and 変換 (Henkan) keys on JIS keyboards.

**Common mappings:**
| Key | Popular Remaps |
|-----|----------------|
| 無変換 | Escape, Control, Layer activator |
| 変換 | Enter, Backspace, IME toggle |

**Popularity:** Standard practice for JIS keyboard power users.

**Implementation:**
- Show this rule only when JIS layout is selected
- Offer presets similar to Caps Lock remap

**Priority:** High for JIS keyboard users.

**References:**
- [Windows IME key customization](https://hamachan.info/win11-ime-onoff/)
- [DTP Transit guide](https://dtptransit.design/misc/windows/customize-keyboards-for-Japanese-input-method.html)

---

### 4. Caps Lock → IME Toggle

**What it is:** Tap Caps Lock to toggle between 英数/かな modes.

**Implementation:** Add "IME Toggle" as a tap option in existing Caps Lock Remap:
```swift
SingleKeyPreset(
    output: "lang-toggle",  // or specific key codes
    label: "🌐 IME Toggle",
    description: "Toggle between Japanese and English input",
    icon: "globe"
)
```

**Priority:** Medium - Simple addition to existing rule.

**References:**
- [Windows Caps Lock IME toggle](https://github.com/chriskempson/windows-capslock-key-japanese-input-toggle)

---

### 5. Single-Key IME Toggle

**What it is:** Use かな key alone to toggle (instead of separate 英数/かな).

**Current behavior:** 英数 → alphanumeric, かな → Japanese (explicit)

**Requested behavior:** Single key toggles between states.

**Priority:** Low - Niche preference.

---

### 6. NICOLA / 親指シフト (Thumb Shift)

**What it is:** Alternative Japanese input method using thumb keys for dakuten/handakuten.

**Complexity:** Very high - requires:
- Complete kana mapping tables
- Simultaneous key detection (thumb + character)
- Custom input method behavior

**Priority:** Low - Very niche, better served by dedicated IME.

**References:**
- [Wikipedia: 親指シフト](https://ja.wikipedia.org/wiki/親指シフト)
- [NICOLA overview](https://www.nslabs.jp/nicola.rhtml)

---

## Implementation Strategy

### Phase 1: Quick Wins
1. Add "IME Toggle" to Caps Lock tap options
2. Add SandS as Leader Key option

### Phase 2: JIS-Specific Rules
1. 無変換/変換 remap collection (context-aware, JIS only)
2. Command-tap IME toggle

### Phase 3: Evaluate
1. Single-key toggle preference
2. Community feedback on additional needs

---

## Detection & Context

Rules should be context-aware based on:

```swift
// Already implemented
KeyboardTypeDetector.detect() // Returns .jis, .ansi, .iso
InputSourceDetector.shared.isJapaneseInputActive
```

Show JIS-specific rules when:
- Physical keyboard is JIS, OR
- User has selected JIS layout in overlay, OR
- Japanese IME is active

---

## Key Codes Reference

| Key | Kanata Code | macOS Key Code |
|-----|-------------|----------------|
| 英数 | `lang2` | 0x66 (102) |
| かな | `lang1` | 0x68 (104) |
| 無変換 | `muhenkan` or `int5` | 0x67 (103) |
| 変換 | `henkan` or `int4` | 0x64 (100) |

---

## Community Input Needed

Before implementing, gather feedback on:
1. Which customizations are most requested?
2. Are there common setups we're missing?
3. ATOK vs Kotoeri vs Google IME differences?

Consider adding a feedback mechanism or survey for Japanese beta users.
