# Media keys in the driverless session runtime

**Status:** research spike, 2026-10-19. No generator, bridge or runtime behavior changes.
**Question:** can the driverless runtime read and send brightness, volume,
playback and mute keys through indirection, the way managed Caps Lock reaches
Kanata through a hidutil mapping to a spare F-key?

**Answer:** yes for output and for most input, with three limits:

1. Brightness cannot be posted to an external display.
2. A media key's identity is lost the moment macOS converts it, so input must
   be remapped *before* conversion (hidutil) or read *after* it (the tap).
3. Only eight spare intermediates exist.

The details and the measurements behind them follow.

## How the runtime handles keys today

- **Input.** `SessionRuntimeWorker` installs one modifying `cgSessionEventTap`
  for `keyDown`, `keyUp` and `flagsChanged` only. Each key code is translated
  through `SessionKeyMap.keyCodeToUsage`, which covers the keyboard page (7) only.
  `NX_SYSDEFINED` events (CGEvent type 14) are not in the mask. They pass
  through untouched.
- **Output.** The worker drains `(value, page, code)` triples from the bridge
  and posts keyboard CGEvents. The bridge's admission check (`session_config.rs`)
  rejects any profile whose actions emit something outside the keyboard-page
  output map. That is why `brdn`/`brup`/`prev`/`pp`/`next`/`mute`/`vold`/`volu`
  produce "configuration requires the advanced driver backend".
- **Kanata's names already carry consumer usages.** On macOS,
  `External/kanata/parser/src/keys/macos.rs` maps:

  | Kanata name | `OsCode` | Page / usage |
  |---|---|---|
  | `mute` | `KEY_MUTE` | 0x0C / 0xE2 |
  | `volu`, `vold` | `KEY_VOLUMEUP`, `KEY_VOLUMEDOWN` | 0x0C / 0xE9, 0xEA |
  | `pp` | `KEY_PLAYPAUSE` | 0x0C / 0xCD |
  | `next`, `prev` | `KEY_NEXTSONG`, `KEY_PREVIOUSSONG` | 0x0C / 0xB5, 0xB6 |
  | fast-forward, rewind | `KEY_FORWARD`, `KEY_REWIND` | 0x0C / 0xB3, 0xB4 |
  | `brup`, `brdn` | `KEY_BRIGHTNESSUP`, `KEY_BRIGHTNESSDOWN` | 0x0C / 0x6F, 0x70 |
  | keyboard backlight | `KEY_KBDILLUM*` | 0xFF / 0x07–0x09 (Apple vendor) |

  So the output channel can already name these keys. Only admission and the
  worker's poster stop them.

## Rig

| Machine | Hardware | KeyPath state during the run |
|---|---|---|
| **Air** | macOS 27.2, arm64, built-in keyboard, built-in display only | App running and **session runtime running** (worker PID 27725, ready 15:46:49, holding a Caps→F19 lease) for the guided presses. App **quit** for the "quit" rows. |
| **mini** | macOS 27.2, arm64, Studio Display. Three USB keyboards: cl80, X2A, and the **KeyPath physical HID fixture** (ESP32-S3, boot-keyboard descriptor, scripted from the mini over Wi-Fi) | App running, **runtime not running** (no worker, no 37001 listener) |

Probes are standalone (`mkprobe`, `np`, `bset`; source summarized in the
appendix). The `access` probe reported `AXIsProcessTrusted=true`,
`CGPreflightPostEventAccess=true` and `CGPreflightListenEventAccess=true` on both
Macs, which matches what an app holding KeyPath's grants has. Every setting a
probe changed was restored: volume, mute, brightness, `fnState` and the
hidutil mappings.

---

## 1. Input: what reaches a session CGEventTap

### 1a. Air built-in keyboard (physical presses, runtime running)

Micah pressed F1–F12 in each mode; the listen-only probe tap recorded what
arrived. `fnState` = `defaults read -g com.apple.keyboard.fnState`; the test set
it with `defaults write` + `activateSettings -u` and restored the original
value, which was `0`.

