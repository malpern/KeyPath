# Driverless gaps and candidate workarounds

Updated 2026-10-03. Canonical backlog for the experimental user-session backend.
Current ordered work and model assignments: [execution plan](permission-reduction-plan.md).

Implementation owner: KeyPath's existing permission, installer, lifecycle and
configuration coordinators. Kanata retains remapping semantics. Upstream work
and host deployment remain deferred. Onboarding redesign follows verification
of the reduced installation requirements.

## Status rules

Feasibility is not product integration. A candidate workaround stays unverified
until its acceptance checks pass. Unsupported configurations must be rejected
with an explanation, never silently simplified or routed to a privileged backend.
This experimental worktree selects only the session backend. The preserved
comparison worktree retains the earlier backend; unsupported session requirements
are rejected here and cannot silently select that backend. Hardware firmware work is a separate option,
not authorization to flash the ESP32 or alter the host.

| ID | Gap and customer impact | Candidate approach | Status / acceptance required |
| --- | --- | --- | --- |
| DL-01 | Caps Lock cannot be treated as ordinary press/release at the session tap. | Device-scoped macOS Caps→F18 substitution, then real Kanata. | Physical basic remap and both tap/hold branches passed. Automatic ownership, preservation of existing mappings, real F18 conflicts, normal stop, worker/parent crash, reconnect, reboot and protected-input policy remain open. Restore only mappings we own. |
| DL-02 | Secure Input blocks dynamic remapping and can interrupt it outside password fields; held-key state can become stale. | Explicit pause, release/reset and resume. A simple static OS substitution is a limited baseline candidate. | Controlled research and signed app-managed pass-through verified. App-managed automatic restart and physical remap after leaving Secure Input passed on final reviewed binary 9f0e3435; transition while holding a modifier remains open. Static substitution cannot reproduce layers/tap-hold; Caps→F18 must not strand an unusable key while paused. Test transition while a modifier is held and representative protected apps. |
| DL-03 | Session events lack keyboard identity; arbitrary per-keyboard profiles or disabling only one keyboard cannot be implemented from that stream alone. | Explore selected device-scoped substitutions into distinct trigger keys, or keyboard firmware. | Unverified beyond the fixture-scoped Caps mapping. Test two keyboards simultaneously, collisions and reconnect. Do not use timing correlation as reliable attribution. Full per-device behavior may require the advanced backend. |
| DL-04 | Synthetic Fn/Globe differs from physical hardware Fn for some macOS actions. Some external Fn keys emit no host event at all. | Preserve physical Fn and invoke equivalent KeyPath actions directly when appropriate. | Function-key semantic flags now separated from physical Fn state; regression and Caps trials passed. Built-in Apple Fn/Globe and direct equivalent actions need physical Mac tests. Firmware-only Fn is not recoverable by host software, including Karabiner. |
| DL-05 | Media, brightness, vendor and unusual international keys are rejected or unmapped by the prototype. | Extend public event coverage; test OS key normalization where supported and direct system actions. | Candidate only. Test input and output separately, supported layouts/devices, modifier combinations and F-key preference behavior. Do not claim all consumer/vendor keys can be normalized. Reject unsupported actions honestly. |
| DL-06 | Mouse movement/click/scroll actions are currently rejected. | Public Quartz mouse/scroll event output integrated with Kanata's action bridge. | Implementation gap, not established driver requirement. Test coordinates, multi-display behavior, button down/up, dragging, tagging and held-button crash cleanup. Preserve the current permission-reduction goal. |
| DL-07 | Unicode/text actions are rejected; native text injection is not universally respected by apps. | Native Unicode events, optionally explicit clipboard paste fallback. | Candidate only. Test Unicode, emoji, composition/input methods and target apps; preserve clipboard and handle asynchronous paste. Clipboard fallback is not universal typing equivalence. |
| DL-08 | User-session app does not run before login or in FileVault preboot. | Keep ordinary physical typing; compatible keyboard firmware is an alternative outside this app architecture. | Architectural boundary accepted for the simple path. No claim that a macOS driver supplies FileVault preboot remapping. |
| DL-09 | Event-tap timeout, crash, sleep/wake, session switches and OS substitutions can leave stale state or orphaned keys. | Existing lifecycle supervision, bounded nonblocking input, exact emitted-key ledger, clean state reset and owned mapping restoration. | Clean worker stop verified. Parent startup exposed and fixed a legacy VirtualHID safety shutdown; a guarded held-output worker-crash campaign is now implemented. Parent remap, Secure Input pass-through, automatic resume and held-output SIGKILL recovery passed on final reviewed binary 9f0e3435. Independent target release occurred while the same fixture run had submitted only key-down; exact final two-report trace confirmed physical key-up later. Earlier transport refusal remains excluded. Timeout, sleep/wake and session continuity still require integrated acceptance. This is a release gate before expanding feature scope. |
| DL-10 | Some apps may handle synthetic input differently, and keycodes versus characters differ across layouts. | Preserve physical key semantics and add explicit layout/text modes only where intended; compatibility testing. | Full ANSI/ISO/JIS, built-in/USB/Bluetooth, games/raw-input apps and remote-desktop coverage remains open. No blanket incompatibility or compatibility claim. |
| DL-11 | Not every Kanata custom action is implemented by the adapter whitelist. | Implement supported action outputs through canonical owners, expand parser-backed preflight only after testing semantics. | Layers, tap/hold, chords, one-shots and ordinary key macros do not inherently need a virtual device. Existing parser whitelist is authoritative for current eligibility; full feature parity is not asserted. Evaluate generated default packs against this whitelist before enabling the backend. |
| DL-12 | Ordinary remapped keys must repeat while held; the first physical trial emitted only one character. | Preserve explicit repeat values across the session ABI and host output queue. | Reproduced with exact ESP32 trace: 10 input events, 2 output events and one character. Root cause: physical DriverKit conversion decoded repeat as release. Repeat ABI fix committed (bc6b0d7d/local Kanata 0853689); press/repeat/release and unsupported-value real-engine regressions pass. Signed physical retest passed on binary 32c5781f: session-3826bf9efd914cae, 10 input/10 output events, nine characters, exact trace and clean stop. Final-source artifact rerun remains part of acceptance. |

