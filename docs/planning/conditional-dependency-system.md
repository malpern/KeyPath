# Conditional Dependency Checking System

## Problem

KeyPath packs can depend on capabilities provided by other packs, but these dependencies are **conditional** on configuration. For example:

- Quick Launcher in `holdHyper` mode needs Hyper to be reachable from *some* key — but in `leaderSequence` mode, it doesn't need Hyper at all
- Window Snapping needs a Leader key configured — but only when using leader-based activation
- The current system checks if a *specific pack* has a *specific config value*, but doesn't scan system-wide for whether the capability exists anywhere

**Result:** Users can configure themselves into broken states with no warning, or get false warnings when the capability they need is actually available through a different path.

## Principles

1. **Dependencies are conditional on the dependent's config** — Only check when the configuration that creates the need is active
2. **Check the recommended source first, then fall back to system-wide scan** — Each dependency declares where it *expects* the capability to come from. Only scan the rest of the keymap if the recommended source doesn't satisfy
3. **Warnings are informational, never blocking** — The user might have a good reason. Show the consequence, don't prevent the action
4. **Recommendations point to the preferred pack** — "Set up Hyper on Caps Lock" is actionable. "Hyper isn't available" is vague
5. **Show warnings where the user is making the decision** — On the dependent pack, on the upstream pack when changing config, and on the rules summary
6. **Collections self-report their outputs** — Each collection declares what it produces via a uniform interface, so the scanner never needs to know about specific config types. This scales to community-contributed rules without updating the checker.
7. **Config model is the source of truth** — The dependency checker reads the config model directly, not the kanata simulator. "Is Hyper configured?" is a config-time question answered by `producedOutputs`. "What happens when you press X?" is a runtime question for the simulator. Different concerns.

## Current System

### What exists
- `PackDependency` with `kind` (`.requires` / `.enhancedBy`) and optional `ConfigPredicate`
- `ConfigPredicate` checks one specific pack: `.holdOutput("C-S-M-A-")`, `.tapOutput(...)`, `.isEnabled`
- `PackDependencyChecker` evaluates predicates, returns `[UnmetDependency]`
- `RulesSummaryView` auto-enables missing deps or shows alert for config mismatches
- `PackDetailView` shows dependency cards (Requires / Enhanced by / Enhances)

