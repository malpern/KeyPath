# Driverless gaps and candidate workarounds

Updated 2026-10-03. Canonical backlog for the experimental user-session backend.
Implementation owner: KeyPath's existing permission, installer, lifecycle and
configuration coordinators. Kanata retains remapping semantics. Upstream work
and host deployment remain deferred. Onboarding redesign follows verification
of the reduced installation requirements.

## Status rules

Feasibility is not product integration. A candidate workaround stays unverified
until its acceptance checks pass. Unsupported configurations must be rejected
with an explanation, never silently simplified or routed to a privileged backend.
The optional driver backend remains available for requirements the session
backend cannot faithfully reproduce. Hardware firmware work is a separate option,
not authorization to flash the ESP32 or alter the host.

| ID | Gap and customer impact | Candidate approach | Status / acceptance required |
| --- | --- | --- | --- |
| DL-01 | Caps Lock cannot be treated as ordinary press/release at the session tap. | Device-scoped macOS Caps→F18 substitution, then real Kanata. | Physical basic remap and both tap/hold branches passed. Automatic ownership, preservation of existing mappings, real F18 conflicts, normal stop, worker/parent crash, reconnect, reboot and protected-input policy remain open. Restore only mappings we own. |
| DL-02 | Secure Input blocks dynamic remapping and can interrupt it outside password fields; held-key state can become stale. | Explicit pause, release/reset and resume. A simple static OS substitution is a limited baseline candidate. | Controlled research pass-through verified. Integrated parent recovery remains open. Static substitution cannot reproduce layers/tap-hold; Caps→F18 must not strand an unusable key while paused. Test transition while a modifier is held and representative protected apps. |
| DL-03 | Session events lack keyboard identity; arbitrary per-keyboard profiles or disabling only one keyboard cannot be implemented from that stream alone. | Explore selected device-scoped substitutions into distinct trigger keys, or keyboard firmware. | Unverified beyond the fixture-scoped Caps mapping. Test two keyboards simultaneously, collisions and reconnect. Do not use timing correlation as reliable attribution. Full per-device behavior may require the advanced backend. |
| DL-04 | Synthetic Fn/Globe differs from physical hardware Fn for some macOS actions. Some external Fn keys emit no host event at all. | Preserve physical Fn and invoke equivalent KeyPath actions directly when appropriate. | Function-key semantic flags now separated from physical Fn state; regression and Caps trials passed. Built-in Apple Fn/Globe and direct equivalent actions need physical Mac tests. Firmware-only Fn is not recoverable by host software, including Karabiner. |
| DL-05 | Media, brightness, vendor and unusual international keys are rejected or unmapped by the prototype. | Extend public event coverage; test OS key normalization where supported and direct system actions. | Candidate only. Test input and output separately, supported layouts/devices, modifier combinations and F-key preference behavior. Do not claim all consumer/vendor keys can be normalized. Reject unsupported actions honestly. |
| DL-06 | Mouse movement/click/scroll actions are currently rejected. | Public Quartz mouse/scroll event output integrated with Kanata's action bridge. | Implementation gap, not established driver requirement. Test coordinates, multi-display behavior, button down/up, dragging, tagging and held-button crash cleanup. Preserve the current permission-reduction goal. |
| DL-07 | Unicode/text actions are rejected; native text injection is not universally respected by apps. | Native Unicode events, optionally explicit clipboard paste fallback. | Candidate only. Test Unicode, emoji, composition/input methods and target apps; preserve clipboard and handle asynchronous paste. Clipboard fallback is not universal typing equivalence. |
| DL-08 | User-session app does not run before login or in FileVault preboot. | Keep ordinary physical typing; compatible keyboard firmware is an alternative outside this app architecture. | Architectural boundary accepted for the simple path. No claim that a macOS driver supplies FileVault preboot remapping. |
| DL-09 | Event-tap timeout, crash, sleep/wake, session switches and OS substitutions can leave stale state or orphaned keys. | Existing lifecycle supervision, bounded nonblocking input, exact emitted-key ledger, clean state reset and owned mapping restoration. | Clean worker stop verified. Parent startup exposed and fixed a legacy VirtualHID safety shutdown; a guarded held-output worker-crash campaign is now implemented. Parent recovery, held output, timeout, sleep/wake and session continuity still require integrated acceptance. This is a release gate before expanding feature scope. |
| DL-10 | Some apps may handle synthetic input differently, and keycodes versus characters differ across layouts. | Preserve physical key semantics and add explicit layout/text modes only where intended; compatibility testing. | Full ANSI/ISO/JIS, built-in/USB/Bluetooth, games/raw-input apps and remote-desktop coverage remains open. No blanket incompatibility or compatibility claim. |
| DL-11 | Not every Kanata custom action is implemented by the adapter whitelist. | Implement supported action outputs through canonical owners, expand parser-backed preflight only after testing semantics. | Layers, tap/hold, chords, one-shots and ordinary key macros do not inherently need a virtual device. Existing parser whitelist is authoritative for current eligibility; full feature parity is not asserted. Evaluate generated default packs against this whitelist before enabling the backend. |

| DL-12 | Ordinary remapped keys must repeat while held; the first physical trial emitted only one character. | Preserve explicit repeat values across the session ABI and host output queue. | Reproduced with exact ESP32 trace: 10 input events, 2 output events and one character. Root cause: physical DriverKit conversion decoded repeat as release. Fix and real-engine regression in progress; signed physical retest required. |

## Delivery order

1. Finish current reduced-permission product acceptance: stable signed identity,
   AX-first/effective-access gates, configuration routing, parent supervision,
   Secure Input recovery, revocation/regrant and runtime continuity.
2. Close DL-01/DL-09 mapping ownership and recovery before declaring Caps product
   support or making the backend the default.
3. Investigate common media keys and Fn equivalents, then mouse and Unicode.
   These are follow-up experiments, not prerequisites to accepting the explicitly
   limited prototype. Measure any added permission or installation step.
4. Investigate limited per-device normalization; retain honest advanced-backend
   eligibility for unsupported semantics.
5. Redesign onboarding around the verified permission set and explain the
   remaining restrictions before enabling a profile. No silent feature loss.

## Evidence and sources

Caps feasibility: `evidence/session-runtime/cbx_92ff62339803-caps-path-1791068598.json`.
Current implementation/provenance: [implementation record](permission-reduction-implementation.md).
Bounded research: `/private/tmp/keypath-permission-footprint/docs/testing/permission-exploration-results.md`.

- [Apple TN2450](https://developer.apple.com/library/archive/technotes/tn2450/): static OS substitutions; not a stateful remapping engine.
- [Karabiner architecture](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md#the-difference-of-event-grabbing-methods): Secure Input, device identity and synthetic Fn constraints. Its event-tap fallback still outputs through VirtualHIDDevice, so that setting does not remove the driver.
- [Karabiner hardware limitations](https://karabiner-elements.pqrs.org/docs/getting-started/features/#current-limitations): firmware-only Fn handling.
- [Apple Quartz events](https://developer.apple.com/documentation/coregraphics/cgevent): mouse and keyboard output APIs.
- [Apple Unicode output](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)): applications may ignore the supplied Unicode string.
