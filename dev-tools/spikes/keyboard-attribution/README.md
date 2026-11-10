# Keyboard attribution spike (2026-11-09)

**Question:** can KeyPath tell which physical keyboard each key came from,
so per-keyboard remapping could return as an opt-in feature?

The session runtime reads keys through a CGEventTap, which merges all
keyboards into one stream. Per-device rules have been unsupported since the
driverless runtime became the only one: the session engine refuses
`macos-dev-names-*` (`Rust/KeyPathKanataHostBridge/src/session_config.rs`).

**Approach under test:** also watch every keyboard through IOHIDManager. That
stream names the device but needs Input Monitoring. Then match each tap event
to the HID event for the same key and direction by timestamp.

`main.swift` records both streams and matches them offline when it stops. It
stores key codes only, never text. Build and run:

```bash
swiftc -O -target arm64-apple-macos27.0 -o kb-attribution main.swift
./kb-attribution --seconds 120 [--csv out.csv]
```

It needs Input Monitoring for whatever launches it (Terminal, or a wrapper
`.app` with `NSInputMonitoringUsageDescription`).

Limits of the tool:
- Its HID-to-keycode table covers letters, digits, punctuation, Return, Escape,
  Delete, Tab, Space, the arrows and, since 2026-11-10, the eight modifiers
  (usages 0xE0–0xE7). Modifier tap events are `flagsChanged`; the tool reads down
  or up from that key's device flag bit. Caps Lock and other keys (F-keys,
  Home/End, the keypad, the ISO `#` key) are skipped on the HID side, so their
  tap events always come out unattributed.
- The summary it prints matches with two windows (30 ms behind / 5 ms ahead, and
  50 / 50 ms), each by both clocks, so the clocks are compared fairly.
- **It sees KeyPath's own re-posts.** With KeyPath's session runtime running,
  every key reaches the tap twice: the original, then KeyPath's re-post 4–6 ms
  later. The tool's own summary counts both, so its "unattributed" figure is
  about half the tap events in that case. Per-press scoring (below) keeps the
  first of each pair. A real implementation sits inside KeyPath's tap and skips
  its own tagged output, so it never sees the second copy.
- If macOS disables the tap (timeout or secure input), the tool re-enables it and
  prints a warning, because tap counts are then incomplete. The 2026-11-09 runs
  used a build without this check; their HID and tap totals agreed except where
  same-key merging explains the gap.

## What happened

1. **First run, on the mini:** inconclusive.
   - The ESP32 HID fixture delivered 202 reports, but neither stream saw any of
     its arrow keys.
   - Someone was typing on the cl80 keyboard at the time. The HID stream caught
     only 10 of about 60 tap events.
   - The agent shell (under the Claude app) likely had only partial Input
     Monitoring, so the results are not trustworthy.
   - The raw CSV was deleted.
2. **A clean macOS 27 VM** (lease `cbx_687d083c91c3`):
   - The fixture was attached through the Parallels Devices menu, and the guest
     saw it as a HID keyboard.
   - The run stopped at the guest's Input Monitoring password prompt. The lab's
     credential helper is disabled on Parallels, and the agent does not enter
     passwords.
   - The lease was destroyed, and the fixture is back on the host with
     autoconnect left at "ask".

## Lessons

- **Lab VM bundles:** four lab VM bundles were owned by the disabled
  `restore-helper` account, so no desktop VM could clone. They were chowned to
  malpern through a sudo lease on 2026-11-09.
- **Fixture attachment:** Parallels refuses a persistent USB binding for this
  fixture ("does not support bypassing the host OS"). Attach it transiently from
  the VM window's Devices > USB menu. The window belongs to the separate
  "macOS VM" app, not Parallels Desktop.
- **Opening Parallels Desktop restarted its service and stopped the running
  lab VM.** Expect that, and restart the VM with `prlctl start`.
- **Deployment target:** build for the guest's macOS version. A binary built on
  27.3 fails to launch on 27.0 with LaunchServices error -10825.

## Results on the mini (2026-11-09, KBAttribution.app with Input Monitoring)

| Run | Tap events | Matched to a keyboard | Ambiguous | Repeats given a device* | Tap minus HID (p50 / p95 / max) |
|---|---|---|---|---|---|
| Fixture only | 41 | 41 (100%) | 0 | 29 of 29 | 1.1 / 6.1 / 10.2 ms |
| Fixture and a person typing on the cl80 | 923 | 923 (100%) | 0 | 152 of 152 | 1.1 / 5.4 / 9.2 ms |

\* A repeat inherits the device of the last matched press. The tool does not
check that device again, so this column counts repeats that got a device, not
repeats proven correct.

**Ground truth.** The fixture sends only arrow keys, and all 606 events credited to it
were arrows. All 317 events credited to the cl80 came from typing: 292 other keys and 25
arrows.

**Event timestamps and callback arrival times give the same answer**, so either clock
works. The tap stream trails the HID stream by about 1 ms, and by at most about 10 ms.

**Not exercised in these two runs: the same key pressed on two keyboards within a few
milliseconds.** The person's arrow presses were at least 9.3 s from the fixture's. The
overlap run below tests that case on purpose.

## Same-key overlap run (2026-11-09, first attempt)

The fixture tapped Right arrow 400 times (20 ms down, every 50 ms) while a person
tapped Right arrow on the cl80 for about 25 seconds.

| | Count |
|---|---|
| HID events (both keyboards, down + up) | 1093 |
| Tap events: fresh presses and releases | 933 |
| Tap events: autorepeat | 80 |
| Ambiguous, by event timestamp | 122 (13%) |
| Ambiguous, by callback arrival | 316 |
| Credited to the fixture / the cl80 | 730 / 203 |
| Tap minus HID (p50 / max / min) | about 1.3 / 27 / −3.9 ms |

