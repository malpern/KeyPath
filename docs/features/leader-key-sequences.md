# Leader Key Sequences - True Leader Key Behavior

## User Request

Support true leader key behavior where:
1. User presses **Leader key** (e.g., Space)
2. User presses **context key** (e.g., "w" for windows)
3. System shows **visual overlay** with available mappings for that context
4. User sees all window controls mapped to home row keys

**Example Flow:**
```
Press Space → Press "w" → See overlay with:
- H: Left half
- L: Right half
- M: Maximize
- etc. (all window controls near home row)
```

## Current Architecture

### What Exists Today

**✅ Layer System**
- Multiple layers defined: Navigation, Vim, Numpad, Symbol, Launcher
- Momentary layer activation (hold leader to activate layer)
- Layer switching via TCP protocol

**✅ Visual Overlay**
- Complete UI overlay system (`LiveKeyboardOverlayView`)
- Shows key presses and layer states
- Supports physical keyboard layouts (MacBook US, ISO, ANSI)
- Press/release animations, tap-hold visualization
- Launcher mode with app icons

**✅ Window Management Actions**
- 13 window actions implemented (left/right halves, 4 corners, maximize, center, undo)
- Display switching (move window across monitors)
- Space switching (move window between virtual desktops)
- Action URI system: `keypath://window/{action}`

**✅ Leader Key (Current Behavior)**
- Single key activator (Space/Caps/Tab/Grave)
- Momentary layer activation (hold Space → activate layer)
- UI configuration exists (SingleKeyPickerContent)

### What's Missing

**❌ Sequence Detection**
- Leader → "w" → activate window layer
- Currently MAL-45 (Kanata defseq support)
- Kanata DOES support sequences, KeyPath doesn't expose them

**❌ Context-Specific Overlay Display**
- When window layer activates, show that layer's key mappings
- Needs visual menu showing available actions
- Should auto-dismiss after action or timeout

**❌ Dedicated Window Management Layer**
- Window actions not organized onto a dedicated layer
- Would need window commands mapped to home row keys

## How This Relates to MAL-38

**MAL-38 Original Issue:**
> "Leader Key: Add visual menu overlay (expectation mismatch)"

**What we determined:**
- Current implementation is a momentary layer activator (correct)
- Users expected Mac "leaderkey" app behavior (visual menu)
- Priority lowered to Medium - current behavior works fine

**This Request Extends MAL-38:**
- MAL-38 was about showing overlay when leader is pressed
- **This request** is about showing **context-specific overlays** after sequence
- This is actually MORE sophisticated than MAL-38

## Implementation Roadmap

### Phase 1: Sequence Support (~500 lines, 2-3 days)

**Already tracked as MAL-45: "Kanata: Add sequences (defseq) UI support"**

**What's needed:**
1. Model `defseq` in Swift config types
2. Add sequence definition UI
3. Generate `defseq` blocks in Kanata config
4. TCP event handling for sequence completion

**Example defseq:**
```lisp
(defseq window-leader
  (space w))  ; Leader → w activates window layer

(defalias
  spc (tap-hold 200 200 space (layer-while-held navigation)))
```

**Files to modify:**
- `Sources/KeyPathAppKit/Models/SequenceConfig.swift` (new, ~100 lines)
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataConfigurationGenerator.swift` (+150 lines)
- `Sources/KeyPathCore/TCP/KanataTCPEvent.swift` (+50 lines for sequence events)
- `Sources/KeyPathAppKit/UI/SequenceEditorView.swift` (new, ~200 lines)

### Phase 2: Window Management Layer (~200 lines, 1 day)

**What's needed:**
1. Define window actions on a dedicated layer
2. Map to home row keys (H, J, K, L, M, etc.)
3. Wire into layer system

**Example layer definition:**
```swift
let windowLayer = Layer(
    name: "Window Management",
    mappings: [
        "h": .action("keypath://window/left"),
        "l": .action("keypath://window/right"),
        "k": .action("keypath://window/maximize"),
        "j": .action("keypath://window/center"),
        "y": .action("keypath://window/top-left"),
        "u": .action("keypath://window/top-right"),
        "b": .action("keypath://window/bottom-left"),
        "n": .action("keypath://window/bottom-right"),
        "m": .action("keypath://window/next-display"),
        "z": .action("keypath://window/undo")
    ]
)
```

**Files to modify:**
- `Sources/KeyPathAppKit/Services/RuleCollectionCatalog.swift` (+100 lines)
- `Sources/KeyPathAppKit/Models/LayerDefinition.swift` (+50 lines)
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataConfigurationGenerator.swift` (+50 lines)

### Phase 3: Context-Aware Overlay Display (~300 lines, 2 days)

**What's needed:**
1. When window layer activates, show visual menu overlay
2. Display available key mappings for that layer
3. Auto-dismiss after action or timeout
4. Animate in/out smoothly

