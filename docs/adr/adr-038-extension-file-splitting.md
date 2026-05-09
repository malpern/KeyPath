# ADR-038: Extension-File Splitting for Large Types

## Status
Accepted

## Context

Several types exceeded 1,000 lines: `LiveKeyboardOverlayController` (1,360), `LiveKeyboardOverlayView` (1,126), `PackDetailView` (1,100). These needed to be split for readability without changing architecture.

Two approaches were considered:

1. **Separate classes/structs** — extract responsibilities into new types (e.g., `OverlayLayerStateManager`, `OverlayLauncherSession`). Requires passing shared state via init params or protocols.

2. **Extensions in separate files** — keep one type, split methods across files by responsibility (e.g., `+LayerState.swift`, `+LauncherSession.swift`). Extensions share instance state naturally.

## Decision

Use **extensions in separate files**. Each file covers one responsibility and is named `TypeName+Responsibility.swift`.

### Rules

1. **All stored properties stay in the main class/struct body.** Swift does not allow extensions in separate files to add stored properties. The core file declares everything; extensions only add methods and computed properties.

2. **`private` members accessed by extensions must be promoted to `internal`.** Swift's `private` scope is per-file. When a method moves to `+LayerState.swift`, it can no longer access `private var oneShotOverride` in the core file. Remove `private` (making it `internal`, the default).

3. **Don't over-split.** A 400-line core with 50 lines of property declarations is fine. Splitting below that scatters related code. The goal is "each file is one concern," not "each file is under 200 lines."

4. **Name extensions by responsibility, not by what they contain.** `+LayerState` not `+NotificationObservers`, `+PackActions` not `+PrivateMethods`.

### Why Not Separate Classes

The types being split (controllers, views) manage a single window/view with tightly shared state: the `NSWindow` reference, the `viewModel`, UI state flags, animation tokens. Extracting into separate classes would mean either:

- Passing 10+ properties through init (coupling without benefit), or
- Creating a shared state object (adding a new type just to avoid extensions)

Extensions give the readability win (each file is one concern) without the coupling cost.

## Consequences

- Core files are larger than ideal (~400-750 lines) because they hold all stored property declarations. This is a Swift language constraint, not a design choice.
- `internal` access is wider than `private` for promoted properties. This is acceptable within a module — these types are not public API.
- The pattern is consistent across the codebase: `LiveKeyboardOverlayController` (7 files), `LiveKeyboardOverlayView` (8 files), `PackDetailView` (6 files).