| Key | `fnState=0` (default) | `fnState=0` + fn held | `fnState=1` | `fnState=1` + fn held |
|---|---|---|---|---|
| F1 | sysdef 8 / `NX_KEYTYPE_BRIGHTNESS_DOWN` (3) | keyDown 122 | keyDown 122 | sysdef brightness-down (3) |
| F2 | sysdef 8 / `BRIGHTNESS_UP` (2) | keyDown 120 | keyDown 120 | sysdef brightness-up (2) |
| F3 | keyDown **160** (Mission Control) | keyDown 99 | keyDown 99 | keyDown 160 |
| F4 | keyDown **177** (Spotlight) | keyDown 118 | keyDown 118 | keyDown 177 |
| F5 | keyDown **176** (Dictation) | keyDown 96 | keyDown 96 | keyDown 176 |
| F6 | keyDown **178** (Do Not Disturb) | keyDown 97 | keyDown 97 | keyDown 178 |
| F7 | sysdef `NX_KEYTYPE_REWIND` (**20**) | keyDown 98 | keyDown 98 | sysdef 20 |
| F8 | sysdef `PLAY` (16) | keyDown 100 | keyDown 100 | sysdef 16 |
| F9 | sysdef `NX_KEYTYPE_FAST` (**19**) | keyDown 101 | keyDown 101 | sysdef 19 |
| F10 | sysdef `MUTE` (7) | keyDown 109 | keyDown 109 | sysdef 7 |
| F11 | sysdef `SOUND_DOWN` (1) | keyDown 103 | keyDown 103 | sysdef 1 |
| F12 | sysdef `SOUND_UP` (0) | keyDown 111 | keyDown 111 | sysdef 0 |

Observations:

- **Nothing is lost; each key arrives as exactly one of two shapes.**
  It is either an `NX_SYSDEFINED` subtype-8 event (source pid 0) or a keyDown.
  There is no third case and no silent key.
- **F3–F6 are keyDowns with key codes 160/177/176/178.** These are not in
  `SessionKeyMap`, so the worker passes them through today. They are readable
  input if the map ever learns them.
- **F7 and F9 are REWIND/FAST (20/19), not PREVIOUS/NEXT (18/17).**
  Short presses still skip tracks (see 2c). A table that equates the Apple top
  row with `prev`/`next` is wrong at the event level.
- **Every F-key keyDown carries `NX_SECONDARYFNMASK` (0x800000),**
  even with `fnState=1` and fn not held. The worker's re-posted copy drops that
  bit when fn is up (seen in the tap: original flags `0x800100`, re-post
  `0x20000000`). That is harmless for F-keys today.
- **Hardware repeat:** a held media key repeats as `repeat=1` system-defined
  downs, the first at about 250 ms and then every **~33 ms**, followed by one up.
  A held F5 (keyDown 176) auto-repeats the same way.
- **With remapping on, the worker consumed F1–F12 in the `fnState=1` columns**
  and re-posted them. The *Function Keys* collection maps f1→f1, so the
  behavior did not change. Media-mode presses were not touched: they are
  type 14, outside its mask.

### 1b. Suppression

| Source | Tap | Result |
|---|---|---|
| Posted `SOUND_UP` ×3 (mini) | `defaultTap`, returns nil for subtype 8 | volume 56 → **56** (all 6 events seen and dropped) |
| Fixture keyboard-page VolumeUp ×3 (mini, real USB) | same | volume 75 → **75**; 6 events seen and dropped. Same presses with no tap: 75 → 94 |
| Air built-in F1, F2, F11, F12 (runtime running) | same | brightness 0.5625 → **0.5625**, volume 0 → **0**; all 4 downs seen and dropped |

The built-in display's brightness keys **are** suppressible from a session tap,
like volume. The modifying tap that would do this is the same kind the worker
already owns. Its mask would only need `1 << 14` added.