**macOS merges overlapping presses of the same key.** While one keyboard holds Right
arrow, a press of Right arrow on the other produces no new tap event. A release on
either keyboard ends the press (confirmed by the 2026-11-10 rerun below). That is why HID shows 160 more events than the tap
stream, and why 80 autorepeats appear when neither keyboard held the key that long. So
in this case, the merged stream does not record which keyboard is holding the key.

Every tap event was credited to some keyboard, but per-press correctness was not
scored: the raw CSV was deleted before that analysis ran. A rerun is planned. It will
score each credited press against the fixture's known schedule and measure how close
two presses must be before the choice is wrong.

**Consequence for a feature:** a per-keyboard rule cannot be exact when the same key is
down on two keyboards at once. It needs a defined fallback for that window (see the
per-keyboard rules ADR).

**Open question, separate from attribution.** In the fixture-only run, 202 USB reports
produced only 41 key presses, and both streams agreed on that count. In the two-keyboard
run, 3×202 reports produced all 606 events.

## Same-key overlap rerun (2026-11-10), scored per press

Same setup as the first attempt: the fixture taps Right arrow 400 times (20 ms
down, every 50 ms) while a person taps Right arrow on the cl80. This time the raw
rows were kept until a scorer had run, then deleted.

**How truth was rebuilt.** Each keyboard's HID stream says when its key went down
and up. From the two streams the scorer builds the tap stream macOS should have
produced under two merge rules, and keeps the one that matches the real tap
stream:

| Merge rule | Real tap events with no expected event | Expected events that never appeared |
|---|---|---|
| The press ends when *every* keyboard has released | 211 | 27 |
| The press ends on the *first* release from either keyboard | 20 | 10 |

So macOS ends a merged press on the first release. Each real tap event's truth is
the keyboard that produced its expected event. 828 tap events got a truth label
(65 from the cl80, 763 from the fixture); 20 did not.

**Result, with the ADR-048 rules** (30 ms behind / 5 ms ahead, closest candidate
consumed, two keyboards fall back, a release follows its press):

| | Count |
|---|---|
| Presses credited to the right keyboard | 402 of 413 |
| Presses credited to the wrong keyboard | **0** |
| Presses that fell back: candidates from both keyboards | 10 |
| Presses that fell back: no HID match | 1 |
| Releases credited to the right keyboard | 381 |
| Releases credited to the press's keyboard although the other keyboard's release ended it | 20 (by design: the engine must see press and release on one keyboard) |
| Releases that fell back because their press did | 14 |

Releases outnumber presses (415 against 413) because merging does not pair them
one to one: a release of a merged press can be the other keyboard's, and the
20 tap events with no truth label include presses whose release did get one.
That is also why 14 releases fell back after only 11 presses did.

The scorer is `score.py` (`python3 -I score.py run.csv KEYCODE`, 124 for Right
arrow, 56 for Left Shift). The raw rows were deleted after scoring, so these
numbers are a one-off measurement; rerun the test to check them.

**How close is too close.** Every press, by distance to the other keyboard's
nearest press of the same key:

| Other keyboard's press | Presses | Fell back | Wrong |
|---|---|---|---|
| under 5 ms away | 10 | 10 | 0 |
| 5–15 ms | 15 | 0 | 0 |
| 15–30 ms | 17 | 0 | 0 |
| 30 ms or more | 371 | 1 | 0 |

**Both clocks gave identical results** with the same window. Tap minus HID was
p50 1.7 ms, p95 4.4 ms, max 29.7 ms, min −4.7 ms (the tap ahead of HID).

## Modifier keys (2026-11-10)

The fixture tapped Left Shift alone 400 times on the same schedule. Every press
and release came through as `flagsChanged` and was credited to the fixture:
398 of 398 presses and releases in one run, 130 of 130 in a second. Tap minus HID
was p50 2.4 ms, max 7.8 ms, never negative.

**Shift on two keyboards at once (rerun the same day).** The fixture tapped Left
Shift on the same schedule while the person tapped Left Shift on the cl80. Two
earlier attempts recorded the cl80's key as Left arrow; after the person released
every modifier it sent Shift normally, so the cause was a stuck key state on the
keyboard, not the tool.

| | Count |
|---|---|
| Presses credited to the right keyboard | 414 of 430 |
| Presses credited to the wrong keyboard | **0** |
| Presses that fell back: candidates from both keyboards | 16 |
| Releases credited to the right keyboard | 359 |
| Releases credited to the press's keyboard although the other keyboard's release ended it | 50 |
| Releases that fell back because their press did | 21 |

| Other keyboard's press | Presses | Fell back | Wrong |
|---|---|---|---|
| under 5 ms away | 15 | 15 | 0 |
| 5–15 ms | 21 | 1 | 0 |
| 15–30 ms | 25 | 0 | 0 |
| 30 ms or more | 369 | 0 | 0 |

macOS merges Shift from two keyboards the way it merges other keys: the first
release from either one ends the press (the "every keyboard released" rule left
343 tap events unexplained, against 43). Both clocks gave identical results. Tap
minus HID was p50 2.4 ms, max 10.3 ms, min −4.3 ms. Raw rows were deleted after
scoring.

**Fixture note.** The ESP32 fixture stopped playing partway through two of five
runs while its Wi-Fi was dropping packets (90% ping loss at worst). Playback was
fine again after unplugging and replugging it. A run that matters should check
that the fixture's HID event count equals its script's.
