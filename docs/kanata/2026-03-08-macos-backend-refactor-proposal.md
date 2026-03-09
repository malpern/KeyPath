# Kanata macOS Backend Refactor Proposal

## Status

Draft

## Audience

- Kanata maintainers
- KeyPath maintainers
- anyone evaluating how to support macOS Input Monitoring and VirtualHID reliably without
  compromising Kanata's cross-platform design

## Purpose

This document proposes a **narrow macOS backend refactor** for Kanata that:

1. preserves plain standalone Kanata on macOS
2. keeps Kanata's cross-platform core intact
3. enables a split-runtime architecture for macOS consumers like KeyPath

This is intentionally **not** a proposal to merge KeyPath's app architecture into Kanata.

## Executive Summary

Kanata's current macOS runtime assumes one process can safely do all of the following:

- hold macOS input-capture permission identity
- open physical keyboard devices
- run Kanata's remapping logic
- check pqrs/Karabiner DriverKit sink readiness
- emit remapped output through the pqrs VirtualHID path

That assumption is workable for the current direct macOS model, but it is too rigid for modern
macOS permission and privilege boundaries.

Recent runtime investigation showed that a user-session bundled host can successfully:

- load the Kanata runtime in-process
- validate config
- construct runtime state
- start the macOS event loop

but it still fails because the macOS event loop directly touches pqrs root-only sink state via the
DriverKit client path before a downstream privileged bridge can take over output responsibilities.

The proposed fix is to refactor the macOS backend so that:

- **input capture** remains in the user-session runtime
- **remapping logic** remains in Kanata core
- **output transport and output-health checks** become backend-pluggable

This keeps plain Kanata working with the existing direct DriverKit backend while enabling optional
alternate output backends for macOS integrations that need a split privilege model.

## Goals

### Required

1. Plain Kanata must remain installable and runnable on macOS without KeyPath.
2. Kanata's cross-platform parsing and remapping core must remain unchanged in spirit and ownership.
3. The default macOS path must continue to support the current direct DriverKit / VirtualHID model.
4. macOS backend code should gain a narrow seam that allows alternate output transport and output
   readiness implementations.
5. Downstream macOS consumers should be able to adopt a split-runtime model without carrying a
   large permanent fork of Kanata.

### Nice to have

1. Improved testability of macOS runtime behavior.
2. Cleaner separation of backend policy from transport mechanism.
3. Better recovery behavior across DriverKit restarts or sink loss.

## Non-Goals

1. Do not introduce a GUI requirement into Kanata.
2. Do not make KeyPath a dependency of Kanata.
3. Do not rewrite Kanata's parser, state machine, or cross-platform action logic.
4. Do not require all macOS users to adopt a split-runtime architecture.
5. Do not upstream KeyPath-specific helper, XPC, launchd, SMAppService, or permission UX code.

## Problem Statement

Today, Kanata's macOS runtime couples three concerns too tightly:

1. physical keyboard input capture
2. output event delivery
3. output sink readiness / recovery policy

In the current macOS path, the runtime does not merely emit output via pqrs/Karabiner DriverKit.
It also directly checks sink readiness from the same process. That means any process running the
macOS event loop implicitly needs to touch the pqrs root-only boundary.

That creates a problem for consumers that need:

- a **user-session process** to own built-in keyboard capture and Input Monitoring identity
- a **privileged process** to own pqrs / VirtualHID output access

The consequence is that even when output events are forwarded elsewhere, the current event loop
still reaches into the root-only pqrs path and fails before the alternate output model can take
over.

## Proposed Design

Refactor the macOS backend so that **output transport and output readiness are abstracted behind a
small backend interface**.

### Conceptual runtime split

The macOS runtime should be thought of as three layers:

1. **Input device layer**
   - opens and grabs physical devices
   - reads input events
   - regrabs/releases input devices when needed

2. **Kanata processing layer**
   - existing parsing, remapping, and action logic
   - transforms input events into output events

3. **Output backend layer**
   - emits output events
   - reports output readiness / availability
   - handles reset / modifier synchronization / tracked-key release

Only the third layer needs a new seam.

### Proposed abstraction

The macOS backend should depend on an output adapter or output backend abstraction rather than
calling pqrs/DriverKit functions directly from the event loop.

The exact Rust shape can vary, but conceptually the backend should own operations like:

- `is_ready`
- `emit_key`
- `sync_modifiers`
- `reset`
- `release_tracked_output_keys`

The event loop and recovery logic should depend on that abstraction rather than directly calling:

- `karabiner_driverkit::is_sink_ready()`
- `karabiner_driverkit::send_key(...)`

### Minimal implementation shape

The smallest upstream-friendly first step is to keep using `KbdOut` as the macOS output surface and
move readiness behind that existing type instead of introducing a KeyPath-specific runtime layer.

Concretely:

- `KbdOut` remains the owner of output emission
- macOS readiness checks move onto `KbdOut` (`output_ready`, `wait_until_ready`)
- `KbdIn` stops probing DriverKit sink readiness during input grab
- the macOS event loop depends on `kbd_out` methods rather than importing pqrs directly

That is enough to decouple the host event loop from direct pqrs readiness calls while preserving
the current direct DriverKit backend as the default implementation.

