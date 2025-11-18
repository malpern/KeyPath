# Layer Architecture for Dynamic Keyboard Visualization

## The Vision

KeyPath should show a real-time, interactive keyboard visualization that displays:
1. **Current active layer(s)** - What layer am I on right now?
2. **Held key effects** - What keys are currently held and what are they doing?
3. **Available actions** - What will happen if I press any key right now?
4. **Context awareness** - How does current app/system state affect mappings?
5. **Kanata state** - What's Kanata's internal state? (combos, sequences, tap-hold timers)

## Why This Matters for Layer Architecture

To build this visualization, we need layers to be **queryable, composable, and stateful**.

### Requirements from Visualization Perspective

1. **Layer Stack Visibility**
   - At any moment, know the complete layer stack (not just "current layer")
   - Example: Base layer + Navigation layer (momentary) + App-specific overrides
   - Must be able to query: "What layers are active RIGHT NOW?"

2. **Key Resolution Chain**
   - For any physical key, trace resolution: Base → Layer 1 → Layer 2 → App Override
   - Must be able to query: "If I press 'H' right now, what will happen and why?"
   - Show transparency: "This key isn't mapped on Navigation, falls through to Base"

3. **Temporal State Tracking**
   - Know what keys are currently held and their state
   - Example: Space is held → Navigation layer active → but tap-hold timer still running
   - Combos in progress: "You pressed 'j', if you press 'k' within 200ms → combo fires"

4. **Predictive Display**
   - Show what WILL happen, not just what IS
   - Example: Holding Space shows Navigation layer mappings BEFORE you press another key
   - Tap-hold keys show BOTH possibilities: "Tap=Space, Hold=Nav Layer"

5. **Context Integration**
   - Layer activation can depend on: focused app, battery state, time of day, external devices
   - Visualization must show: "These mappings are active BECAUSE you're in VS Code"

## Architectural Implications

### What This Rules Out

❌ **Option 1 (Layers as Implicit Collection Features)**
- Doesn't work: Can't query layer stack, collections are black boxes
- Problem: No way to know if multiple collections are contributing to current state
- Visualization gap: Can't explain WHY a key does what it does

❌ **Option 3 (Hybrid - Collection-Owned Layers)**
- Problematic: Namespacing ("vim.navigation") makes composition hard
- Visualization issue: How to show "vim.navigation" + "custom.navigation" + "app.vscode.navigation"?
- Too complex for real-time display

### What This Favors

✅ **Option 4 (Managed Resources with Smart Defaults)**
- Layer stack is explicit: [Base, Navigation, Symbols]
- Clear composition: Multiple sources contribute to standardized layers
- Easy to query: "What's on Navigation layer?" → merge all contributors
- Natural visualization: Show "Navigation Layer" with contributions from Vim + Custom Rules + App Overrides

✅ **Plus: First-Class Layer State Management**
- Need a `LayerStateManager` that tracks:
  - Active layers right now
  - Why they're active (Space held, toggled, app-triggered)
  - What keys are held and their timers
  - Pending combos/sequences

## Proposed Architecture: Layers as Observable State Machines

### Alignment with Proven Patterns (QMK/ZMK/Kanata)

Research shows that 4 standard layers cover 80% of use cases across the keyboard remapping community:

1. **Base** - Default typing layer (QWERTY/Dvorak/Colemak)
2. **Navigation/Extend** - Arrow keys, page up/down, home/end, text editing (covers "Nav" needs)
3. **Numbers + Symbols** - Numbers, punctuation, special characters (combines "Num" and "Sym")
4. **Media + System** - Function keys, media controls, volume, brightness (combines "Fn" and "Media")

This 80/20 pattern is consistently seen across:
- QMK's recommended layouts (Miryoku, Callum)
- ZMK's common layer patterns
- Kanata's example configurations
- Community keyboard layouts (r/ErgoMechKeyboards)

