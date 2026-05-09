# Keyboard Visualization MVP Plan

## Goal

Add a floating keyboard visualization window that highlights keys as they're pressed. Pure visual feedback - no mapping display yet. **Tailored specifically for MacBook keyboard layouts.**

## Architecture (Three-Layer Model)

**PhysicalLayout (data)** → **KeyboardViewModel (joins layout + press state)** → **SwiftUI Views**

## Layer 1: Physical Layout Model

**New file:** `Sources/KeyPathAppKit/Models/PhysicalLayout.swift`

```swift
struct PhysicalKey: Identifiable, Hashable {
    let id: UUID
    let keyCode: UInt16          // CGEvent key code (matches KeyboardCapture)
    let label: String            // Display label ("A", "Shift", "⌘", "🔅")
    let x: Double                // In keyboard units (0-based)
    let y: Double
    let width: Double            // 1.0 = standard key
    let height: Double
}

struct PhysicalLayout {
    let name: String
    let keys: [PhysicalKey]
    let totalWidth: Double       // For aspect ratio calculation
    let totalHeight: Double

    static let macBookUS: PhysicalLayout  // Hardcoded MacBook US keyboard
}
```

**Key identification:** Use `UInt16` CGEvent key codes directly - this matches `KeyboardCapture.swift` which already has key code → string mapping (lines ~560-578).

**MacBook-Specific Considerations:**
- Function keys row (F1-F12) with special symbols (brightness, volume, media controls)
- Mac modifier keys: Command (⌘), Option (⌥), Control (⌃), Function (fn)
- Compact layout with smaller modifier keys
- Arrow keys cluster (↑ ↓ ← →)
- Touch Bar area ignored for MVP (no physical keys)

## Layer 2: ViewModel

**New file:** `Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel.swift`

```swift
@MainActor
class KeyboardVisualizationViewModel: ObservableObject {
    @Published var pressedKeyCodes: Set<UInt16> = []
    @Published var layout: PhysicalLayout = .macBookUS
    
    private var keyboardCapture: KeyboardCapture?
    
    func startCapturing()   // Sets up listen-only event tap
    func stopCapturing()
    func isPressed(_ key: PhysicalKey) -> Bool
}
```

**Integration point:** Reuse `KeyboardCapture` in listen-only mode (already supports this via `CaptureMode`).

### Event Capture Ownership (Critical)

We cannot spin up a second `KeyboardCapture` instance from the visualization window without destabilizing the existing recording/wizard flows—`KeyboardCapture` owns the global event tap and prompts for Input Monitoring permission when it starts. To avoid dueling taps and repeated permission prompts:

1. **Introduce a single capture coordinator** (e.g., `KeyboardCaptureCoordinator`) that owns the event tap and publishes key up/down events via Combine/AsyncSequence.
2. **Recording, wizard diagnostics, and the visualization view model all subscribe** to this coordinator. The coordinator reference-counts subscribers and only tears down the tap when the last subscriber unsubscribes.
3. **Visualization stays listen-only**: it subscribes to the shared event stream but never toggles tap state itself, so we do not interrupt the daemon or existing UI flows.

This shared-ownership approach keeps the MVP safe (no new permission prompts, no risk of pausing the main service) and creates the extensibility we need for future visual tooling.

## Layer 3: SwiftUI Views

**New files in** `Sources/KeyPathAppKit/UI/KeyboardVisualization/`:

1. `KeyboardVisualizationWindow.swift` - NSPanel wrapper for floating window
2. `KeyboardView.swift` - Main keyboard rendering with GeometryReader
3. `KeycapView.swift` - Individual key rendering

```swift
// KeyboardView - normalized coordinate rendering
struct KeyboardView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel
    
    var body: some View {
        GeometryReader { geo in
            let unitSize = geo.size.width / viewModel.layout.totalWidth
            
            ForEach(viewModel.layout.keys) { key in
                KeycapView(key: key, isPressed: viewModel.isPressed(key))
                    .frame(width: key.width * unitSize, height: key.height * unitSize)
                    .position(x: (key.x + key.width/2) * unitSize,
                              y: (key.y + key.height/2) * unitSize)
            }
        }
        .aspectRatio(viewModel.layout.totalWidth / viewModel.layout.totalHeight, contentMode: .fit)
    }
}
```

