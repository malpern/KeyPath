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

The first attempt moved `runModal()` into its own `DispatchQueue.main.async`
block. That did not work, and a second `sample` showed why: the modal loop then
sat inside a main-queue block, and the main queue is serial, so main-actor
tasks (which run through it) still waited behind the alert.

The alert is now shown as an ordinary, non-modal window by
`NonModalAlertPresenter`, which wires the alert's buttons to its own handler.
Nothing waits on it. It still appears once per layer.

## Rule

Never call `runModal()`, or anything else that spins a nested run loop, on the
main thread while the app is meant to keep working. Calling it from a main-queue
block blocks the main queue just as surely as calling it from a main-actor task.
Use a sheet or a non-modal window (`NonModalAlertPresenter`).

## Still open

Why the nav layer's simulation fails for 77/77 keys on the Air, including on
healthy runs, is a separate investigation.
