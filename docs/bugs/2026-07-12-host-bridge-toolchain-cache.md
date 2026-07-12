# Host bridge cache reused an unloadable dylib

**Status:** Fixed by #988

## Symptom

A signed, notarized release could start Kanata but log that
`libkeypath_kanata_host_bridge.dylib` was unavailable because `dlopen` rejected
its `__LINKEDIT` string pool as misaligned. The launcher fallback hid the loss
of host-bridge validation and runtime integration from normal readiness checks.

## Root cause

The Rust host-bridge build cache was keyed only by source content. An artifact
linked with a different Xcode linker could therefore be reused after the
release workflow selected KeyPath's pinned stable Xcode. Copying, signing, and
notarization preserved the already-invalid Mach-O file; they did not create the
corruption.

## Durable rule

Native artifact caches must include every build input that can affect the
binary format, including the selected developer directory, linker, Rust/Cargo
toolchain, target, and feature set. A cache key is not sufficient proof that a
native artifact is usable: the host bridge must also pass its real `dlopen` and
C-ABI smoke check before the build script returns success. A failed cached
check invalidates the hit and rebuilds; a failed newly built check stops the
release before bundle assembly.