### 1c. External keyboards

- **Fixture (real USB HID, scripted).** Keyboard-page `Mute`/`VolumeUp`/`VolumeDown`
  (0x7F/0x80/0x81) arrive as `NX_SYSDEFINED` subtype 8 codes 7/0/1, source pid 0.
  They are indistinguishable from the built-in keyboard's media keys.
- **cl80 (listen-only, mini, #1309 runtime running with a Caps→F19 lease on both
  cl80 interfaces).** The board has no Fn key and no media layer. Its F10, F11 and
  F12 arrived as plain keyDowns 109, 103 and 111 (each re-posted once by the worker)
  and sent no media events. Its page-12 collection (below) was never exercised.
  Both cl80 `UserKeyMapping` arrays were identical before and after the run. An
  external board's *consumer-page* media keys therefore remain unmeasured; the
  fixture covered keyboard-page Mute/VolumeUp/VolumeDown only.

**Where an external keyboard's consumer keys live:** on the cl80 the consumer
collection (page 12, usage 1) is on its **second** event service (0x1005bb72b,
primary usage 1/2), not on its keyboard service (primary 1/6). On the X2A it is
on a vendor-page primary service. A hidutil mapping for media keys therefore
has to target the service that carries page 12. `hidutil list -m keyboard`
alone does not find it.

## 2. Output: posting system-defined events

Posting builds `NSEvent.otherEvent(.systemDefined, subtype: 8,
data1: (code << 16) | (0xA|0xB) << 8 | repeatBit)`. It posts `.cgEvent` at
`.cghidEventTap` (also tested at `.cgSessionEventTap`), tagged in
`eventSourceUserData`. The poster ran as a non-UI background process.

### 2a. Effect

| Key | mini (Studio Display) | Air (built-in display) |
|---|---|---|
| `SOUND_UP`/`SOUND_DOWN` (0/1) | ✅ one step (6.25 %) per tap | ✅ 25 → 19 → 25 |
| `MUTE` (7) | ✅ toggles `output muted` | — (not repeated) |
| `PLAY` (16) | ✅ `togglePlayPause` delivered to the now-playing app | — |
| `NEXT`/`PREVIOUS` (17/18) | ✅ `nextTrack`/`previousTrack` | — |
| `FAST`/`REWIND` (19/20), short tap | ✅ delivered as `nextTrack`/`previousTrack` | — |
| `BRIGHTNESS_UP`/`DOWN` (2/3) | ❌ **no effect.** DisplayServices reads 0.7925 before and after. `DisplayServicesSetBrightness` changes the same display, so the reading is live. | ✅ 0.594 → 0.5 → 0.5625 (snaps to 1/16 steps) |

Playback was observed with a receiver that registers `MPRemoteCommandCenter`
handlers and claims now-playing (`np`, silent audio). The posted events reached
it through the system's media routing, as hardware keys do.

`KeyPath running` vs `KeyPath quit` made no difference to any posted event
(Air: same volume and brightness steps with the app quit). This is expected:
the worker's tap mask excludes type 14.

### 2b. Latency (mini, long-lived poster, 15–16 pairs at 150 ms spacing)

| Event | Post → seen at a session tap |
|---|---|
| keyboard keyDown (F20) | median **0.57 ms**, p90 6.7 ms, max 29 ms |
| system-defined media | median **2.9 ms**, p90 6.4 ms, max 29 ms |
| system-defined `PLAY`/`NEXT`/`PREV` | post → `MPRemoteCommand` handler **35–51 ms**. This is the media router, the same path a hardware key takes. |

**Process exit races delivery.** Short-lived poster processes that exit within
about 1 ms of their last post lost 1 of 3 key pairs. Building the event
(`NSEvent.otherEvent`) on first use costs 50–60 ms. The worker is long-lived
and posts from a warm run loop, so neither applies to it. A one-shot helper
would have to linger.

### 2c. Repeat while held

