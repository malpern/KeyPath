# Leader Key + Overlay Integration Plan

## User Vision

**Phase 1**: Make leader key work with the existing overlay keyboard
- When Leader → w activates window layer, overlay shows which keys do what
- Use existing LiveKeyboardOverlayView infrastructure
- Visual feedback integrated into keyboard display

**Phase 2**: Add standalone contextual menu (later)
- Can appear even when overlay isn't shown
- Floating menu for users who don't use overlay
- Same information, different presentation

## Current Overlay System

### What Exists Today

**LiveKeyboardOverlayView.swift** (~1,800 lines) - Complete, mature system:
- Physical keyboard rendering (MacBook layouts)
- Live key press visualization
- Layer indicator showing current layer name
- Tap-hold state display
- Launcher mode with app icons
- Remapping display (shows what key outputs)
- Floating keymap labels with animations
- Idle fade (2-stage: 10s dim, 48s hide)

**Key Components:**
- `LiveKeyboardOverlayView` - Main container
- `KeycapGrid` - Physical keyboard layout
- `OverlayKeycapView` - Individual key rendering
- `LayerIndicator` - Shows active layer name
- `KeymapLabels` - Floating labels for remapped keys

### What's Missing for Context Menu

**Need to add:**
1. Highlight available keys when layer activates
2. Show tooltip/label for each key's action
3. Dim inactive keys (ones not mapped on this layer)
4. Auto-dismiss highlighting after timeout or action

## Implementation Plan - Phase 1 (Overlay Integration)

### Step 1: Sequence Support (MAL-45) - 2-3 days

**Why first?** Need Leader → w → activate layer capability

**What to build:**
1. Model `defseq` in Swift config types
2. UI for creating sequences
3. Generate Kanata defseq blocks
4. Handle TCP sequence events

**Example sequence:**
```lisp
(defseq window-context
  (space w))  ; Leader → w

(defalias
  spc (tap-hold 200 200 space (one-shot 1000 (layer-while-held navigation))))
```

**Files:**
- `Sources/KeyPathAppKit/Models/SequenceConfig.swift` (new, ~150 lines)
- `Sources/KeyPathCore/TCP/KanataTCPEvent.swift` (+30 lines for sequence events)
- `Sources/KeyPathAppKit/UI/SequenceEditorView.swift` (new, ~200 lines)
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataConfigurationGenerator.swift` (+150 lines)

### Step 2: Window Management Layer Definition - 1 day

**Define window actions on dedicated layer mapped to home row:**

```swift
let windowManagementLayer = RuleCollection(
    id: RuleCollectionIdentifier.windowManagement,
    name: "Window Management",
    mappings: [
        KeyMapping(input: "h", output: "(keypath://window/left)"),
        KeyMapping(input: "l", output: "(keypath://window/right)"),
        KeyMapping(input: "k", output: "(keypath://window/maximize)"),
        KeyMapping(input: "j", output: "(keypath://window/center)"),
        KeyMapping(input: "y", output: "(keypath://window/top-left)"),
        KeyMapping(input: "u", output: "(keypath://window/top-right)"),
        KeyMapping(input: "b", output: "(keypath://window/bottom-left)"),
        KeyMapping(input: "n", output: "(keypath://window/bottom-right)"),
        KeyMapping(input: "m", output: "(keypath://window/next-display)"),
        KeyMapping(input: "z", output: "(keypath://window/undo)"),
        // Add more as needed
    ],
    layerName: "window-mgmt"  // Kanata layer name
)
```

**Files:**
- `Sources/KeyPathAppKit/Services/RuleCollectionCatalog.swift` (+100 lines)

### Step 3: Overlay Context Menu Integration - 2-3 days

**Enhance LiveKeyboardOverlayView to show context:**

#### 3.1: Add Context Menu State

```swift
// In LiveKeyboardOverlayView
@State private var activeContextLayer: String?
@State private var contextMappings: [KeyMapping] = []
@State private var contextHighlightEnabled = false

