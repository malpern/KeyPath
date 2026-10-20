# Driverless media and brightness output: technical spike

Date: 2026-10-12
Status: investigation; support remains disabled

## Decision

Keep media and brightness remapping unavailable in this release. A bounded,
output-only prototype is worth pursuing after driverless keyboard behavior and
recovery qualify on physical hardware. Do not make it a prerequisite for merging
the current driverless branch.

Start with an ordinary keyboard shortcut producing volume or playback output.
Remapping the physical media/function row is a separate input-capture project.
Treat brightness as a separate qualification milestone, not an automatic benefit
of implementing volume.

## Evidence and limits

These are source and SDK observations, not a successful hardware experiment:

| Evidence | Implication |
| --- | --- |
| `External/kanata/src/oskbd/macos.rs`, `TryFrom<KeyEvent> for InputEvent`, converts a key to a usage page/code and value | Kanata already has the vocabulary to describe consumer outputs. |
| `Rust/KeyPathKanataHostBridge/src/session_config.rs` limits supported output usages to keyboard page 7 | Enabling a UI action alone cannot make it work; parsed configuration admission must agree with transport. |
| `Sources/KeyPathCore/SessionRuntime/SessionOutputState.swift`, `translate`, accepts keyboard-page usages only | Consumer usages need their own translation and state handling. They must not be cast to virtual keyboard codes. |
| `Sources/KeyPathAppKit/Services/SessionRuntime/SessionRuntimeWorker.swift` drains bridge output, journals held keyboard output, then posts `CGEvent` keyboard events | Output transport, durable cleanup, and supervisor recovery all need coordinated changes. |
| `Sources/KeyPathAppKit/Services/SessionRuntime/SessionCapsLockOutput.swift` handles Caps as a native latch separately | A special output path is already an architectural pattern, but Caps latch success proves nothing about consumer output. |
| `Sources/KeyPathAppKit/Services/KeyboardCapture/KeyboardCapture.swift` decodes system-defined subtype 8 events | The app recognizes media events for recording. This is not proof that the session worker can suppress or emit them reliably. |
| `Sources/KeyPathRulesCore/SystemActionInfo.swift` marks playback, volume and brightness outputs unsupported | Keep this user-facing restriction until qualification passes. |

Primary platform evidence was inspected in the locally installed macOS 27 SDK:
`AppKit.framework/Headers/NSEvent.h` exposes
`otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:`;
`IOKit.framework/Headers/hidsystem/IOLLEvent.h` defines
`NX_SUBTYPE_AUX_CONTROL_BUTTONS` as 8; and
`IOKit.framework/Headers/hidsystem/ev_keymap.h` defines sound, mute,
playback and brightness key constants.

These declarations make an AppKit system-defined event prototype plausible.
They do **not** document a guarantee that a synthetic event reaches the system
media handler, that every display responds, or that all supported macOS versions
interpret the payload identically. Verify event encoding and delivery with a
small experiment before changing production admission. The inspected SDK is a
beta SDK; the shipping toolchain and supported OS matrix remain separate gates.

## Proposed implementation sequence

1. **Isolated delivery experiment.** From a signed app with the normal driverless
   permissions, construct system-defined events using SDK constants. Determine
   which posting route actually delivers paired down/up events to the intended
   system handler. Exercise volume, mute and playback separately. Capture
   observed system behavior; merely constructing an event or seeing it in a tap
   is not success.
2. **Output-only transport.** Introduce a typed consumer output enum and a narrow
   allowlist. Map HID consumer usages to native media identifiers explicitly.
   Preserve keyboard output behavior and reject every unmapped page, usage and
   invalid value. Do not generalize the existing virtual-key mapping.