## Floating Window

Use `NSPanel` with:
- `.floating` window level
- Borderless or utility style
- Resizable (SwiftUI scales via normalized coords)
- Draggable from content area

## File Structure

```
Sources/KeyPathAppKit/
├── Models/
│   └── PhysicalLayout.swift           # NEW: Layout + key position data
├── UI/
│   └── KeyboardVisualization/         # NEW FOLDER
│       ├── KeyboardVisualizationWindow.swift   # NSPanel wrapper
│       ├── KeyboardVisualizationViewModel.swift
│       ├── KeyboardView.swift         # Main keyboard view
│       └── KeycapView.swift           # Single key view
```

## Implementation Steps

### Phase 1: Data Model

1. Create `PhysicalLayout.swift` with `PhysicalKey` and `PhysicalLayout` structs
2. Hardcode `PhysicalLayout.macBookUS` with all MacBook keys and positions:
   - **Function row:** F1-F12 with Mac symbols (🔅, 🔆, ⏮, ⏯, ⏭, 🔇, 🔉, 🔊)
   - **Main keyboard:** QWERTY layout with standard key sizes
   - **Modifier row:** Control, Option, Command (⌘), Space, Command (⌘), Option, fn
   - **Arrow cluster:** ↑ ↓ ← → keys
   - **Special keys:** Escape, Delete, Return, Tab, Caps Lock
3. Use CGEvent key codes from existing `KeyboardCapture` mapping

**MacBook Key Code Reference:**
Based on macOS CGEvent key codes (verify against actual hardware):
- Function keys: F1=122, F2=120, F3=99, F4=118, F5=96, F6=97, F7=98, F8=100, F9=101, F10=109, F11=103, F12=111
- Modifiers: Left Control=59, Left Option=58, Left Command=55, Right Command=54, Right Option=61, fn=63
- Arrow keys: Up=126, Down=125, Left=123, Right=124
- Main keys: Use mapping from `KeyboardCapture.swift` lines 562-571

**Note:** Key codes should be verified during implementation by testing on actual MacBook hardware. Some function keys may vary by MacBook model (e.g., Touch Bar models).

### Phase 2: Basic SwiftUI Rendering

1. Create `KeycapView` - simple rounded rect with label, pressed state changes color
2. Create `KeyboardView` - `GeometryReader` layout using normalized coordinates
3. Test with static layout (no live input yet)

**KeycapView Design:**
- Rounded rectangle with subtle shadow
- Label centered (text or symbol)
- Pressed state: brighter color or border highlight
- MacBook-style key proportions (slightly rounded, compact)

### Phase 3: ViewModel + Event Integration

1. Create `KeyboardVisualizationViewModel`
2. Wire up `KeyboardCapture` in listen-only mode (`suppressEvents = false`)
3. Update `pressedKeyCodes` on key down/up events
   - Track both keyDown and keyUp events
   - Use `CGEvent.keyDown` and `CGEvent.keyUp` event types
4. Connect to view

**Event Handling Architecture (CRITICAL):**

**⚠️ IMPORTANT:** `KeyboardCapture` is currently owned by `RecordingCoordinator` and manages global event tap state. Creating a second "listen-only" tap from the visualization window will:
- Race with wizard/recording flows
- Potentially tear down the active tap the service depends on
- Re-trigger Input Monitoring permission prompts

**Recommended Approach: Shared Event Pipeline (Option 1)**

Refactor `KeyboardCapture` into a singleton publisher that supports multiple subscribers:
- Single event tap started once (no duplicate permission prompts)
- Multiple subscribers: recording, visualization, wizard
- Visualization subscribes to keyDown/keyUp events without touching main capture service
- Benefits: Centralizes capture logic, reduces bugs, improves testability

**Alternative Approaches:**
- **Option 2:** Dedicated visualization tap - Isolates feature but duplicates capture logic and risks double prompts
- **Option 3:** Query daemon state via IPC - Requires daemon changes, medium reward

