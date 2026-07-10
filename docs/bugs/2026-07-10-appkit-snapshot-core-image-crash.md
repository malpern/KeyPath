# AppKit snapshot Core Image crash

## Symptom

The snapshot lane aborted with signal 11 instead of reporting a visual
mismatch. The exception was `-[NSConcreteValue CGRectValue]: unrecognized
selector` while SnapshotTesting evaluated `CILabDeltaE` for a tolerant
`NSImage` comparison under the pinned stable Xcode 26.6 toolchain.

## Root cause

SnapshotTesting's tolerant AppKit image strategy routes through a Core Image
filter that is not safe in this offscreen XCTest environment. The harness also
used the process-wide default preferences and captured immediately after
hosting, so references could contain the developer's settings or partially
loaded asynchronous icons.

## Fix

- Encode AppKit renders as PNG and compare decoded RGBA pixels without Core
  Image. Pixel precision and per-channel tolerance remain configurable.
- Give each test a unique `UserDefaults` suite through `defaultAppStorage`.
- Allow the hosted view to settle before capture and isolate its HOME directory.
- Recreate the favicon cache directory at write time because an asynchronous
  fetch may finish after an isolated test HOME has been removed.
- Refresh the three references that previously encoded machine-local state.

## Regression coverage

The 73-test snapshot lane now completes without a process crash and reports
normal assertion failures. `AppKitSnapshotStrategyLintTests` prevents the
Core Image-backed AppKit strategy from returning to the shared harness.