3. **Lifecycle ownership.** Define press, repeat and release policy per action,
   including overlapping mappings to the same action. Audit the bridge value
   encoding: the current Kanata macOS conversion collapses press and repeat to
   value 1, so do not assume the transport preserves a distinct repeat value. Extend worker reports and
   parent recovery where a held consumer action requires release. Journal before
   posting down, and clear only after posting up, as keyboard output does.
   Verify tagging prevents reinjection loops on the chosen event route.
4. **Admission and UI.** Only after transport tests pass, admit the exact supported
   outputs in Rust and expose the same actions in Swift. Add cross-boundary
   contract fixtures so an offered action cannot be rejected or silently dropped.
   Keep consumer inputs and unqualified outputs rejected.
5. **Brightness milestone.** Test built-in display brightness independently.
   Document the qualified display scope. External monitor/DDC support is another
   feature; a passing built-in display test does not imply it.
6. **Optional future input work.** Study physical media-row suppression, Fn mode
   and device behavior only after output support is stable. Do not advertise
   physical media-key remapping based on output-only success.

A direct audio-volume API could implement an explicit “adjust volume” command,
but it may differ from native key behavior: output device selection, HUD, repeat,
and routing all need their own product decision. Avoid silently substituting it
for a promised native media key. If reliable delivery requires private APIs or
additional privileges, stop and reassess rather than expanding release scope.

## Complexity and reliability assessment

The mapping table is small. The difficult part is defining and proving delivery
and cleanup. The prototype is moderate implementation effort; production
qualification is the larger cost. No calendar estimate is justified before the
delivery experiment.

Volume and mute are the best first experiment because state changes are
observable. Playback is more ambiguous: macOS may route to a background player,
a browser media session or no player. Success must follow the system's expected
target, not merely the foreground app. Brightness adds hardware dependencies;
some external displays ignore native brightness keys.

Key risks are a missing release causing runaway repeats, an extra repeat
toggling mute/playback twice, worker death leaving an action held, a posted event
returning to the capture pipeline, and OS updates changing media routing. Secure
Input, lock/unlock, session switches and permission revocation must preserve the
existing fail-safe behavior. A VM can exercise lifecycle and parser contracts,
but is not evidence of physical audio/display behavior.

## Qualification gates before enabling an action

| Gate | Required evidence |
| --- | --- |
| Pure translation | Every admitted consumer usage has exact down/up/repeat tests; unknown usage/page/value fails closed; repeat-before-press and duplicate presses have defined behavior. |
| Configuration | Actual Rust parser accepts only implemented outputs, including outputs nested in tap-hold, tap-dance, macros and layers; consumer inputs remain rejected. |
| State and recovery | Stop, worker kill, supervisor restart and app quit during a held action leave no continuing effect; keyboard modifiers are released correctly alongside consumer output. |
| Physical Air | Verify each action on the built-in keyboard, speakers and display; compare single press and held repeat with native keys. |
| Physical external setup | Repeat with an external keyboard and headphones/audio-device changes; qualify each supported display class explicitly. |
| Playback routing | Music and a browser media session, foreground/background, multiple players and no player; record actual selected target and absence of duplicate actions. |
| Environment | Supported macOS versions, signed release build, permission deny/grant/revoke, sleep/wake, lock/unlock, Secure Input and session changes. |
| Regression | Ordinary letters, F1–F12, Caps latch, modifier shortcuts, app launch, layers and keyboard cleanup still pass. |
| UI and docs | Only qualified actions become selectable; unavailable actions explain the limitation; imported unsupported configurations preserve existing rules. |

Retain logs, build identity, OS/hardware identity and observed outcomes with the
qualification record. An unavailable test is an open gate, never a pass.

## Go / no-go

Proceed beyond the prototype only if public API delivery is repeatable on the
physical Air and the supported macOS baseline, with no new permission or driver
requirement and a defensible held-output cleanup strategy. Release volume and
playback separately from brightness if their evidence differs. Defer the feature
if correctness depends on private APIs, ambiguous cleanup, or broad hardware
exceptions that the UI cannot explain simply.