// When layer change event received
private func handleLayerChange(_ layerName: String) {
    if layerName == "window-mgmt" {
        // Get mappings for this layer
        contextMappings = getMappingsForLayer(layerName)
        activeContextLayer = layerName

        withAnimation(.spring(response: 0.3)) {
            contextHighlightEnabled = true
        }

        // Auto-dismiss after 5 seconds of inactivity
        scheduleContextDismissal()
    } else {
        dismissContext()
    }
}
```

#### 3.2: Enhance OverlayKeycapView

```swift
// In OverlayKeycapView
var isContextActive: Bool  // New parameter
var contextAction: String?  // What this key does in context (e.g., "Left Half")

var body: some View {
    ZStack {
        // Base keycap
        keycapBase

        // Context highlight overlay
        if isContextActive {
            if let action = contextAction {
                // Highlight this key
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.3))
                    .overlay(
                        VStack(spacing: 2) {
                            Text(keycap.uppercased())
                                .font(.system(size: 14, weight: .bold))
                            Text(action)
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                        }
                    )
            } else {
                // Dim inactive keys
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.5))
            }
        }
    }
}
```

#### 3.3: Visual Design in Overlay

**When window layer activates:**

```
┌─────────────────────────────────────────────────┐
│  [Layer: Window Management]                     │  ← Existing layer indicator
├─────────────────────────────────────────────────┤
│                                                 │
│  Q  W  E  R  T  [Y]  U   I  O  P               │
│                  ↑    ↑                         │
│             Top-Left Top-Right                  │
│                                                 │
│  A  S  D  F  G  [H] [J] [K] [L]  ;             │
│                  ↓   ↓   ↓   ↓                  │
│               Left Ctr Max Right                │
│                                                 │
│  Z  X  C  V  [B]  N  [M]                       │
│              ↑     ↑   ↑                        │
│         Bot-Left Bot-R Display                  │
└─────────────────────────────────────────────────┘

[Y, U, B, N, H, J, K, L, M] = Highlighted with action labels
[All other keys] = Dimmed (40% opacity)
```

**Key features:**
- Highlighted keys glow with blue tint
- Action label appears below key letter
- Inactive keys dimmed
- Layer indicator shows "Window Management"
- Auto-dismiss after 5s or after any key pressed

#### 3.4: Files to Modify

**LiveKeyboardOverlayView.swift** (+150 lines):
- Add context state management
- Handle layer change events for context
- Pass context info to keycap views
- Auto-dismiss logic

**OverlayKeycapView.swift** (+80 lines):
- Add context highlight rendering
- Add action label display
- Add dimming for inactive keys
- Animation for context activate/dismiss

**KanataViewModel.swift** (+30 lines):
- Track active context layer
- Provide mappings for context layer
- Context dismiss triggers

### Step 4: Wiring & Polish - 1 day

**Connect all the pieces:**
1. TCP layer change events trigger context display
2. Sequence completion triggers layer activation
3. Context auto-dismisses on key press or timeout
4. Smooth animations for context enter/exit
5. Handle escape key to manually dismiss

**Testing:**
1. Leader → w activates window layer
2. Overlay highlights H, J, K, L, etc. with labels
3. Press H → window moves left, context dismisses
4. Press Esc → context dismisses without action
5. 5s timeout → context auto-dismisses

## Phase 1 Total Effort

| Step | Lines | Days | Files |
|------|-------|------|-------|
| 1. Sequence Support (MAL-45) | ~500 | 2-3 | 4 new/modified |
| 2. Window Layer Definition | ~100 | 1 | 1 modified |
| 3. Overlay Context Integration | ~230 | 2-3 | 2 modified |
| 4. Wiring & Polish | ~50 | 1 | 3 modified |
| **Total** | **~880** | **6-8** | **10 files** |

## Phase 2: Standalone Context Menu (Later)

**Why separate?**
- Phase 1 covers users who already use overlay (majority)
- Standalone menu adds value for overlay-free users
- Can be built after validating UX with Phase 1

**What it adds:**
```
┌────────────────────────────────┐
│ Window Management (Press key)  │  ← Floating window
├────────────────────────────────┤
│ [H] Left Half                  │
│ [L] Right Half                 │
│ [K] Maximize                   │
│ [J] Center                     │
│ [Y] Top-Left    [U] Top-Right  │
│ [B] Bottom-Left [N] Bottom-Rgt │
│ [M] Next Display [Z] Undo      │
└────────────────────────────────┘
```

**Implementation** (~300 lines, 2 days):
- `ContextMenuWindow.swift` (new, ~200 lines)
- Position near cursor or screen center
- Same data model as overlay version
- Can appear even when overlay hidden

## Implementation Priority

**v1.1 Release:**
1. ✅ MAL-45: Sequence support (foundation)
2. ✅ Window management layer (organization)
3. ✅ Overlay context integration (primary UX)

**v1.2 Release:**
4. ⏳ Standalone context menu (optional enhancement)

## Benefits of Overlay-First Approach

**Advantages:**
1. ✅ Uses existing, proven overlay system
2. ✅ No new windows to manage
3. ✅ Users already familiar with overlay
4. ✅ Integrated visual language
5. ✅ Lower complexity (reuse existing rendering)

**User Experience:**
- Natural extension of overlay functionality
- Context appears where user is already looking
- Consistent with existing layer indicator
- Smooth animations already work

## Technical Architecture

### Data Flow

```
User: Leader → w
    ↓