**Implementation Requirements:**
- Single owner: `KeyboardCaptureCoordinator` (or similar)
- Document how to avoid interrupting main tap
- Ensure visualization never modifies global tap state
- Handle keyDown/keyUp events (currently only keyDown is processed)
- Add keyCode to `pressedKeyCodes` on keyDown
- Remove keyCode from `pressedKeyCodes` on keyUp
- Handle autorepeat suppression (already handled by `KeyboardCapture`)

### Phase 4: Floating Window

1. Create `KeyboardVisualizationWindow` with `NSPanel`
2. Add window management (show/hide, remember position)
3. Add menu item or keyboard shortcut to toggle

**Window Configuration:**
Follow the pattern from `LayerIndicatorWindow.swift`:
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
    styleMask: [.borderless, .resizable],
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.isMovable = true  // Allow dragging
window.hasShadow = true
window.contentView = NSHostingView(rootView: KeyboardView(viewModel: viewModel))
```

## Key Decisions

| Decision          | Choice                    | Rationale                         |
|-------------------|---------------------------|-----------------------------------|
| Key identifier    | CGEvent UInt16 keyCode    | Matches existing `KeyboardCapture`  |
| Coordinate system | Keyboard units (1.0 = 1u) | Standard in mech keyboard world   |
| Window type       | NSPanel                   | Proper floating behavior on macOS |
| Event source      | Existing `KeyboardCapture`  | Reuse proven infrastructure       |
| Layout variant    | MacBook US (ANSI-style)   | Most common MacBook layout        |

## MacBook Keyboard Layout Details

### Layout Structure (Top to Bottom)

**Row 0: Function Keys** (y: 0.0)
- 12 function keys, each ~1.0u wide
- **F1 (122):** 🔅 Brightness Down
- **F2 (120):** 🔆 Brightness Up
- **F3 (99):** Mission Control / Launchpad
- **F4 (118):** Spotlight / Launchpad
- **F5 (96):** Keyboard Backlight Down (if available)
- **F6 (97):** Keyboard Backlight Up (if available)
- **F7 (98):** ⏮ Previous Track
- **F8 (100):** ⏯ Play/Pause
- **F9 (101):** ⏭ Next Track
- **F10 (109):** 🔇 Mute
- **F11 (103):** 🔉 Volume Down
- **F12 (111):** 🔊 Volume Up

**Row 1: Number Row** (y: 1.2u)
- ` 1 2 3 4 5 6 7 8 9 0 - = delete`
- Standard keys: 1.0u each
- Delete key: ~1.5u

**Row 2: QWERTY Top** (y: 2.4u)
- `tab q w e r t y u i o p [ ] \`
- Tab: ~1.5u, standard keys: 1.0u each

**Row 3: QWERTY Middle** (y: 3.6u)
- `caps a s d f g h j k l ; ' return`
- Caps Lock: ~1.75u, Return: ~2.25u, standard keys: 1.0u each

**Row 4: QWERTY Bottom** (y: 4.8u)
- `shift z x c v b n m , . / shift`
- Left Shift: ~2.25u, Right Shift: ~2.75u, standard keys: 1.0u each

**Row 5: Modifiers** (y: 6.0u)
- `control option command space command option fn`
- Left Control: ~1.25u
- Left Option: ~1.25u
- Left Command: ~1.25u
- Space: ~4.0u
- Right Command: ~1.25u
- Right Option: ~1.25u
- fn: ~1.0u

**Row 6: Arrow Cluster** (y: 7.2u, x: ~11.0u from left)
- Compact 2x2 grid positioned below right Shift
- `     ↑     `
- `← ↓ →`
- Each arrow key: ~1.0u

### Coordinate System Notes
- **Unit (u):** Standard key width = 1.0u (~19mm on MacBook)
- **Row spacing:** 1.2u vertical spacing between row centers
- **Key spacing:** ~0.1u gap between adjacent keys
- **Total width:** ~15.0u (function row) to ~14.0u (main keyboard)
- **Total height:** ~8.5u (function row + 6 main rows + arrow cluster)

### Key Size Reference
- **Standard key:** 1.0u × 1.0u
- **Wide modifier:** 1.25u × 1.0u (Option, Command)
- **Extra wide:** 1.5u-2.75u × 1.0u (Tab, Shift, Return, Space)
- **Height:** All keys ~1.0u tall (uniform)

