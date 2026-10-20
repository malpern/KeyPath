# Caps mapping recovery after keyboard reconnection

## Reproduction (2026-10-11)

A signed driverless candidate passed physical Caps-to-Escape input before and
after a guest reboot. Disconnecting and reconnecting the same physical keyboard
in that boot stopped remapping, and normal Restart refused recovery permanently.
The journal named event-service registry ID 4294968128; the replacement service
was 4294969211 with the same vendor, product and location. No mutation-in-flight
marker remained.

## Cause

`SessionCapsMappingLease.restore` required the original service to appear in the
current eligible-keyboard list before it could retire the journal. That was safe
against restoring onto a replacement, but made disappearance unrecoverable.
Additionally, persisted keyboard selection checked boot identity without checking
whether its registry instance still existed, so automatic selection kept using
the disconnected service ID in the same boot.

## Resolution and boundaries

Recovery first queries the exact registry ID among registered IOKit services.
An empty match alone is insufficient: an unregistered service may still exist
in the registry. The fallback walks the complete IOService registry plane,
without keyboard eligibility filters, and accepts absence only after successful
entry-ID reads and valid iterator exhaustion. Lookup errors or invalid iterators
retain the journal. Same-boot and exact-owner checks still precede retirement.
An in-flight mutation marker still blocks it, because an orphan selector-based
hidutil child could target a newly
connected device. No property read or write occurs on the disappearance path;
the old service's journal is removed, never restored onto its replacement.

Persisted selection also rejects an absent instance. The existing automatic
setup policy can then discover a fresh selection only when enabled and exactly
one eligible physical keyboard is present. Explicit opt-out, ambiguous-device
refusal and worker verification remain unchanged.

## Regression evidence

The standalone durable-lease regression failed on the old code with
`ambiguousDevice` after simulating registry ID 42 being replaced by 43. It passes
with retirement enabled, alongside the existing lease safety scenarios. Added
XCTest coverage exercises replacement present, no keyboard present, lookup
failure, a live registry entry omitted from keyboard enumeration, owner/boot
mismatch and in-flight marker retention. Selection coverage requires a stale
same-boot instance to be rejected and a live exact instance to remain accepted.

## Signed physical acceptance

Final candidate SHA256 e0d9631936fe82393ed6d4cef449d080ed025ca9992a57b115f9c1970752994a passed in owned macOS 26.5.2 lease cbx_0c7a1188aed2. Baseline worker 2459, reconnect worker 3337 (same parent 1499), and reboot worker 824 (new parent 395) each produced two physical Escape down/up pairs with fixture 2884855553BC. No Caps latch transition, F18 leakage, stuck modifier, or held output. Reconnect recovery used the normal health/status setup flow; automatic startup completed without quitting the parent. Reboot automatically relaunched the app, retained Accessibility, and refreshed device selection. Normal Quit emptied the exact physical service's UserKeyMapping and removed the journal. Fixture detached; lease destroyed and independently absent from provider inventory.

Regressions: combined red 3 failures/10 passes; green 54 focused tests plus 25 related lifecycle/Caps tests, zero warnings. Artifacts: /Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_0c7a1188aed2/20261012T010747Z. Hydration stop marker warned during destroy; VM deletion succeeded.