## Driverless-only follow-up — October 3, 2026 Pacific

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

## Next bounded safety acceptance cases (DL-02 / DL-09)

Designed in parallel by Sol high; root checked existing worker timeout/Secure Input
exit paths. These are unexecuted acceptance requirements, not additional passes.

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

## Reviewed next slices — October 3, 2026, 8:25pm Pacific

DL-09 timeout evidence needs refinement before actual acceptance: frozen
6a35b48dd collapses `tapDisabledByTimeout`, `tapDisabledByUserInput` and the
timer observation of a disabled tap into `tap-disabled`. This does not establish
the OS timeout cause. A source-only acceptance design is being prepared; actual
callback-origin evidence and a bounded inducement must precede a physical pass.
The parent checks every250ms and report age is limited to2seconds; harness
receipt freshness is a different limit. Generic tap failure requires explicit
restart; automatic resume is currently specific to Secure Input.

DL-01's smallest proposed product slice is one exact keyboard instance with
explicit F18 reservation, after runtime stabilization. Add a pure mapping-lease
model and bounded mapping transport/journal service, then integrate worker and
parent cleanup through current lifecycle owners. Raw Caps eligibility and its
onboarding tour stay unchanged until acceptance passes.

Each mapping write must bind nonce/generation, UID, boot and exact device
instance; persist intent before mutation and verify readback. Preserve unrelated
mappings and refuse existing Caps/F18 mappings, duplicate or ambiguous devices.
Never clear the whole mapping array unconditionally. Worker restores on orderly
exit; parent restores only after independently confirming worker termination.
Failed restoration retains the journal and blocks another acquisition.

