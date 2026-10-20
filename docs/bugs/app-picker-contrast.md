# Tour app-picker contrast and QA — 2026-10-11

The light tour applied a custom dark foreground to its descendants, but the native app-picker sheet could retain the system dark appearance. App names and heading therefore rendered as dark ink over a dark sheet.

The picker now owns an explicit light surface and matching foreground, sets a light SwiftUI color scheme, and requests a light native presentation. The chooser keeps existing app selection and browsing behavior.

A rendered regression (`FirstSuccessAppPickerAppearanceTests.testPickerOwnsReadableSurfaceInsideDarkSheet`) recreates the inherited dark foreground/system-dark combination. The old code failed the surface assertion (red component 0.213 versus minimum 0.85); the fix passes. Focused validation passed 44 XCTest cases plus 33 Swift Testing reload/recovery cases, zero compiler warnings; 380 files passed accessibility checks. Developer ID signature passed deep/strict verification. Candidate ZIP SHA-256: 7e1e3683b8fdf75d42cbd5b5a1557c4386fa36db727b335958e7aaf44b983392. Installed on the Air, reopened with Ready status. Installed chooser visual confirmation remains pending.

## Recovery status correction

The older tour handoff incorrectly carried forward an open recovery item after its later fix. `work/recovery/restart-recovery-notes.txt` records actual successful recovery in lease cbx_112536399cec: without a fixture, Caps activation remained saved-but-not-active; after reconnecting ESP32 2884855553BC, Try Again started worker 2178 while parent 737 stayed unchanged. Physical run caps-39c094f044c7426c9f41 produced two Escape down/up pairs, no Caps latch changes or F18 leakage, and released outputs. Normal Quit restored UserKeyMapping to null. This is verified reconnection recovery, distinct from a full reboot/reselection run.

## Fresh VM check

Owned macOS 26.5.2 lease cbx_527e79dd990d used the preceding tour-sizing build (archive f3cebbc085ebe9abc9518a71c4a3458d389b113ef58d9522ea9c6a18d87c7814). Welcome showed Get Started above the privacy text. Explicit Get Started opened Accessibility setup. Normal macOS authentication using a disposable test administrator granted Accessibility; KeyPath's own PermissionOracle reported AX granted, and the application automatically reached tour step 1, skipping healthy Summary.

Physical continuation was blocked by lab USB attachment: the controller's --device-connect call stalled, the ESP32 remained Present-On-Host YES / Connected-To-Vm NO, and the owned stalled CLI process was terminated. No physical result or fresh reboot/reselection success is claimed. No other USB devices were changed.