- A posted **down with no up and no repeats**, held 1.5 s, moved volume 50 → **100**.
  The tap saw only the one down and the one up. **The system repeats a held
  media key itself**, so the poster needs only press and release, which is
  exactly what Kanata emits.
- Posted downs with `repeat=1` every 80 ms also work and add to that repeat.
- Hardware sends its own `repeat=1` events (~33 ms, see 1a). If the worker
  consumes an input media key, it must consume the repeats too and must not
  forward them, or volume races.

## 3. hidutil `UserKeyMapping` as the input path

### 3a. Does a mapping move a media usage before macOS converts it?

| Mapping on the fixture service | Physical press | Arrived at the tap | Volume |
|---|---|---|---|
| keyboard 0x80 (VolumeUp) → F19 | VolumeUp | **keyDown 80 (F19)**, no system-defined event | unchanged |
| none on 0x81 | VolumeDown | sysdef `SOUND_DOWN` | −1 step |

**Yes:** a mapping is applied before the NX conversion, so a remapped media key
reaches the tap as an ordinary F-key keyDown.

Consumer-page sources (`0xC000000E9`, `0xC000000CD`, …) and an Apple
vendor-page source (`0xFF00000003`) were **accepted and read back**. On the Air's
built-in keyboard, consumer volume-up → F17 **took effect** (3b). No external board
with consumer-page media keys was available: the cl80 has no media keys (1c).

### 3b. `fnState` and mapping order on the built-in keyboard

Measured on the Air with KeyPath remapping **off** (an empty mapping is required;
see the lease note under Recommendation). Mappings applied to the built-in keyboard
service: keyboard F1 `0x70000003A`→F15, keyboard F11 `0x700000044`→F19, consumer
brightness-down `0xC00000070`→F16, consumer volume-up `0xC000000E9`→F17. Micah
pressed F1–F12 in each state.

| State | F1 | F11 | F12 | Which mapping fired |
|---|---|---|---|---|
| `fnState=0` (media) | sysdef brightness-down | sysdef volume-down | **keyDown 64 (F17)** | consumer volume-up |
| `fnState=0` + fn | **keyDown 113 (F15)** | **keyDown 80 (F19)** | keyDown 111 (F12) | keyboard F1 and F11 |
| `fnState=1` | **F15** | **F19** | F12 | keyboard F1 and F11 |
| `fnState=1` + fn | sysdef brightness-down | sysdef volume-down | **F17** | consumer volume-up |

**`fnState` and fn are applied *before* `UserKeyMapping`.** The mapping sees the
usage that Apple's keyboard driver has already chosen. In F-key mode that is the
keyboard-page F-key; in media mode it is the consumer usage (`0x0C/0xE9` for
volume up). A mapping on the F-key usage does nothing in media mode, and a
mapping on the media usage does nothing in F-key mode. So a hidutil indirection
for the top row must map *both* usages to cover both settings.

**The built-in brightness keys are not consumer `0x6F/0x70`.** The consumer
brightness-down mapping never fired, and F1 stayed a system brightness event.
Apple's driver reports brightness under another usage (most likely its vendor
top-case page), and it was not identified here. Volume is the standard consumer
usage. The other keys (mute, play, F3–F6) were not mapped in this test.

### 3c. How many spare intermediates exist

Sent from the fixture as real keyboard-page usages, with no mapping, and recorded
at the tap:

