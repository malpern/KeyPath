# A modal alert inside a main-actor task froze the app's async work

**Found:** 2026-10-19, while verifying the overlay layer reveal on the Air.

## Symptom

After the first non-base layer change of a session, layer changes from
`keypath://layer/...` reached `ActionDispatcher` but nothing downstream ran:
no `[App] Layer action dispatched` log, no overlay reveal, no shortcut list.
The app was not hung; AppleEvents and synchronous handlers still ran.

## Cause

`KeyboardVisualizationViewModel.rebuildLayerMappingForLayer` builds the layer's
key map in a `Task`, and when the simulator fails for most keys it calls
`showSimulationFailureAlert` via `await MainActor.run { ... }`. That called
`NSAlert.runModal()` inside the main-actor job. A `sample` of the main thread
showed the modal loop nested under that task's closure. Every other main-actor
`Task` (for example `ActionDispatcher.onLayerAction`) queued behind it until
someone dismissed the alert. On the Air the alert sat behind the lock screen.

## Fix

The alert still appears once per layer, but `runModal()` now runs from its own
`DispatchQueue.main.async` block, after the task that built the mapping has
finished, so it no longer holds that task open.

## Rule

Never call `runModal()` (or anything else that spins a nested run loop) from
inside a Swift concurrency task on the main actor. Use a sheet, a non-modal
window, or hop to a plain main-queue block first.

## Still open

Why the nav layer's simulation fails for 77/77 keys on the Air, including on
healthy runs, is a separate investigation.
