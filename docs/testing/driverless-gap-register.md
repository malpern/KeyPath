# Driverless gaps and candidate workarounds

Updated 2026-10-06. Current gaps for the driverless user-session backend.
The [October 3 execution plan](permission-reduction-plan.md) is historical;
current acceptance scope is recorded here and in the primary evidence below.

Implementation owner: KeyPath's existing permission, installer, lifecycle and
configuration coordinators. Kanata retains remapping semantics. Upstream work
and host deployment remain deferred. Normal Accessibility/Input Monitoring
consent and onboarding have signed acceptance; final candidate and distribution
qualification remain separate gates.

## Status rules

Feasibility is not product integration. A candidate workaround stays unverified
until its acceptance checks pass. Unsupported configurations must be rejected
with an explanation, never silently simplified or routed to a privileged backend.
This build does not offer an automatic advanced-driver fallback. Hardware
firmware work is a separate option, not authorization to flash the ESP32 or
alter the host. Accessibility and Input Monitoring remain required; Full Disk
Access and browser-history import have been removed.

| ID | Gap and customer impact | Candidate approach | Status / acceptance required |
| --- | --- | --- | --- |
| DL-01 | Caps Lock cannot be treated as ordinary press/release at the session tap. | Device-scoped macOS Caps→F18 substitution, then real Kanata. | Non-debug production opt-in, physical Caps tap→Escape/hold→Control, Disable restoration and disabled-consent startup refusal passed on signed `567b285fc` with one ESP32 fixture. Earlier signed cases cover owned restoration, disconnect/replacement-identity refusal and held-Control worker/parent crash cleanup. Previous-boot record retirement passed with constructed valid records, not a physical reselect test. One selected keyboard/current boot and explicit F18 reservation remain required; customer keyboards and reboot/reselection remain open. Restore only mappings we own. |
| DL-02 | Secure Input blocks dynamic remapping and can interrupt it outside password fields; held-key state can become stale. | Explicit pause, release/reset and resume. A simple static OS substitution is a limited baseline candidate. | Controlled research and signed app-managed pass-through verified. App-managed automatic restart and physical remap after leaving Secure Input passed on final reviewed binary 9f0e3435; earlier signed held-Caps evidence separately verifies generated Control release before physical Caps-up and fresh-worker remapping after Secure Input. That receipt preserves its failed original checker and does not claim full modifier all-up or continuous transition. Representative protected apps and other held-modifier cases remain open. Dynamic remapping in password/Secure Input contexts is an accepted limit. |
| DL-03 | Session events lack keyboard identity; arbitrary per-keyboard profiles or disabling only one keyboard cannot be implemented from that stream alone. | Explore selected device-scoped substitutions into distinct trigger keys, or keyboard firmware. | Managed Caps is limited to one explicitly selected eligible keyboard. Two-keyboard attribution, arbitrary per-device filtering and reconnect compatibility remain unverified. Do not use timing correlation as reliable attribution or imply a driver fallback is available in this build. |
| DL-04 | Synthetic Fn/Globe differs from physical hardware Fn for some macOS actions. Some external Fn keys emit no host event at all. | Preserve physical Fn and invoke equivalent KeyPath actions directly when appropriate. | Function-key semantic flags are separated from physical Fn state. Signed native-F18 handback diagnostics observed retained Function clear on the first ordinary q→a input; that is not general all-modifier-up acceptance. Built-in Apple Fn/Globe, F-key preference behavior and direct equivalent actions need physical Mac tests; generic ESP32 reports do not qualify Apple hardware Fn. Firmware-only Fn is not recoverable by host software, including Karabiner. |
| DL-05 | Media, brightness, vendor and unusual international keys are rejected or unmapped by the prototype. | Extend public event coverage; test OS key normalization where supported and direct system actions. | Candidate only. Test input and output separately, supported layouts/devices, modifier combinations and F-key preference behavior. Do not claim all consumer/vendor keys can be normalized. Reject unsupported actions honestly. |
| DL-06 | Mouse movement/click/scroll actions are currently rejected. | Public Quartz mouse/scroll event output integrated with Kanata's action bridge. | Implementation gap, not established driver requirement. Test coordinates, multi-display behavior, button down/up, dragging, tagging and held-button crash cleanup. Preserve the current permission-reduction goal. |
| DL-07 | Unicode/text actions are rejected; native text injection is not universally respected by apps. | Native Unicode events, optionally explicit clipboard paste fallback. | Candidate only. Test Unicode, emoji, composition/input methods and target apps; preserve clipboard and handle asynchronous paste. Clipboard fallback is not universal typing equivalence. |
| DL-08 | User-session app does not run before login or in FileVault preboot. | Keep ordinary physical typing; compatible keyboard firmware is an alternative outside this app architecture. | Architectural boundary accepted for the simple path. No claim that a macOS driver supplies FileVault preboot remapping. |
| DL-09 | Event-tap timeout, crash, sleep/wake, session switches and OS substitutions can leave stale state or orphaned keys. | Existing lifecycle supervision, bounded nonblocking input, exact emitted-key ledger, clean state reset and owned mapping restoration. | Clean worker stop verified. Parent startup exposed and fixed a legacy VirtualHID safety shutdown; a guarded held-output worker-crash campaign is now implemented. Parent remap, Secure Input pass-through, automatic resume and held-output SIGKILL recovery passed on final reviewed binary 9f0e3435. Independent target release occurred while the same fixture run had submitted only key-down; exact final two-report trace confirmed physical key-up later. Earlier transport refusal remains excluded. Later signed cases verify held-Caps Control release after worker/parent SIGKILL, retained-uncertainty refusal when a queued real HID writer outlives its owner, and all-up observer retirement/explicit same-parent Start after Login Window. Those cases do not establish death inside an opaque HID write, held-key session continuity, sleep/wake or genuine OS tap timeout. These remain distinct acceptance gaps. |
| DL-10 | Some apps may handle synthetic input differently, and keycodes versus characters differ across layouts. | Preserve physical key semantics and add explicit layout/text modes only where intended; compatibility testing. | Full ANSI/ISO/JIS, built-in/USB/Bluetooth, games/raw-input apps and remote-desktop coverage remains open. No blanket incompatibility or compatibility claim. |
| DL-11 | Not every Kanata custom action is implemented by the adapter whitelist. | Implement supported action outputs through canonical owners, expand parser-backed preflight only after testing semantics. | Layers, tap/hold, chords, one-shots and ordinary key macros do not inherently need a virtual device. Existing parser whitelist is authoritative for current eligibility; full feature parity is not asserted. Evaluate generated default packs against this whitelist before enabling the backend. |
| DL-12 | Ordinary remapped keys must repeat while held; the first physical trial emitted only one character. | Preserve explicit repeat values across the session ABI and host output queue. | Reproduced with exact ESP32 trace: 10 input events, 2 output events and one character. Root cause: physical DriverKit conversion decoded repeat as release. Repeat ABI fix committed (bc6b0d7d/local Kanata 0853689); press/repeat/release and unsupported-value real-engine regressions pass. Signed physical retest passed on binary 32c5781f: session-3826bf9efd914cae, 10 input/10 output events, nine characters, exact trace and clean stop. Final-source artifact rerun remains part of acceptance. |