**Key Insight:** Most users need 3-4 layers maximum. Additional layers (mouse, gaming, app-specific) are power-user features, not defaults.

### Core Model

```swift
/// Standard layer names - the "slots" in the layer system
/// Based on proven 80/20 patterns from QMK, ZMK, and Kanata communities
enum StandardLayer: String, CaseIterable {
    case base           // Default typing layer
    case extend         // Navigation + editing (arrows, word nav, selection, undo/redo)
    case symbols        // Numbers + symbols (1-9, 0, !, @, #, etc.)
    case media          // Media + system (F-keys, volume, brightness, playback)

    // Optional power-user layers (not in default 80/20)
    case mouse          // Mouse movement and clicks (for ergonomic/gaming keyboards)
    case gaming         // Gaming-specific (WASD preserved, etc.)
    case appSpecific    // App-conditional overrides (IDE, browser, terminal)
}

/// How a layer gets activated
/// Mirrors Kanata's layer activation mechanisms (defcfg layer-switch)
enum LayerActivator: Codable {
    case alwaysActive                    // Base layer (Kanata: default layer)
    case momentary(key: String)          // Hold key (Kanata: layer-while-held)
    case toggle(key: String)             // Tap to switch, tap again to return (Kanata: layer-toggle)
    case oneShot(key: String)            // Active for next keypress only (Kanata: one-shot)
    case appContext(bundleId: String)    // Active when app is focused (custom extension)
    case systemState(condition: String)  // Battery low, external monitor, etc. (custom extension)
}

// Note: Kanata also supports tap-hold for layer activation (tap for one action, hold for layer)
// This is handled by tap-hold configurations, not layer activators directly

/// Configuration for a standard layer
struct LayerConfiguration: Identifiable {
    let id: StandardLayer
    var activators: [LayerActivator]  // Multiple ways to activate
    var priority: Int                  // Higher priority layers override lower
    var isEnabled: Bool
}

/// A mapping contribution to a layer from any source
struct LayerContribution {
    let sourceId: UUID           // Collection, custom rule, or app profile
    let sourceName: String       // "Vim", "My Custom Rules", "VS Code Profile"
    let targetLayer: StandardLayer
    let mappings: [KeyMapping]
    let priority: Int            // Within the layer, which contribution wins?
}

/// Real-time state of the layer system
struct LayerState: Equatable {
    let activeLayerStack: [ActiveLayer]  // Ordered by priority
    let heldKeys: Set<HeldKey>
    let pendingActions: [PendingAction]  // Tap-hold timers, combo windows
    let timestamp: Date
}

struct ActiveLayer {
    let layer: StandardLayer
    let activatedBy: ActivationReason
    let contributions: [LayerContribution]  // All sources feeding this layer
}

enum ActivationReason {
    case alwaysActive
    case keyHeld(key: String, heldSince: Date)
    case toggled(by: String, toggledAt: Date)
    case appContext(bundleId: String)
    case systemState(condition: String)
}

struct HeldKey {
    let key: String
    let pressedAt: Date
    let activeActions: [KeyAction]  // What this held key is currently doing
}

enum KeyAction {
    case activatingLayer(StandardLayer)
    case modifier(Modifier)
    case tapHoldPending(tapAction: String, holdAction: String, decidesAt: Date)
    case comboPossible(keys: [String], expiresAt: Date)
}
```

### Layer State Manager