Kanata: Sequence detected, activates window-mgmt layer
    ↓
TCP: LayerChange event → "window-mgmt"
    ↓
KanataViewModel: Updates activeLayerName
    ↓
LiveKeyboardOverlayView: Detects layer change
    ↓
    - Sets contextHighlightEnabled = true
    - Loads contextMappings for "window-mgmt"
    - Schedules auto-dismiss (5s)
    ↓
OverlayKeycapView: Each keycap checks if it has contextAction
    ↓
    - If action exists: Highlight + show label
    - If no action: Dim key
    ↓
User: Presses H
    ↓
    - Action dispatches: keypath://window/left
    - Context dismisses
    - Window moves
```

### State Management

```swift
// In KanataViewModel
@Published var activeLayerName: String = "base"
@Published var activeContextLayer: String?

func updateContextLayer(_ layerName: String) {
    // Check if this layer should show context
    if layerName == "window-mgmt" || layerName == "launcher" {
        activeContextLayer = layerName
    } else {
        activeContextLayer = nil
    }
}

// In LiveKeyboardOverlayView
@ObservedObject var viewModel: KanataViewModel

var body: some View {
    KeycapGrid(
        layout: layout,
        contextLayer: viewModel.activeContextLayer,
        contextMappings: getMappingsFor(viewModel.activeContextLayer)
    )
}
```

## Example User Workflow

### Window Management Context

**User presses:** Space (leader)
- Overlay shows Space as held (existing behavior)

**User presses:** w (while holding space)
- Sequence completes: Leader → w
- Kanata activates window-mgmt layer
- TCP event: LayerChange("window-mgmt")
- Overlay instantly highlights: H, J, K, L, Y, U, B, N, M, Z
- Each key shows action label below
- Other keys dimmed

**User presses:** H (release space first)
- Window snaps to left half
- Context highlight fades out
- Overlay returns to normal

**Alternative:** User releases space without pressing anything
- 5s timeout expires
- Context highlight fades out
- Overlay returns to normal

### App Launcher Context

**User presses:** Space → a
- Sequence activates launcher layer
- Overlay highlights: A, B, C, D, E, F, G, H, I, J...
- Shows app icon + name for each launcher
- Press key → app launches, context dismisses

## Configuration

**User preferences:**
```swift
struct ContextMenuSettings {
    var enableOverlayContext: Bool = true  // Phase 1
    var enableStandaloneMenu: Bool = false  // Phase 2
    var contextTimeout: TimeInterval = 5.0
    var showActionLabels: Bool = true
    var dimInactiveKeys: Bool = true
}
```

## Success Metrics

**Phase 1 complete when:**
- ✅ Leader → w activates window layer
- ✅ Overlay highlights available keys with labels
- ✅ Pressing action key works and dismisses context
- ✅ Timeout auto-dismisses after 5s
- ✅ Esc manually dismisses context
- ✅ Works for multiple contexts (window, launcher, etc.)

## Next Steps

**Immediate:**
1. Start with MAL-45 (sequence support)
2. Define window management layer with home row mappings
3. Enhance overlay to show context highlights

**Want me to start implementing Step 1 (MAL-45)?**
