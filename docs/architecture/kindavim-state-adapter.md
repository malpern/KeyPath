# KindaVim State Adapter

## Purpose
`KindaVimStateAdapter` provides a single, production-safe bridge from KindaVim runtime signals into KeyPath UI state.

Primary signal:
- `~/Library/Application Support/kindaVim/environment.json`

Secondary hook (optional, future):
- Karabiner variable bridge (when a provider is supplied)

## Contract
The adapter emits a strict snapshot model:
- `mode`: `insert | normal | visual | unknown`
- `source`: `json | karabiner | fallback`
- `confidence`: `high | medium | low`
- `timestamp`: last emitted snapshot timestamp
- `isStale`: whether the last known non-fallback signal is stale

It also exposes:
- `isEnvironmentFilePresent`
- `rawModeValue`
- `lastErrorDescription`

## Behavior
- Watches `environment.json` via `ConfigFileWatcher` for write/replace/delete events.
- Retries malformed reads briefly to tolerate atomic-write partial states.
- Falls back to `unknown` safely when the file is missing or invalid.
- De-noises duplicate unchanged states to avoid UI churn.
- Tracks freshness separately so stale detection remains accurate even when mode does not change.

## Known Limits
- No operator-pending, register, count, text-object, or command-sequence introspection.
- No command prediction, simulation, or outcome inference.
- Mode is only as fresh as upstream signal cadence; stale state is explicit.

## Integration Points
- Leader-hold Context HUD (`.kindaVimLearning` style) consumes adapter snapshots.
- Rules panel config controls whether KindaVim uses:
  - contextual coach + cheatsheet,
  - cheatsheet only,
  - standard key list.

## Future Hooks
- Replace/augment fallback with richer upstream event streams if KindaVim exposes structured command-state events.
- Add telemetry on stale durations and source quality for tuning confidence and timeout behavior.