### What's missing
- No fallback scan when the preferred source doesn't satisfy (power users who put Hyper on a different key get false warnings)
- No conditional activation (dependency always checked regardless of dependent's config)
- No inline warnings when changing upstream config (e.g., switching Caps Lock away from Hyper)
- `unmetDependencyMap` is computed but not displayed as badges in the rules list
- Scanner hardcodes knowledge of each config type — won't scale to community rules

## Proposed Design

### Collection Self-Reporting: `producedOutputs`

Instead of the scanner knowing how to crack open each config type, each collection reports what it produces:

```swift
extension RuleCollection {
    /// All key outputs this collection produces when enabled.
    /// Read from the config model, not the simulator.
    var producedOutputs: Set<String> {
        switch configuration {
        case .tapHoldPicker(let config):
            // Reports both tap and hold outputs
            var outputs: Set<String> = []
            if let tap = config.selectedTapOutput ?? config.tapOptions.first?.output {
                outputs.insert(tap)
            }
            if let hold = config.selectedHoldOutput ?? config.holdOptions.first?.output {
                outputs.insert(hold)
            }
            return outputs

        case .homeRowMods(let config):
            // Reports all configured modifier outputs
            return Set(config.keyConfigs.compactMap(\.holdOutput))

        case .customMappings(let rules):
            // Reports all output keys from custom rules
            return Set(rules.map(\.output))

        // ... other config types report their outputs similarly
        default:
            return []
        }
    }

    /// All layers this collection can activate.
    var activatableLayers: Set<String> {
        guard let activator = momentaryActivator else { return [] }
        return [activator.targetLayer.name]
    }
}
```

**Why this scales:** When a community contributor adds a new collection type, they implement `producedOutputs` on their config. The scanner works automatically — no central switch statement to update.

**Why not the simulator:** `producedOutputs` reads declared config, not simulated keypress results. This is a static analysis question ("what did the user configure?") not a runtime question ("what happens when key X is pressed at time T?"). The config model is the source of truth, always available, and fast to read.

### Dependency Model: Priority-Chain Checking

Each dependency declares three things:

```swift
struct PackDependency {
    // --- Existing fields (unchanged) ---
    let packID: String              // Preferred source pack
    let kind: DependencyKind        // .requires or .enhancedBy
    let configPredicate: ConfigPredicate?  // What to check on preferred source
    let description: String         // Human-readable explanation

    // --- New fields ---

    /// When this dependency applies. nil = always.
    /// Only checked when the dependent pack's own config creates the need.
    let condition: DependencyCondition?

    /// What to scan for system-wide if the preferred source doesn't satisfy.
    /// nil = don't fall back, only check preferred source.
    let fallbackCapability: FallbackCapability?
}
```

#### DependencyCondition

When the dependency is active — based on the *dependent* pack's config:

```swift
enum DependencyCondition: Codable, Equatable, Sendable {
    /// Only when launcher activation mode matches
    case launcherMode(LauncherActivationMode)

    /// Only when leader key is set to a specific key
    case leaderKeyIs(String)

    /// Generic: only when a config field equals a value
    case configEquals(field: String, value: String)
}
```

#### FallbackCapability

What to scan the entire keymap for if the preferred source doesn't satisfy:

```swift
enum FallbackCapability: Codable, Equatable, Sendable {
    /// Any enabled collection's producedOutputs contains this key
    case keyOutputExists(String)

    /// Any enabled collection's activatableLayers contains this layer
    case layerActivatable(String)
}
```

### Checking Algorithm: Priority Chain

```
1. Is the condition met? (check dependent pack's own config)
   └─ No  → dependency is dormant, skip entirely
   └─ Yes (or nil condition) → continue

2. Does the preferred source satisfy? (existing configPredicate check)
   └─ Yes → dependency met, no warning
   └─ No  → continue

3. Does fallbackCapability exist anywhere? (query producedOutputs / activatableLayers)
   └─ Yes → dependency met, no warning (power user path)
   └─ No  → UNMET — warn with recommendation to use preferred source
```

Step 1 and 2 are O(1). Step 3 is a linear scan of `producedOutputs` across enabled collections — fast even with hundreds of community rules because it's just set lookups, no simulation.

### Fallback Scanner

Uses the self-reporting interface, not hardcoded config knowledge:

```swift
extension PackDependencyChecker {
    static func isFallbackMet(
        _ capability: FallbackCapability,
        enabledCollections: [RuleCollection]
    ) -> Bool {
        switch capability {
        case .keyOutputExists(let key):
            return enabledCollections.contains { $0.producedOutputs.contains(key) }
        case .layerActivatable(let layer):
            return enabledCollections.contains { $0.activatableLayers.contains(layer) }
        }
    }
}
```

This is the entire scanner. It never needs updating when new collection types are added — they just implement `producedOutputs` and `activatableLayers`.

### UnmetDependency — Enhanced with Recommendation

```swift
struct UnmetDependency: Equatable, Sendable {
    let dependency: PackDependency
    let reason: UnmetReason
    /// The recommended pack to fix this (same as dependency.packID)
    let recommendedPackID: String
    /// Specific fix description based on what's wrong
    let fixDescription: String

    enum UnmetReason: Equatable, Sendable {
        case notEnabled          // Preferred source pack is disabled
        case configMismatch      // Preferred source enabled but wrong config
    }
}
```

`fixDescription` varies based on which check failed:
- Preferred source is off entirely → "Enable Caps Lock Remap and set hold to Hyper"
- Preferred source is on but wrong config → "Change Caps Lock Remap hold to Hyper"

The user never sees "we also checked the rest of your keymap" — the recommendation is always the preferred pack.

### Example: Quick Launcher → Hyper

```swift
// On the Quick Launcher pack:
PackDependency(
    packID: "com.keypath.pack.caps-lock-to-escape",
    kind: .requires,
    configPredicate: .holdOutput("C-S-M-A-"),
    description: "Hold Hyper mode requires a key mapped to Hyper",
    condition: .launcherMode(.holdHyper),
    fallbackCapability: .keyOutputExists("C-S-M-A-")
)
```

**Scenarios:**

| Launcher mode | Caps Lock hold | Hyper elsewhere? | Result |
|---------------|---------------|------------------|--------|
| holdHyper | Hyper | — | Met (step 2) |
| holdHyper | Control | Yes (Right Option) | Met (step 3, power user) |
| holdHyper | Control | No | **Unmet** → "Change Caps Lock hold to Hyper" |
| holdHyper | (disabled) | No | **Unmet** → "Enable Caps Lock Remap and set hold to Hyper" |
| leaderSequence | anything | anything | Dormant (step 1, condition not met) |

### Example: Window Snapping → Leader Key

```swift
PackDependency(
    packID: "com.keypath.pack.vim-navigation",
    kind: .requires,
    configPredicate: .isEnabled,
    description: "Window Snapping needs a Leader key to activate the window layer",
    condition: nil,  // Always needs a leader — no conditional
    fallbackCapability: .layerActivatable("nav")
)
```

## Warning Surfaces

### 1. Pack Detail View (inline banner) — PRIMARY
- Below the toggle, above the editor content
- Orange banner with icon: "Hold Hyper mode is active, but no key is mapped to Hyper"
- Action button: "Set up on Caps Lock" → opens Caps Lock Remap detail
- Hides when the issue is resolved or the condition changes
- Only shown for `.requires` dependencies, not `.enhancedBy`

### 2. Rules Summary List (badge on row)
- Small orange warning dot on the pack row when an unmet `.requires` dependency exists
- Tooltip shows the fix description
- Tapping the row opens Pack Detail where the full banner is visible

### 3. Upstream Config Change (inline on the pack being changed)
- When user changes Caps Lock hold output away from Hyper:
  - Compute downstream impact: which enabled packs depend on Hyper via `producedOutputs`?
  - Show inline note below the picker: "Quick Launcher uses Hyper"
  - Informational only — don't block the change
- Same pattern for Leader Key when user changes the leader key assignment

### 4. Activation Mode Picker (in-context)
- When user switches Quick Launcher to `holdHyper` and Hyper isn't reachable:
  - Show warning below the activation mode picker immediately
  - "No key is mapped to Hyper. Recommended: set up on Caps Lock."
- This is the Pack Detail banner appearing in response to the condition becoming active

## Warning Copy Guidelines

- Lead with what's broken: "Hold Hyper mode is active, but no key is mapped to Hyper"
- Recommend the preferred source: "Set up Hyper on Caps Lock" (not "find a key for Hyper")
- One line for the problem, one button for the fix
- Never mention the fallback scan — it's an implementation detail
- Only warn for `.requires`, not `.enhancedBy` — enhancements are suggestions, not requirements

## Dependency Cards (unchanged)

Pack Detail's "Requires / Enhanced by / Enhances" cards continue to show regardless of whether the dependency is met. They describe the relationship between packs. The warning banner is separate — it appears only when the dependency is actually unmet.

## Migration Path

1. Implement `producedOutputs` and `activatableLayers` on `RuleCollection` (reads config model directly)
2. Add `condition` and `fallbackCapability` as optional fields on `PackDependency` (defaults to nil = existing behavior)
3. Extend `PackDependencyChecker.checkDependency()` to implement the priority chain
4. Add `isFallbackMet()` scanner using `producedOutputs` / `activatableLayers`
5. Wire Quick Launcher's Hyper dependency as the first real use case
6. Add warning surfaces incrementally (Pack Detail first)

No breaking changes. Existing dependencies without `condition` or `fallbackCapability` continue to work exactly as before.

## Implementation Order

| Phase | What | Effort |
|-------|------|--------|
| 1 | `producedOutputs` + `activatableLayers` on `RuleCollection` | 0.5 day |
| 2 | Add `condition` + `fallbackCapability` to `PackDependency`, extend checker with priority chain | 1 day |
| 3 | `isFallbackMet()` scanner using self-reporting interface | 0.5 day |
| 4 | Quick Launcher → Hyper dependency (condition + fallback) — first real validation | 0.5 day |
| 5 | Pack Detail inline warning banner | 0.5 day |
| 6 | Rules Summary warning badges | 0.5 day |
| 7 | Upstream config change warnings (Caps Lock Remap picker) | 1 day |
| 8 | Activation mode picker inline warning | 0.5 day |

Total: ~5 days

## Risks

- **Incomplete `producedOutputs`:** If a collection type doesn't implement it, capabilities from that type won't be found by the fallback scan. Mitigated by: the preferred source check (step 2) doesn't use `producedOutputs` — it uses the existing `configPredicate`. The fallback scan is a safety net, not the primary path.
- **False negatives:** A key configured to output Hyper on an unreachable layer won't actually work. We accept this — tracing full layer reachability through the config model is a rabbit hole. The system checks "is it configured" not "is it physically reachable through N layer hops."
- **Community rule coverage:** New collection types need to implement `producedOutputs` to participate in fallback scanning. This is a lightweight protocol obligation — document it as a requirement for community rule authors.
- **UI clutter:** Mitigated by only warning for `.requires` and keeping to one line + one button.
- **Performance:** `producedOutputs` is a property computed from the config model — no simulation, no I/O. Fallback scan is a linear scan of set lookups. No caching needed initially; can add lazy caching invalidated on `ruleCollectionsChanged` if profiling shows a need.

## Future: Community Rules

When the rules system opens to community contributions, rule authors implement `producedOutputs` and `activatableLayers` on their collection config type. The dependency system works automatically:

- Their outputs are discoverable by the fallback scanner
- Other packs can declare dependencies on capabilities their rules provide
- No central registry of "what config types exist" — each type self-reports

This is the same pattern as Swift's `CustomStringConvertible` — you conform, the system uses it.