## Historical driverless-only follow-up — October 3, 2026 Pacific

This dated record is preserved; current Caps status is DL-01 above.

Caps remains a planned feature after runtime stabilization, confirmed by the
user. The current raw Caps refusal and temporary suppression of its welcome
tour do not cancel DL-01. Re-enable that first-win flow only when owned
substitution, collisions, restoration and recovery are verified.

DL-11 now has narrow generated app-specific virtual-input switch support.
Real TCP/passthrough tests prove fallback/active-app/fallback output, and the
managed save regression rejects nested Unicode before changing sources,
journals or reload state. App-only inputs also enter the captured source map;
unreferenced aliases previously hid their actions from parsed validation.
Signed physical app-specific acceptance is still pending.

The exact event-tap map currently supports F1–F20, not F21–F24. Symbolic outputs
such as `at` can be rejected where explicit supported keyboard sequences such
as `S-2` are eligible; no automatic layout-sensitive translation is claimed.
Per-device filtering remains rejected before managed writes. Generated navigation layer exit now has narrow
`ReleaseState::Layer` support: a real passthrough engine test proves that exiting
the layer preserves physical ownership of already-held keys and modifiers until
their releases. Key release, media and Unicode remain rejected. Individual
toggle/one-shot actions are eligible; the original tap-toggle transaction test is
retained. Remaining graph-profile parsing and launcher synchronization failures
are under review. Tests preserve old generator and journal-recovery coverage separately
from supported session acceptance, without a validation bypass.

## Remaining qualification order

1. Finish signed acceptance of the final candidate and fresh distribution checks.
   Existing normal two-consent/onboarding acceptance does not qualify newer bytes.
