# 2026-03-08 Passthru Runtime Direct pqrs Client Creation Fix

## Problem

After the earlier macOS backend seam refactor, the signed host-passthru diagnostic no longer
failed on the old direct `is_sink_ready()` / `vhidd_server` path, but the user-session launcher
still wedged.

The stack sample narrowed the remaining issue:

- the passthru host path was still constructing the direct pqrs client in a background thread
- the sampled stack ran through:
  - `virtual_hid_device_service::client::create_client()`
  - `find_server_socket_file_path()`
  - filesystem status checks under the root-only pqrs boundary

## Diagnosis

The remaining direct pqrs client creation was not coming from `KbdOut` readiness anymore.

It was still coming from the host bridge startup path:

- `keypath_kanata_bridge_start_passthru_runtime(...)`

That function still launched:

- `kanata_state_machine::Kanata::event_loop(...)`

On macOS, `Kanata::event_loop(...)` constructs `KbdIn` from:

- `External/kanata/src/oskbd/macos.rs`

and that input path still goes through `karabiner_driverkit` functions such as:

- `driver_activated`
- `register_device`
- `grab`
- `wait_key`

So even though output readiness had been abstracted, the host-owned passthru runtime was still
starting the direct DriverKit-backed macOS input loop, which was enough to instantiate the pqrs
client in the user-session process.

## Fix

Changed the host bridge passthru runtime startup to be **processing-loop only**.

### Behavior change

`keypath_kanata_bridge_start_passthru_runtime(...)` now:

- starts `Kanata::start_processing_loop(...)`
- stores a sender for `KeyEvent` injection
- does **not** call `Kanata::event_loop(...)`

This means the host-owned passthru path no longer constructs `KbdIn` and therefore no longer
constructs the direct pqrs client through the macOS DriverKit input path.

### New bridge seam

Added:

- `keypath_kanata_bridge_passthru_send_input(...)`

This lets the passthru runtime receive injected `KeyEvent`s through the bridge-owned processing
channel without requiring the macOS hardware input loop to be started inside the user-session host.

This is still a narrow host-bridge seam, not a KeyPath-specific protocol baked into vendored
Kanata.

## Why this is acceptable for the current spike

This change does **not** claim to finish split-runtime input capture.

What it does do:

- stop the user-session passthru runtime from constructing the direct pqrs client
- keep the existing passthru output-channel seam usable
- preserve standalone direct Kanata behavior unchanged

What remains for later KeyPath-side work:

- app-owned input capture/injection wiring for real host-side input events
- bridge/session orchestration around that path

## Verification

Verified in this worktree:

- `cargo build` in `External/kanata`
- `cargo test --features passthru-output-spike` in `Rust/KeyPathKanataHostBridge`

The bridge tests now cover:

1. passthru runtime creation with an empty output queue
2. passthru runtime startup without `Kanata::event_loop(...)`
3. injected input producing channel-backed output through the processing loop

## Files changed in this step

- `Rust/KeyPathKanataHostBridge/src/lib.rs`