### Visual Layout Approximation
```
[F1] [F2] [F3] [F4] [F5] [F6] [F7] [F8] [F9] [F10] [F11] [F12]
[`] [1] [2] [3] [4] [5] [6] [7] [8] [9] [0] [-] [=] [delete]
[tab] [q] [w] [e] [r] [t] [y] [u] [i] [o] [p] [[] []] [\]
[caps] [a] [s] [d] [f] [g] [h] [j] [k] [l] [;] ['] [return]
[shift] [z] [x] [c] [v] [b] [n] [m] [,] [.] [/] [shift]
[ctrl] [opt] [cmd] [                    space                    ] [cmd] [opt] [fn]
                                                                    [↑]
                                                                    [←] [↓] [→]
```

## Critical Files to Read Before Implementation

- `/Sources/KeyPathAppKit/Services/KeyboardCapture.swift` - Event tap, key code mapping (lines 560-578)
- `/Sources/KeyPathAppKit/UI/RecordingCoordinator.swift` - Example of `KeyboardCapture` usage

## CGEvent Key Code Reference

Based on `KeyboardCapture.swift` and macOS documentation:

**Main Keys:**
- a=0, s=1, d=2, f=3, h=4, g=5, z=6, x=7, c=8, v=9, b=11
- q=12, w=13, e=14, r=15, y=16, t=17
- 1=18, 2=19, 3=20, 4=21, 6=22, 5=23, =24, 9=25, 7=26, -=27, 8=28, 0=29
- ]=30, o=31, u=32, [=33, i=34, p=35, return=36
- l=37, j=38, '=39, k=40, ;=41, \=42, ,=43
- /=44, n=45, m=46, .=47
- tab=48, space=49, `=50, delete=51, escape=53

**Modifiers:**
- Left Control=59, Left Option=58, Left Command=55
- Right Command=54, Right Option=61, fn=63
- Left Shift=56, Right Shift=60, Caps Lock=57

**Function Keys:**
- F1=122, F2=120, F3=99, F4=118, F5=96, F6=97
- F7=98, F8=100, F9=101, F10=109, F11=103, F12=111

**Arrow Keys:**
- Up=126, Down=125, Left=123, Right=124

## Future Phases (Not MVP)

1. **Mapping visualization** - Show what keys remap to
2. **Layer display** - Show active layer, layer-specific mappings
3. **Tap-hold visualization** - Show tap vs hold state
4. **Additional layouts** - ISO MacBook, JIS MacBook, external keyboards
5. **Heatmap mode** - Show key frequency over time
6. **Touch Bar support** - For MacBook Pro models with Touch Bar (dynamic keys)

## Known Limitations

### F-Keys as Media Keys (F1-F12)

On MacBooks, F1-F12 are media keys by default (brightness, volume, etc.):
- **Without Fn held**: These generate `NSSystemDefined` events, not CGEvents. Our CGEvent tap cannot see them.
- **With Fn held**: They generate normal F-key codes and will highlight correctly.

**Workaround for users**: Enable "Use F1, F2, etc. keys as standard function keys" in System Settings → Keyboard.

**Potential future solution**: Use IOHIDManager for raw HID-level access. This would capture all hardware events including media keys, but requires significant refactoring:
1. Replace CGEvent tap with IOHIDManager-based capture
2. Map HID usage pages to key codes
3. Handle device hotplug events
4. Test across different Mac models (different HID usage pages)

Estimated effort: 1-2 days of development + testing

### Escape Key on Touch Bar MacBooks

Touch Bar MacBook Pros don't have a physical Escape key. The virtual Escape key on the Touch Bar may not generate CGEvents that our tap can see.

## Notes

- MacBook keyboards are more compact than standard ANSI 104-key layouts
- Function keys have dual functionality (F-key vs media control) - MVP shows F-key labels
- Some MacBook models have Touch Bar instead of function keys - MVP ignores Touch Bar
- Key sizes are approximate - adjust based on visual testing
- Coordinate system uses "keyboard units" where 1.0u = standard key width