**Architecture:**
```swift
// In LiveKeyboardOverlayView
@State private var activeContextLayer: Layer?
@State private var showContextMenu = false

// When layer change event received
func handleLayerChange(_ layerName: String) {
    if layerName == "Window Management" {
        activeContextLayer = findLayer(named: layerName)
        withAnimation(.spring()) {
            showContextMenu = true
        }

        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.spring()) {
                showContextMenu = false
            }
        }
    }
}
```

**Files to modify:**
- `Sources/KeyPathAppKit/UI/LiveKeyboardOverlayView.swift` (+150 lines)
- `Sources/KeyPathAppKit/UI/ContextMenuOverlay.swift` (new, ~150 lines)

**Visual Design:**
```
┌─────────────────────────────────────────┐
│  Window Management (Press a key)       │
├─────────────────────────────────────────┤
│  [H] Left Half      [L] Right Half      │
│  [K] Maximize       [J] Center          │
│  [Y] Top-Left       [U] Top-Right       │
│  [B] Bottom-Left    [N] Bottom-Right    │
│  [M] Next Display   [Z] Undo            │
└─────────────────────────────────────────┘
```

## Implementation Complexity Assessment

### Total Effort
**~1,000 lines of code across 3 phases**
**~5-7 days of development**

### Breakdown

| Phase | Lines | Days | Difficulty |
|-------|-------|------|------------|
| Sequence Support (MAL-45) | ~500 | 2-3 | Medium (Kanata integration) |
| Window Layer Definition | ~200 | 1 | Easy (existing patterns) |
| Context Overlay Display | ~300 | 2 | Medium (UI coordination) |
| **Total** | **~1,000** | **5-7** | **Medium** |

### Why It's Not Difficult

**✅ Building on Existing Infrastructure:**
1. **Layer system exists** - just need to define new layer
2. **Overlay system complete** - just add context menu variant
3. **Window actions work** - just need to organize onto layer
4. **Kanata supports sequences** - just need to model and generate

**✅ Clear Implementation Path:**
- Phase 1 (MAL-45) is already scoped and understood
- Phase 2 is straightforward layer definition
- Phase 3 enhances existing overlay (proven pattern)

**✅ No Major Architectural Changes:**
- All primitives exist: layers, actions, overlays, TCP events
- Just combining them in a new way
- No new subsystems required

### Risk Factors

**🟡 Moderate Risks:**
1. **Sequence timing** - Getting timeout/debounce right for Leader → w
2. **Overlay coordination** - Ensuring context menu doesn't conflict with main overlay
3. **Escape handling** - User should be able to cancel out of sequence

**🟢 Low Risks:**
- Window actions already work reliably
- Layer system is mature and tested
- Overlay rendering is proven

## Recommended Approach

### Option A: Incremental (Recommended)

**Ship in stages:**
1. **v1.1**: Implement MAL-45 (sequence support) - enables manual config
2. **v1.2**: Add window management layer - organizes actions
3. **v1.3**: Add context-aware overlay - full visual menu

**Pros:**
- De-risks each phase
- Can validate with users along the way
- Each release adds value
- Easier to test and debug

### Option B: All-at-Once

**Ship complete feature in v1.1**

**Pros:**
- Complete feature all at once
- Better UX (no intermediate states)
- Single testing/validation cycle

**Cons:**
- Bigger implementation (5-7 days)
- Higher risk if issues found
- Harder to isolate bugs

## Recommendation

**Go with Option A (Incremental)**

**Reasoning:**
1. MAL-45 is already planned as a separate ticket
2. Each phase delivers standalone value
3. Lower risk approach for a major UX change
4. User feedback can shape later phases

**Timeline:**
- **v1.1** (2-3 days): MAL-45 sequence support
- **v1.2** (1 day): Window management layer
- **v1.3** (2 days): Context overlay display

**Total: 5-6 days across 3 releases**

## Related Tickets

- **MAL-38**: Leader Key visual overlay (lowered to Medium, future enhancement)
- **MAL-45**: Kanata sequences (defseq) UI support (Phase 1 of this plan)
- **MAL-46**: Layer-toggle and layer-switch (related layer enhancements)

## User Value

**Why this is worth doing:**

1. **Discoverability** - Users can see available window actions without memorization
2. **Vim-like workflow** - Leader → w feels natural for Vim users
3. **Context switching** - Different overlays for different contexts (window, apps, etc.)
4. **Extensibility** - Pattern can extend to other contexts:
   - Leader → a → app launcher overlay
   - Leader → s → symbol layer overlay
   - Leader → n → navigation overlay

**This transforms KeyPath from "keyboard remapper" to "contextual command palette"**

## Conclusion

**Implementation difficulty: Medium (5-7 days)**

**Not difficult because:**
- All infrastructure exists (layers, overlays, actions, TCP)
- Just combining existing pieces in a new way
- No new core systems required
- Well-scoped with clear phases

**Recommended approach: Incremental (v1.1, v1.2, v1.3)**

**First step: Implement MAL-45 (sequence support)**
