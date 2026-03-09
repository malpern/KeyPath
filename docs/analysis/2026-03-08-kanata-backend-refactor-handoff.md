# 2026-03-08 Kanata macOS Backend Refactor Handoff

## Scope

This work stayed intentionally scoped to the vendored Kanata macOS backend seam inside this
worktree. It did **not** attempt to finish the full KeyPath split-runtime migration.

Goal addressed:

- remove direct pqrs sink-readiness coupling from the macOS user-session event loop
- preserve standalone Kanata on macOS
- keep direct DriverKit output as the default path
- make passthru / alternate output ownership possible behind a small backend seam

## Diagnosis

The blocker was not only output emission. The host runtime was still coupled to pqrs root-only
state because the macOS event loop directly imported and called:

- `karabiner_driverkit::is_sink_ready()`

and `KbdIn::new` also waited on sink readiness during input grab.

That meant a user-session host process could still die on:

- `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server`

even when output events were intended to be forwarded elsewhere.

## Changes Made

### 1. Moved macOS output readiness behind `KbdOut`

Updated vendored Kanata so the macOS event loop depends on `kbd_out` methods instead of importing
pqrs directly.

Files:

- `External/kanata/src/kanata/macos.rs`
- `External/kanata/src/oskbd/macos.rs`
- `External/kanata/src/oskbd/sim_passthru.rs`
- `External/kanata/src/oskbd/simulated.rs`

Details:

- added `KbdOut::output_ready()`
- added `KbdOut::wait_until_ready(timeout)`
- kept `release_tracked_output_keys(...)` on `KbdOut`
- removed direct `is_sink_ready()` imports from the macOS event loop
- removed the input-side sink-readiness wait from `KbdIn::new`

Result:

- the macOS host event loop no longer directly touches pqrs readiness
- direct DriverKit readiness remains implemented in the default macOS `KbdOut`
- simulated/passthru backends report ready without probing pqrs

### 2. Cleaned up the passthru constructor path

The host bridge was previously creating a normal `Kanata` runtime and then mutating:

- `runtime.kbd_out.tx_kout`

That worked for the spike, but it bypassed the intended seam.

Updated vendored Kanata to expose `Kanata::new_with_output_channel(...)` for the
`simulated_input + simulated_output` build used by the macOS passthru spike, not only for the old
`passthru_ahk` path.

Files:

- `External/kanata/src/kanata/mod.rs`
- `Rust/KeyPathKanataHostBridge/src/lib.rs`

Result:

- `keypath_kanata_bridge_create_passthru_runtime(...)` now uses
  `Kanata::new_with_output_channel(...)`
- the passthru host path now uses the vendored Kanata seam instead of reaching into `kbd_out`
  internals after construction

### 3. Documentation update

Updated:

- `docs/kanata/2026-03-08-macos-backend-refactor-proposal.md`

Added a short “minimal implementation shape” section explaining that the first upstream-friendly
step is to keep using `KbdOut` as the output surface and move readiness behind it, rather than
adding a KeyPath-specific runtime layer to Kanata.

## Tests Added

### Bridge-level passthru regression test

File:

- `Rust/KeyPathKanataHostBridge/src/lib.rs`

Test:

- creates a passthru runtime from a real config
- verifies runtime creation succeeds
- verifies the output queue starts empty

### Vendored Kanata passthru regression test

Files:

- `External/kanata/src/tests.rs`
- `External/kanata/src/tests/passthru_macos_tests.rs`

Test:

- creates a macOS passthru runtime via `Kanata::new_with_output_channel(...)`
- verifies `kbd_out.output_ready()` is true
- writes one key via the passthru output path
- verifies the event is emitted onto the output channel

## Verification Run

The following were run successfully in this worktree:

- `cargo build` in `External/kanata`
- `cargo test --features simulated_input,simulated_output passthru_runtime_output_channel_is_ready_and_emits_events` in `External/kanata`
- `cargo test --features passthru-output-spike` in `Rust/KeyPathKanataHostBridge`

## Important Boundary

This refactor does **not** claim the full app-owned split runtime is now proven end-to-end.

What is true now:

- the Kanata-side macOS event loop no longer hard-calls pqrs readiness
- the default direct DriverKit backend is still intact
- passthru/simulated output has a small readiness seam and constructor path

What is **not** yet proven in this turn:

- that the signed app-host diagnostic now runs fully past the previous root-only crash in practice
- that bridge/session readiness is fully wired into the experimental KeyPath host launch path

## Recommended Next Step For The KeyPath Agent

The next step should happen on the KeyPath side, not as more vendored Kanata refactoring.

Run the signed experimental host passthru diagnostic and answer this specific question:

- does the user-session host now advance past the former `vhidd_server` readiness crash point?

If yes:

- proceed with bridge/session readiness wiring and bounded passthru forwarding validation

If no:

- identify the remaining KeyPath-side code path that is still instantiating or invoking the direct
  DriverKit backend instead of the passthru/bridged output owner

## Things To Watch For

1. The remaining failure, if any, is likely no longer “event loop directly imported pqrs
   readiness.” That part was removed.
2. If the signed host still touches root-only pqrs state, the likely causes are:
   - the wrong runtime constructor/path is still used somewhere in KeyPath
   - another direct-output code path is being exercised outside the event loop seam
   - bridge readiness/ownership is not yet reflected in the experimental host runtime path
3. Avoid pushing KeyPath IPC or app-bundle concepts into vendored Kanata from here. The current
   seam is intentionally generic and upstream-shaped.

## Files Changed In This Turn

- `External/kanata/src/kanata/macos.rs`
- `External/kanata/src/kanata/mod.rs`
- `External/kanata/src/oskbd/macos.rs`
- `External/kanata/src/oskbd/sim_passthru.rs`
- `External/kanata/src/oskbd/simulated.rs`
- `External/kanata/src/tests.rs`
- `External/kanata/src/tests/passthru_macos_tests.rs`
- `Rust/KeyPathKanataHostBridge/src/lib.rs`
- `docs/kanata/2026-03-08-macos-backend-refactor-proposal.md`