```swift
@MainActor
class LayerStateManager: ObservableObject {
    // Observable state for UI
    @Published private(set) var currentState: LayerState

    // Configuration
    private var layerConfigs: [StandardLayer: LayerConfiguration]
    private var contributions: [LayerContribution]

    // Real-time queries for visualization
    func resolveKey(_ key: String) -> KeyResolution {
        // Trace through layer stack to find what this key does
        // Returns: which layer handles it, what action, why
    }

    func activeLayersRightNow() -> [ActiveLayer] {
        // Current layer stack with reasons
    }

    func whatWillHappen(if key: String, isPressedNow: Bool) -> [PossibleOutcome] {
        // Predictive: what are all possible outcomes?
        // Example for tap-hold: [.tap("space"), .hold(.activateLayer(.navigation))]
    }

    func whyIsThisMappingActive(_ mapping: KeyMapping) -> ActivationChain {
        // Explain: Base → Vim Collection → Enabled → Navigation Layer → Space Held
    }
}

struct KeyResolution {
    let key: String
    let handledBy: StandardLayer
    let action: KeyAction
    let contributedBy: LayerContribution
    let fallbackChain: [StandardLayer]  // Layers checked before finding this
}

struct ActivationChain {
    let steps: [ActivationStep]
}

enum ActivationStep {
    case layerEnabled(StandardLayer)
    case collectionEnabled(name: String, id: UUID)
    case activatorTriggered(LayerActivator, reason: String)
    case priorityWon(over: [String])
}
```

## How This Enables Visualization

### 1. Real-Time Keyboard Display

```swift
struct KeyboardVisualizationView: View {
    @ObservedObject var layerState: LayerStateManager

    func colorForKey(_ key: String) -> Color {
        let resolution = layerState.resolveKey(key)
        switch resolution.handledBy {
        case .base: return .gray
        case .navigation: return .blue
        case .symbols: return .purple
        // ... etc
        }
    }

    func labelForKey(_ key: String) -> String {
        let outcomes = layerState.whatWillHappen(if: key, isPressedNow: false)
        if outcomes.count == 1 {
            return outcomes[0].displayLabel
        } else {
            return outcomes.map { $0.shortLabel }.joined(separator: "/")
        }
    }
}
```

### 2. Layer Stack Indicator

```swift
struct LayerStackView: View {
    @ObservedObject var layerState: LayerStateManager

    var body: some View {
        VStack {
            ForEach(layerState.activeLayersRightNow()) { active in
                HStack {
                    Text(active.layer.rawValue.capitalized)
                    Text(active.activatedBy.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
```

### 3. Key Inspector (Hover/Click to Explain)

```swift
struct KeyInspectorView: View {
    let key: String
    @ObservedObject var layerState: LayerStateManager

    var body: some View {
        let resolution = layerState.resolveKey(key)
        VStack(alignment: .leading) {
            Text("Key: \(key)")
                .font(.title)
            Text("Action: \(resolution.action.description)")
            Text("From: \(resolution.contributedBy.sourceName)")

            Divider()

            Text("Resolution Chain:")
            ForEach(resolution.fallbackChain) { layer in
                Text("  \(layer) → \(layer.hasMapping(key) ? "Found" : "Transparent")")
            }
        }
    }
}
```

### 4. Tap-Hold Feedback

```swift
struct TapHoldIndicator: View {
    @ObservedObject var layerState: LayerStateManager

    var body: some View {
        ForEach(layerState.currentState.heldKeys.filter { $0.hasTapHoldPending }) { held in
            if case .tapHoldPending(let tap, let hold, let decidesAt) = held.activeActions.first {
                HStack {
                    Text("Tap: \(tap)")
                    ProgressView(value: timeUntil(decidesAt))
                    Text("Hold: \(hold)")
                }
            }
        }
    }
}
```

## How Collections, Rules, and Layers Integrate

### 1. Collections Contribute to Standard Layers

**Key Principle:** Collections don't OWN layers, they CONTRIBUTE mappings to standard layers.

This aligns with how the community thinks about layers:
- Layers are semantic slots: "What am I trying to do?" (navigate, type symbols, control media)
- Collections provide proven mapping sets: "How do I do it?" (Vim-style, Emacs-style, gaming layout)
- Multiple collections can contribute to the same layer (Vim navigation + custom paste command)