Existing HIDDeviceMonitor merges identical devices and lacks serial/registry
identity, so notifications can only prompt fresh enumeration. Registry IDs cannot
be reused across boots. Whole-array writes lack a demonstrated atomic
compare-and-set; concurrent edits and identical replacement mappings remain
ownership limitations. Real F18 from another keyboard is indistinguishable at
the session tap and requires an explicit support policy.

Acceptance must cover start/stop/cancellation, worker and parent crash separately,
Secure Input restoration and held-Caps reconciliation, reconnect/reboot and
startup journal recovery. Simultaneous parent/worker loss cannot promise immediate
restoration. Require initial physical all-up and Caps-off state and independently
observe latch/modifier state during transitions. These are design requirements,
not implemented features or new test passes.


## Minimal Caps ownership integration boundary — October 5 review

Source-only review confirmed that logical Caps inputs are deliberately rejected in configuration validation, reload admission and the worker; raw Caps also passes through. Preserve those gates until explicit managed Caps input admission and owned F18→logical Caps ingress are implemented and verified. The October5 review below supersedes the earlier effective-F18 text-rewrite proposal. Continue rejecting Caps output and unsupported raw configurations.

Use the existing ServiceLifecycleCoordinator/sessionOperationGate and worker owner-exit cleanup. A small substitution lease helper may read/write device-scoped UserKeyMapping through the evidenced hidutil interface; no new daemon, watchdog or permission grant. Preserve unrelated mapping entries. Refuse existing Caps sources, mappings involving F18, meaningful F18 profile usage and ambiguous device identity. Extend existing device identity with serial/location and current registry identity before writing. Native F18 on another keyboard is still indistinguishable at the event tap and must be an explicit eligibility limitation.

Persist only the owned device/generation, effective config hash, original map and verified applied map. Restore only when current device and map still match the owned applied state. Never clear the whole map or restore a stale snapshot over foreign changes. Read/write races are not solved by hidutil; test them rather than claiming atomic ownership.

A surviving parent restores after worker failure; a surviving worker restores after parent failure. If both die, durable restoration occurs on next launch; immediate restoration is not promised. During Secure Input pause, restore native Caps before resuming, then reapply only after physical release reconciliation and verified runtime recovery. Product support remains unimplemented. Required tests include preservation/conflicts, native F18/two keyboards, reconnect/ambiguous identity, normal stop, each crash, both-process crash/next launch, failed activation/reload rollback, reboot and Secure Input with Caps held. This narrows implementation scope and does not declare any new acceptance pass.

#### October5 implementation and transport check

Product8c2841849 adds the pure `SessionCapsMappingPolicy` and nine focused tests; no transport, durable journal or admission gate is activated. Acquisition now checks both the current event-service registry identity and uniqueness of the selected VID/PID/serial/location locator. Restoration requires the exact recorded device, boot UUID and ordered applied array. Concurrent mutation/identical replacement remains an explicit ownership limitation.

The local macOS `hidutil property --help` lists VID/PID/location/usage/transport/product as direct matching keys and says generic properties must be inside `IOPropertyMatch`; serial is not in its direct-key list. Do not assume the historical top-level SerialNumber selector actually narrowed matching. The product adapter must use the documented generic-property form where needed and independently establish exactly one matching keyboard event service and the expected registry ID before any write/readback. Matching a USB-device registry ancestor is insufficient. No host mappings were read or changed for this help-only check.

Independent source review recommends F18→logical Caps translation at worker ingress instead of a text rewrite: preserve the user config and existing reload owner, and introduce an explicit managed-Caps input capability without adding Caps to the output usage list. Reject raw Caps before translating owned F18; translate before mapped-input lookup and held-input tracking. The Rust validator must remove the unchanged-input exemption for managed Caps and validate implicit source/transparent fallbacks, source-dependent repeat, overrides and chords_v2 as well as the existing nested action traversal. Conservatively refuse unsupported advanced cases in the first slice. Reserve meaningful F18 profile input/output; another keyboard’s native F18 remains an eligibility limitation. Explicit Caps output refusal in SessionOutputState is the runtime backstop. No admission bit or ingress substitution is enabled yet.

