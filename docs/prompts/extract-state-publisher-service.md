# Task: Extract StatePublisherService from RuntimeCoordinator

## Objective
Extract the UI state publishing and AsyncStream logic from `RuntimeCoordinator.swift` into a dedicated `StatePublisherService.swift` service.

## Why This Extraction?
RuntimeCoordinator (2,321 lines) contains state publishing logic that:
- Manages AsyncStream for UI state changes
- Creates state snapshots for ViewModel
- Notifies observers on state changes
- Syncs diagnostics from DiagnosticsManager

This is a self-contained concern that should be a separate service.

## Source Location
`Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift`

Look for the `// MARK: - UI State Snapshot (Phase 4: MVVM)` section (around lines 178-230).

## Target File
Create: `Sources/KeyPathAppKit/Services/StatePublisherService.swift`

## Code to Extract

1. **stateChangeContinuation** - AsyncStream continuation
2. **stateChanges** - AsyncStream property
3. **notifyStateChanged()** - Emit state to observers
4. **getCurrentUIState()** - Create state snapshot
5. **refreshProcessState()** - Trigger state refresh

## Service Structure

```swift
import Foundation
import KeyPathCore

/// Publishes UI state changes via AsyncStream for reactive ViewModel updates.
///
/// This service provides:
/// - AsyncStream for UI state changes (replaces polling)
/// - State snapshot creation for ViewModel synchronization
/// - Efficient change notification (only emits when state changes)
@MainActor
final class StatePublisherService {
    // State continuation for AsyncStream
    private var stateChangeContinuation: AsyncStream<KanataUIState>.Continuation?
    
    // State providers (injected)
    private var stateProvider: (() -> KanataUIState)?
    
    /// Stream of UI state changes for reactive ViewModel updates
    nonisolated var stateChanges: AsyncStream<KanataUIState> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.stateChangeContinuation = continuation
                // Emit initial state
                if let provider = self.stateProvider {
                    continuation.yield(provider())
                }
            }
        }
    }
    
    /// Configure the state provider
    func configure(stateProvider: @escaping () -> KanataUIState) {
        self.stateProvider = stateProvider
    }
    
    /// Notify observers that state has changed
    func notifyStateChanged() {
        guard let provider = stateProvider else { return }
        let state = provider()
        stateChangeContinuation?.yield(state)
    }
    
    /// Get current state snapshot
    func getCurrentState() -> KanataUIState? {
        stateProvider?()
    }
}
```

## Integration Pattern

After extraction, RuntimeCoordinator should delegate:

```swift
// In RuntimeCoordinator:
let statePublisher = StatePublisherService()

// In init():
statePublisher.configure { [weak self] in
    guard let self else { return KanataUIState.empty }
    return self.buildUIState()
}

// Replace notifyStateChanged() calls:
private func notifyStateChanged() {
    statePublisher.notifyStateChanged()
}

// Expose stream:
nonisolated var stateChanges: AsyncStream<KanataUIState> {
    statePublisher.stateChanges
}
```

## Git Workflow

```bash
git checkout master
git pull
git checkout -b refactor/extract-state-publisher-service
# Make changes
swift build
swift test
git add -A
git commit -m "refactor: extract StatePublisherService from RuntimeCoordinator"
git push -u origin refactor/extract-state-publisher-service
```

## Validation

1. `swift build` passes
2. `swift test` passes (60 tests)
3. UI still updates reactively when state changes

## Estimated Size
~80 lines of clean, focused code