| Usage | Key | macOS key code | Usable as intermediate? |
|---|---|---|---|
| 0x68–0x6F | F13–F20 | 105, 107, 113, 106, 64, 79, 80, 90 | ✅ 8 keys (F13–F19 carry the fn flag; F20 does not) |
| 0x70–0x73 | F21–F24 | **nothing reaches the tap** | ❌ |
| 0x74, 0x76, 0x77 | Execute, Menu, Select | nothing | ❌ |
| 0x75 | Help | 114 (= Insert key code) | ❌ collides with Insert |
| 0x87 | International1 (JIS ろ) | 94 | ⚠️ a real key on JIS keyboards |
| 0x89 | International3 (JIS ¥) | 93 | ⚠️ a real key on JIS keyboards |
| 0x88, 0x8A, 0x8B | International2/4/5 | nothing | ❌ |
| 0x90, 0x91 | LANG1 かな, LANG2 英数 | 104, 102 | ⚠️ real keys on JIS keyboards, and they switch input source |
| 0x92–0x94 | LANG3–5 | nothing | ❌ |
| 0x32 | Non-US # | 42 | ❌ same key code as `\` |
| 0x64 | Non-US `\` (ISO §) | 10 | ❌ a real ISO key |
| 0x65 | Application | 110 | ⚠️ PC Menu key, rare on Mac boards |
| 0x7F–0x81 | keyboard Mute/VolUp/VolDn | system-defined 7/0/1 | ❌ they *are* media keys |

So there are **8 clean intermediates (F13–F20), shared with managed Caps.**
Caps takes one, leaving seven for twelve-odd media keys plus whatever the user
has bound F13–F20 to. The JIS/LANG codes are usable only on ANSI/ISO keyboards
that will never send them, and that is not knowable per keyboard. The budget
does not fit "one intermediate per media key".

---

## Recommendation

**Status 2026-10-20:** the output half shipped (rules-admission-review.md §4.5); the
input half (tap path) is next.

### Output: post from the worker, not the app

Allow consumer-page output in admission, and have the worker post
system-defined events for it. Concretely, in a later change:

1. The bridge's output map gains `(0x0C, 0xE2/0xE9/0xEA/0xCD/0xB5/0xB6/0xB3/0xB4/0x6F/0x70)`.
   Admission stops rejecting `mute`/`volu`/`vold`/`pp`/`next`/`prev`/`brup`/`brdn`.
2. In the worker's output drain, a page-0x0C triple becomes
   `NSEvent.otherEvent(.systemDefined, subtype 8)` with `NX_KEYTYPE_*`:

   | Kanata | NX code |
   |---|---|
   | `volu` | 0 |
   | `vold` | 1 |
   | `brup` | 2 |
   | `brdn` | 3 |
   | `mute` | 7 |
   | `pp` | 16 |
   | `next` | 17 |
   | `prev` | 18 |
   | fast-forward | 19 |
   | rewind | 20 |

   Value 1 posts down (`0xA`), value 0 posts up (`0xB`), and value 2 is dropped
   because the system repeats on its own (2c). The event is tagged with the
   worker's output tag so its own tap ignores it. Track held media outputs with
   the same all-up bookkeeping as held keys, so a stop releases them.
3. Keyboard backlight (`0xFF/0x07–0x09`) can map to `NX_KEYTYPE_ILLUMINATION_*`
   (21/22/23). It was not measured, because neither test Mac has a backlit
   keyboard.

Why the worker and not an app-side `push-msg "system:…"` action:

| | Worker poster | `push-msg` → app → poster |
|---|---|---|
| Hold / repeat | Press and release mirror Kanata exactly, and the system repeats while held | `push-msg` fires once on press with no release. Holding volume gives one step unless the rule grows paired on-press/on-release messages. |
| Latency | ~3 ms median (measured) | Adds a TCP hop and an actor hop on top |
| Works in layers, tap-hold, macros, chords | Yes: Kanata's normal output | Only where the generator writes `push-msg` |
| Works when the app UI is wedged | Yes | No |

`push-msg "system:…"` remains right for things that are not keys
(Mission Control, Spotlight, DND). Note that the Apple top row sends those as
keyDowns 160/177/178 (1a). Learning those key codes would be a separate,
cheaper improvement.

### Brightness on external displays: not through events

A posted `BRIGHTNESS_*` event drives the built-in panel only (2a). For the
Studio Display it does nothing, and the physical keys of an external Apple
keyboard were not tested against it. The options are the private
`DisplayServicesSetBrightness`, which worked from a background process here,
or DDC for third-party monitors. Both are a product decision beyond key
remapping. Recommendation: post the event, and document that `brup`/`brdn`
follow macOS's own brightness keys, which control the built-in or Apple
display macOS chooses, not every monitor.

### Input: read system-defined events in the tap; hidutil only for ambiguity

Two candidate input paths, measured:

- **Tap path (recommended).** Add `1 << 14` to the worker's mask. A subtype-8
  event's `data1` gives the `NX_KEYTYPE`, down/up and repeat. Feed it to Kanata
  as the matching consumer `OsCode` (page 0x0C usage) through `sendInput`, and
  consume it only when the profile maps that input. Swallow the hardware
  `repeat=1` copies, because Kanata does its own repeat. This works for any
  keyboard on any keymap, needs no hidutil lease, uses no intermediate, and was
  shown to suppress built-in brightness and volume (1b).
  The cost is attribution: system-defined events carry no device identity, so
  per-device media rules are impossible. That is already true for every session
  input.
- **hidutil path (fallback).** It works: a mapping is applied before NX
  conversion (3a). But it needs one intermediate per key from a pool of eight
  shared with Caps, and a mapping on whichever service carries page 12. It also
  shares the per-service `UserKeyMapping` array with the Caps lease.
  `SessionCapsRuntimeSupport.verifyActive` restores the whole recorded array,
  so a second writer looks like "ownership lost" and stops the runtime. The
  order test in 3b had to ask for remapping to be switched off first for exactly
  that reason. Use hidutil only where the tap path cannot tell keys apart.

### What stays impossible in the driverless runtime

- **Per-device media rules.** System-defined events carry no source device.
- **Telling F7/F9 apart from previous/next at the event level** on Apple
  keyboards: they are rewind/fast-forward codes that the media router treats
  as skip on a tap.
- **External-monitor brightness through events** (Studio Display measured).
- **F21–F24 and most International/LANG usages as intermediates:** they never
  reach a tap.
- **Fn itself as a media modifier for non-Apple boards:** the fn layer is
  resolved in keyboard firmware or in Apple's driver before any of this.
- **Creating a virtual consumer-control device** to send real HID media usages.
  `IOHIDUserDeviceCreateWithProperties` returns NULL without
  `com.apple.developer.hid.virtual.device`, and ad-hoc signing with that
  entitlement is killed at launch (exit 137). That is the driver backend's job.

## Follow-ups found during the spike

- `QMKKeycodeMapping.swift` comments list `NX_KEYTYPE_BRIGHTNESS_UP/DOWN = 21/22`.
  Those are `ILLUMINATION_UP/DOWN` (keyboard backlight). Brightness is **2/3**,
  measured in 1a and 2a.
- The mini's cl80 has `Caps→F18` on service 0x1005bb72b with no running worker
  and no lease owner. It looks stranded from an earlier session.

## Appendix: probes

All are standalone Swift or C, built with `swiftc -O` / `clang`. None ship.

- `mkprobe tap <s> [suppress]`: session tap for types 10/11/12/14. It prints the
  key code and flags, or subtype/`data1`/source pid/user data, with
  `CLOCK_UPTIME_RAW` ms timestamps. `suppress` returns nil for subtype 8.
- `mkprobe post|bench <key> …`: builds and posts subtype-8 events (tagged
  `0x4B504D4B`); `bench` is long-lived and timestamps every post.
- `mkprobe bright` / `bset`: `DisplayServicesGetBrightness` / `SetBrightness`.
- `np`: silent `AVAudioPlayer` plus `MPRemoteCommandCenter` handlers to observe
  delivery of play/next/previous.
- The fixture scripts were raw `KPHID1` reports with a right-Shift delimiter
  before each usage, so segments could be attributed. The fixture's own timing
  is local and unaffected by its ~5 s Wi-Fi start latency.
- Guided runs used `osascript display dialog` prompts over ssh. A mark was taken
  before and after each prompt, and all settings were restored at the end.