## Default and Optional Backends

### Default backend: direct DriverKit backend

This preserves current standalone Kanata behavior.

Responsibilities:

- talk directly to pqrs/Karabiner DriverKit
- remain the default macOS backend
- keep the current CLI install/run story intact

This is the path plain Kanata users continue to use.

### Optional backend: bridged output backend

This is intended for downstream integrations such as KeyPath.

Responsibilities:

- send remapped output events to a privileged companion over IPC
- receive output readiness from that companion instead of probing pqrs directly
- avoid direct access to pqrs root-only state from the user-session input host

For the current host-bridge passthrough spike, this also implies the user-session host must not
start the direct macOS DriverKit event loop when it is operating in processing-only /
bridge-owned-output mode. Otherwise the host can still instantiate the pqrs client indirectly via
the macOS input stack even if output readiness checks are abstracted.

This backend should be optional and should not be required for normal Kanata usage.

## Why This Helps Standalone Kanata

This proposal is valuable even if KeyPath did not exist.

Benefits to plain Kanata:

- cleaner macOS backend boundaries
- less mixing of runtime policy and transport details
- easier future support for alternate output modes or test backends
- fewer assumptions welded directly into the event loop

The important point is that the direct DriverKit backend remains available and remains default.

## Why This Supports Kanata's Cross-Platform Mission

This proposal is intentionally cross-platform-friendly because it does **not** move product-specific
logic into Kanata core.

It keeps the cross-platform mission intact by:

- leaving parser/state-machine/action semantics untouched
- keeping the refactor scoped to macOS backend boundaries
- preserving the existing macOS direct mode
- making alternate macOS runtime models possible without changing Linux/Windows behavior

This should be understood as a backend cleanup that reduces platform coupling, not as a
product-specific architecture change.

## What Stays Downstream in KeyPath

The following should remain KeyPath-owned and should not be upstreamed as part of this proposal:

- app bundle / GUI runtime structure
- Input Monitoring UX and permission guidance
- helper / XPC / SMAppService wiring
- installer and repair orchestration
- privileged output bridge implementation details
- launchd / deployment / packaging conventions

Kanata should provide the backend seam. KeyPath should provide one consumer of that seam.

## Proposed Upstream / Downstream Boundary

### Upstream Kanata

- macOS output backend abstraction
- direct DriverKit backend implementation
- recovery logic driven through the backend abstraction
- optional alternate backend hooks or feature-gated backend wiring

### Downstream KeyPath

- bridge-backed output backend implementation
- user-session host runtime packaging
- privileged output companion
- permission and installer UX

## Recommended Rollout

### Phase 1: behavior-preserving backend refactor

Refactor macOS output and output-health handling behind a narrow abstraction while keeping direct
DriverKit as the only production backend.

Success criteria:

- no user-visible behavior change for plain Kanata
- no KeyPath dependency
- no cross-platform behavior change

### Phase 2: optional alternate backend support

Add the ability to compile or construct a non-DriverKit output backend.

Success criteria:

- alternate backend remains optional
- direct DriverKit backend still default
- no regression for plain macOS Kanata users

### Phase 3: downstream KeyPath adoption

KeyPath adopts the alternate backend to build a split runtime:

- user-session host owns input capture and Input Monitoring identity
- privileged bridge owns pqrs output

Success criteria:

- KeyPath no longer requires the HID-owning process to touch pqrs directly
- standalone Kanata remains unaffected

## Why This Is Preferable to a Large Fork

Without this seam, KeyPath must keep carrying macOS-specific runtime patches in a forked vendored
Kanata tree. That is possible, but it increases long-term maintenance cost and makes upstream sync
harder.

A narrow backend refactor is preferable because it:

- reduces permanent downstream divergence
- gives macOS a cleaner backend structure upstream
- preserves standalone Kanata
- makes the downstream split-runtime model a consumer of a general seam rather than a custom fork

## Risks

1. Recovery behavior may become more subtle once output readiness is no longer a direct DriverKit
   call from the event loop.
2. Modifier synchronization semantics need to remain correct across backends.
3. If the abstraction is too large, it will feel product-specific and be harder to maintain.
4. If the abstraction is too small, downstream integrations will still need invasive patches.

The best mitigation is to keep the seam narrow and specific to output ownership and readiness.

## Open Questions

1. Should the output abstraction live as a trait used only on macOS, or as a more generic backend
   concept?
2. Should the alternate backend be compile-time gated, runtime selected, or both?
3. How much of recovery policy should stay in the event loop versus move into the output backend?
4. Is there a minimal upstream shape that enables downstream split-runtime work without taking on
   more macOS complexity than maintainers want?

## Suggested Pitch to Upstream

The strongest upstream framing is:

- this is a macOS backend refactor, not a KeyPath integration request
- the default Kanata behavior remains direct DriverKit and remains fully supported
- the change improves macOS backend modularity on its own merits
- the split-runtime model is just one downstream consumer of the new seam

In short:

> Preserve standalone Kanata. Refactor the macOS backend so output transport and output readiness
> are pluggable. Keep direct DriverKit as default. Let downstream consumers opt into alternate
> output ownership models without forcing those models onto Kanata itself.
