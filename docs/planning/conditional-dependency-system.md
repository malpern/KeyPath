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

## Proposed Design

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
    /// Any enabled collection outputs this key (hold, tap, or mapping)
    case keyOutputExists(String)

    /// Any enabled collection has a momentary activator for this layer
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

3. Does fallbackCapability exist anywhere? (scan all enabled collections)
   └─ Yes → dependency met, no warning (power user path)
   └─ No  → UNMET — warn with recommendation to use preferred source
```

This is cheap: step 1 and 2 are O(1). Step 3 only runs when the preferred source fails, which is the uncommon case.

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
        case dormant             // Condition not met (should never appear in results)
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

### FallbackCapability Scanner

```swift
extension PackDependencyChecker {
    static func isFallbackMet(
        _ capability: FallbackCapability,
        enabledCollections: [RuleCollection]
    ) -> Bool
}
```

For `.keyOutputExists("C-S-M-A-")`:
1. Scan all enabled collections with `tapHoldPicker` configs — check `selectedHoldOutput` and `selectedTapOutput`
2. Scan all `homeRowMods` configs — check if any key outputs the target
3. Scan custom rules — check if any output matches
4. Return true on first match

For `.layerActivatable("nav")`:
1. Check all enabled collections with a `momentaryActivator` targeting that layer
2. Return true if any found

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
  - Compute downstream impact: which enabled packs depend on Hyper?
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

1. Add `condition` and `fallbackCapability` as optional fields on `PackDependency` (defaults to nil = existing behavior)
2. Extend `PackDependencyChecker.checkDependency()` to implement the priority chain
3. Add `isFallbackMet()` scanner
4. Wire Quick Launcher's Hyper dependency as the first real use case
5. Add warning surfaces incrementally (Pack Detail first)

No breaking changes. Existing dependencies without `condition` or `fallbackCapability` continue to work exactly as before.

## Implementation Order

| Phase | What | Effort |
|-------|------|--------|
| 1 | Add `condition` + `fallbackCapability` to `PackDependency`, extend checker with priority chain | 1 day |
| 2 | `isFallbackMet()` scanner for `.keyOutputExists` and `.layerActivatable` | 0.5 day |
| 3 | Quick Launcher → Hyper dependency (condition + fallback) | 0.5 day |
| 4 | Pack Detail inline warning banner | 0.5 day |
| 5 | Rules Summary warning badges | 0.5 day |
| 6 | Upstream config change warnings (Caps Lock Remap picker) | 1 day |
| 7 | Activation mode picker inline warning | 0.5 day |

Total: ~4.5 days

## Risks

- **False negatives on fallback scan:** A key mapped to Hyper on an unreachable layer won't actually work. We accept this — tracing full layer reachability is a rabbit hole. The system checks "is it configured" not "is it physically reachable through N layer hops."
- **Custom rules:** Users can map any key to Hyper via custom rules. The fallback scanner should check these too, otherwise power users who set up Hyper without a pack get false warnings.
- **UI clutter:** Mitigated by only warning for `.requires` and keeping to one line + one button.
- **Performance:** Fallback scan is rare (only when preferred source fails) and cheap (linear scan of ~20 collections). No caching needed initially.