```swift
// Vim collection contributes to the "extend" layer (navigation + editing)
RuleCollection(
    name: "Vim",
    mappings: [
        KeyMapping(input: "h", output: "left"),
        KeyMapping(input: "j", output: "down"),
        KeyMapping(input: "k", output: "up"),
        KeyMapping(input: "l", output: "right"),
        // ... more vim mappings
    ],
    targetLayer: .extend,  // Contributes to standard "extend" layer
    suggestedActivator: .momentary(key: "space")  // Suggestion, not enforcement
)

// At runtime, this becomes:
LayerContribution(
    sourceId: vimCollectionId,
    sourceName: "Vim",
    targetLayer: .extend,
    mappings: vimMappings,
    priority: 100  // Default collection priority
)
```

### 2. Custom Rules Extend Layers

Custom rules use the same contribution mechanism as collections. This allows users to:
- Add to existing layer mappings (extend Vim with custom shortcuts)
- Override collection mappings (change 'h' to something else on extend layer)
- Create entirely custom layers (app-specific IDE shortcuts)

```swift
// User creates custom rule
CustomRule(
    mapping: KeyMapping(input: "p", output: "C-M-v"),  // Cmd+V (paste)
    targetLayer: .extend,  // Adds to same layer as Vim
    description: "Paste in navigation mode"
)

// Also becomes a contribution:
LayerContribution(
    sourceId: customRuleId,
    sourceName: "My Custom Rules",
    targetLayer: .extend,
    mappings: [pasteMapping],
    priority: 200  // Custom rules win over collections by default
)
```

### 3. Layer Configuration Managed Separately

**Key Principle:** Layer triggers are first-class, separate from mappings.

This separation is critical because:
- Same mappings can be activated different ways (Space hold, CapsLock hold, F-key toggle)
- Users should be able to change triggers without editing collection mappings
- Different users prefer different activation mechanisms (hold vs toggle vs one-shot)

```swift
// User configures how Extend layer activates
LayerConfiguration(
    id: .extend,
    activators: [
        .momentary(key: "space"),        // Original Vim suggestion
        .momentary(key: "capslock"),     // User added this
        .appContext("com.microsoft.VSCode")  // Auto-activate in VS Code
    ],
    priority: 10,
    isEnabled: true
)
```

### 4. Visualization Shows Merged Result

**Key Principle:** Visualization shows the live layer stack and source attribution.

When user holds Space:
```
Active Layers:
  - Base (always active)
  - Extend (Space held) ← 2 contributions:
    • Vim Collection: h/j/k/l → arrows, w/b → word nav, u → undo
    • My Custom Rules: p → paste
```

When hovering over 'p' key while Space is held:
```
Key: P
Will output: Cmd+V (Paste)
Active on: Extend layer
Contributed by: My Custom Rules
Reason: Space is held (activates Extend layer)
Resolution chain: Extend (found) ← Base (transparent)
```

This visualization pattern is inspired by QMK Configurator and ZMK Studio, which show:
- Current active layer(s)
- What each key does on each layer
- Visual indication of transparent keys (fall through to lower layers)

## Benefits of This Architecture

### For Current Features
1. ✅ Collections remain self-contained (suggest layer + activator)
2. ✅ Users can customize activators without breaking collections
3. ✅ Custom rules naturally extend collection layers
4. ✅ Clear conflict resolution (priority system)

### For Visualization
1. ✅ **Queryable**: At any moment, know exact layer stack and why
2. ✅ **Composable**: See contributions from all sources merged
3. ✅ **Stateful**: Track held keys, timers, pending actions
4. ✅ **Explainable**: Trace any key through resolution chain
5. ✅ **Predictive**: Show what WILL happen before it happens
6. ✅ **Context-aware**: App/system state integrates naturally

### For Future Features
1. ✅ App-specific profiles (layers auto-activate by app)
2. ✅ Conditional layers (battery low → enable power-saving layer)
3. ✅ Combo visualization (show combos in-progress)
4. ✅ Sequence tracking (multi-key sequences with visual feedback)
5. ✅ Learning mode (suggest optimizations based on usage)