2. Keep genuine OS tap timeout separate from callback-stall, heartbeat-expiry or
   SIGKILL evidence. Preserve unverified sleep/wake and held-key session gaps.
3. Reuse the existing physical rig for bounded ordinary/modifier/layout/app
   cases. Apple Fn/Globe and built-in/Bluetooth/customer keyboards require their
   own hardware evidence; the ESP32 fixture cannot qualify that matrix.
4. Keep unsupported media, mouse, Unicode and per-device actions rejected until
   their semantics are implemented and tested. Explain eligibility before saving
   or activating a profile; no silent feature loss or advanced-driver fallback.

## Evidence and sources

Current primary receipts are in the separate permission-footprint checkout at
`/private/tmp/keypath-permission-footprint/docs/testing/evidence/`:

- `2026-10-06-production-caps-lock-acceptance.json` — production opt-in on signed `567b285fc`.
- `2026-10-05-caps-runtime-live-acceptance.json` and
  `2026-10-05-caps-secure-reload-acceptance.json` — narrowly scoped crash,
  Secure Input and configuration-transition evidence; original checker failures retained.
- `2026-10-05-caps-identity-refusal-acceptance.json` and
  `2026-10-06-caps-previous-boot-acceptance.json` — identity/refusal and constructed-record retirement.
- `2026-10-05-queued-writer-acceptance.json` — retained uncertainty across late real write.
- `2026-10-05-observer-session-acceptance.json` — all-up Login Window retirement.
- `2026-10-06-function-handback-behavior.json` — Function handback diagnostic limits.
- `2026-10-06-production-onboarding-acceptance.json` — normal two-consent/Start/Rules flow.

Historical Caps feasibility: `evidence/session-runtime/cbx_92ff62339803-caps-path-1791068598.json`.
Current implementation/provenance: [implementation record](permission-reduction-implementation.md).
Bounded research: `/private/tmp/keypath-permission-footprint/docs/testing/permission-exploration-results.md`.

- [Apple TN2450](https://developer.apple.com/library/archive/technotes/tn2450/): static OS substitutions; not a stateful remapping engine.
- [Karabiner architecture](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md#the-difference-of-event-grabbing-methods): Secure Input, device identity and synthetic Fn constraints. Its event-tap fallback still outputs through VirtualHIDDevice, so that setting does not remove the driver.
- [Karabiner hardware limitations](https://karabiner-elements.pqrs.org/docs/getting-started/features/#current-limitations): firmware-only Fn handling.
- [Apple Quartz events](https://developer.apple.com/documentation/coregraphics/cgevent): mouse and keyboard output APIs.
- [Apple Unicode output](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)): applications may ignore the supplied Unicode string.

## Historical safety checklist (DL-02 / DL-09)

Designed in parallel by Sol high; root checked existing worker timeout/Secure Input
exit paths. This original checklist is preserved. Later held-Caps Secure Input
and all-up observer receipts cover only the narrow scopes stated in DL-02/DL-09;
other variants below remain unverified. This table is not additional acceptance.

| Case | Required observation | Harness work needed |
| --- | --- | --- |
| Held generated Control enters Secure Input | Owned ledger224 and independent Control down, then secureInput exit, empty ledger and actual Control up before physical q release; controlled secure sample passes through. | Live Secure Input toggle in one target, timestamped modifier observations, parent-owned HRM config. |
| Secure Input ends while original q is still held | Fresh worker generation does not recreate Control from the old hold/repeats; after physical all-up, fresh tap/hold is balanced. | Phase-aware fixture and observations across worker generations. |
| Real OS event-tap timeout with held output | Actual tap-disabled evidence, bounded owned-worker stall, independent release before physical key-up, original typing and fresh-worker remap. | Deterministic approved timeout trigger; heartbeat expiry, simulated callback and SIGKILL are separate evidence. |
| Actual guest sleep/wake with held output | Recorded macOS sleep/wake, physical all-up reconciliation, no stuck key/modifier, one healthy runtime or explicit stopped state, supported recovery verified. | Guest sleep/wake control and phase-aware target/focus checks; VM suspend alone is not equivalent. |
| Owned console departure/return | No remapped output in another session; clean modifier state and valid console/runtime identity on return; fresh balanced tap/hold. | Phase-aware lock/session observations; fast user switching additionally needs a second owned test session. |

Each case keeps frozen binary/config identity, parent/nonce/PID/UID ownership,
exact fixture traces and output observations independent of the worker ledger.
Unavailable observation is untested, not successful. Dynamic remapping inside
protected fields remains an accepted limitation.