## Caps transport checkpoint — October 5

Product8072e8ef2 implements the additive managed validator and durable mapping
lease/transport; default product admission and worker raw-Caps refusal remain.
Actual parser regressions cover virtual source/repeat leaks and reserved outputs.
The fresh ESP32 guest mapping acquire/readback/restore cycle passed under UID502,
with independent restored-map/journal/process and provider/USB cleanup. No runtime
Caps input or recovery transition was tested in that cycle. DL-01 remains open:
connect ingress/lifecycle, then qualify normal stop, crashes/next launch, failed
activation/reload, reconnect/reboot, native F18 collision and protected-input
restoration. Two seconds bound useful hidutil execution and64 KiB bounds output; child exit
is confirmed before lock release (OS termination latency is not bounded); unsupported physical HID
service shapes refuse. Nil readback is restored as equivalent empty mapping, not
literal nil. Concurrent foreign writes remain non-atomic. No extra permission,
maintained launcher, daemon or broad lab change is introduced.

The live transport receipt covers0445045e2.8072e8ef2 additionally checks persisted
journal identity before acquire mutation/after readback and confirms killed-child
exit before lease unlock; focused regressions and independent source review pass.
No separate live hardening or runtime Caps acceptance is claimed.

## Current Caps runtime checkpoint — October 5

Product053792f35 implements explicit DEBUG managed-Caps admission, generation-bound F18→logical Caps ingress, owned mapping acquisition/restoration, periodic identity checks, and mode-change restart through the existing configuration/lifecycle owners. Default launch remains off. 82 focused actual-package tests and narrow independent source review pass; the signed candidate is ready. [Source/candidate receipt](https://github.com/malpern/KeyPath/blob/experiment/macos-permission-footprint/docs/testing/evidence/2026-10-05-caps-runtime-source-checkpoint.json). Earlier statements that this runtime integration is unimplemented are historical.

DL-01/DL-09 remain open until integrated physical tap/hold, normal stop, failed activation, reload transitions, crash/next-launch, Secure Input held-key reconciliation and reconnect/reboot refusal are observed. Mapping-only acceptance does not establish these outcomes. The prototype requires one eligible physical keyboard, current exact device identity, initial all-up/Caps-off and explicit native F18 reservation.

Every HID write now has a durable mutation-in-flight marker. Confirmed child exit permits clearing it; forced death may leave an orphan writer, so a surviving marker refuses automatic recovery/restart even without an intent journal. Dead owner PIDs or elapsed time do not establish writer completion. Immediate restoration after both owners die is not promised; next-launch restoration is restricted to verified owned same-boot/device state without uncertain mutation. No extra daemon or permission is introduced.


## Integrated Caps live acceptance — October 5

Signedd80b5b9cb passed explicit managed Caps80ms→Escape and350ms→Control with real ESP32 traces, exact independent target events and all-up ledgers. Normal Quit restored the original map and cleared the journal. Separate all-up worker and parent crashes restored the map; both-owner loss retained the known lease, and same-boot normal relaunch recovered it under a new generation. A physical tap on that generation passed. Original profile/process/mapping/journal/flags and provider/template/nonpersistent-USB cleanup passed. [Selected receipt](https://github.com/malpern/KeyPath/blob/experiment/macos-permission-footprint/docs/testing/evidence/2026-10-05-caps-runtime-live-acceptance.json).

DL-01 is partially accepted, not closed: held-Control recovery, Secure Input reconciliation, reload mode crossing, reconnect/reboot and forced-death uncertain-marker refusal remain. The600ms hold emitted expected repeat flags then release, so exact-two-notification assumptions are invalid beyond the OS repeat delay. Default launch without selection produced no worker or mutation; exact refusal cause/prompt error remains a diagnostic gap. DEBUG selection, one keyboard and reservedF18 remain limitations. No new permission or daemon was introduced; Accessibility plus Input Monitoring remain required. DL-09 genuine OS timeout and observer-specific retirement remain unverified. Onboarding follows the remaining core gates.