## Implementation Path

### Phase 1: Standard Layers (Current Priority)
- Define `StandardLayer` enum with 4 default layers (base, extend, symbols, media)
- Migrate Vim collection to target `.extend` layer
- Create `LayerConfiguration` for user customization
- Show basic layer indicator in UI (what layer am I on?)

**Goal:** Users can see "Base" or "Extend" indicator when switching layers

### Phase 2: Contribution System
- Implement `LayerContribution` model
- Merge mappings from collections + custom rules at runtime
- Priority/conflict resolution (custom rules > collections > defaults)
- Show sources in UI ("Vim + 2 custom rules on Extend layer")

**Goal:** Multiple sources can contribute to same layer, with clear precedence

### Phase 3: State Tracking
- Implement `LayerStateManager` with @Published state
- Track active layers in real-time (observing Kanata state changes)
- Monitor held keys via Kanata TCP notifications
- Publish state updates for SwiftUI reactivity

**Goal:** Real-time layer stack updates as user presses/releases keys

### Phase 4: Basic Visualization
- Show current active layer stack (Base + Extend when Space held)
- Color-code keys by which layer handles them
- Display key labels based on active layer ("H" shows "←" when Extend active)

**Goal:** QMK Configurator-style keyboard view showing current mappings

### Phase 5: Advanced Visualization
- Key inspector (hover to explain resolution chain)
- Tap-hold indicators (visual countdown for tap vs hold decision)
- Combo progress (show partial combo state)
- Resolution chain display (Base → Extend → AppSpecific)

**Goal:** Full transparency into "why does this key do what it does right now?"

### Phase 6: Context Integration
- App-specific layer activation (auto-enable IDE layer in VS Code)
- System state conditions (enable power-saving layer on battery)
- External device detection (enable gaming layer when controller connected)
- Smart suggestions based on usage patterns

**Goal:** Context-aware layers that adapt to user's workflow

## Conclusion

**Recommendation: Standard 4-Layer System + Contribution Model + State Management**

### Core Insights from Research

1. **4 Layers Cover 80% of Use Cases**
   - Base, Extend (nav+edit), Symbols (num+sym), Media (fn+media)
   - This pattern is proven across QMK, ZMK, Kanata communities
   - Additional layers (mouse, gaming, app-specific) are power-user features

2. **Layers Are Semantic Slots, Not Ownership Boundaries**
   - Layer = "What am I trying to do?" (navigate, type numbers, control media)
   - Collection = "How do I do it?" (Vim-style, Emacs-style, custom shortcuts)
   - Multiple collections can contribute to the same layer

3. **Layer Triggers Are First-Class Behaviors**
   - Momentary (hold), toggle (tap), one-shot (next key only)
   - Triggers should be configurable separately from mappings
   - Same mappings can be activated different ways

4. **Visualization Requires Observable State**
   - Users need to see the live layer stack
   - Show which keys are active on which layers
   - Explain why each key does what it does (source attribution)

### What This Architecture Enables

**For Users:**
- Clear mental model: "I'm on the Extend layer because I'm holding Space"
- Predictability: "If I press H right now, I'll get left arrow (from Vim collection)"
- Customization: "I can add my own shortcuts to the Extend layer alongside Vim"
- Context awareness: "My IDE shortcuts auto-activate when I'm in VS Code"

**For Visualization:**
- Real-time layer stack display
- Color-coded keyboard showing active mappings
- Resolution chain explanation (which layer handles each key)
- Tap-hold timers and combo progress indicators

**For Future Features:**
- App-specific profiles (auto-switching layers by app)
- Conditional layers (battery state, external monitors, connected devices)
- Learning mode (suggest optimizations based on usage patterns)
- Community layer sharing (import/export layer configurations)

The key insight: **Layers are the UI**. The architecture must make the current state completely transparent, queryable, and explainable in real-time. This is what makes keyboard remapping approachable instead of mysterious.
