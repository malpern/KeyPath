# KeyPath HID fixture readiness and on-device UX

## Current readiness

The firmware and Mac workflow are ready for the first physical board. Host tests, client tests,
installer tests, campaign-runner tests, the ESP32-S3 QEMU boot smoke test, and the credential-bearing
production build pass. This proves the software shape; it does not prove the delivered LCD, touch
controller, buzzer revision, native USB behavior, or report timing.

There are no additional software or visual changes required before the first flash. The remaining
release gate is the physical acceptance checklist in
[`keypath-hid-fixture-first-board.md`](keypath-hid-fixture-first-board.md).

## Operator journey

### Install or update

Connect the board to the Mac with a data-capable USB cable, then run:

```bash
cd /Users/malpern/local-code/keypath-pico-hid-fixture
Scripts/lab/pico-hid-fixture-tool install
```

The command checks the Mac and encrypted credentials, runs all software tests, builds production
firmware, finds an unambiguous serial device, flashes it, and verifies the authenticated status API.
It does not ask the operator to copy credentials into a terminal.

### Fast showroom proof

When the Mac is exclusively available for real keyboard input, run:

```bash
cd /Users/malpern/local-code/keypath-pico-hid-fixture
Scripts/lab/hid-capture-jig-tool showroom
```

This is the zero-touch path: it opens and focuses the source-hashed Jig, then immediately asks the
ESP32 to type `KeyPath demo OK` plus Return over real USB HID. Demo mode deliberately bypasses the
Mac CPU, load, memory-pressure, and thermal admission gate so an audience is never left waiting for
the machine to become idle. It still requires exclusive keyboard focus, bounded execution, exact
independent Jig capture of all 16 characters, and verified release of every key and modifier.

The bypass makes this demonstration evidence only: it must never be used to accept or reject a
KeyPath build. `physical-hid-capture-run` remains strict by default, and matrix/acceptance callers do
not pass `--demo-mode`; they still require three clean host-resource samples. A timestamped combined
artifact records `admissionMode: demo-bypass` or `strict`. Use `hid-capture-jig-tool demo` only for
the separate offline top-power-then-touch presentation; it uses the same demo-only bypass.

### Cold-boot screen sequence

| Approximate time | Display | Operator meaning |
|---|---|---|
| 0–0.26 s | Hacker Dojo mark reveals | Display task is alive. |
| 0.26–1.20 s | Mark, `HACKER DOJO`, and `MOUNTAIN VIEW / SINCE 2009` | Short identity splash; USB, Wi-Fi, and HID initialization continue concurrently. |
| 1.20–1.65 s | Splash expands and dissolves | Transition into live fixture state. |
| After 1.65 s | `WAKING UP` or `JOINING LAB` | Runtime is starting or trying the named Wi-Fi profile. |
| Connected | `READY`, IP address, and `USB READY` or `USB WAIT` | Control plane is reachable; USB state is explicit. |

The splash is intentionally brief and has no image-decoding work. It is built from LVGL vector
primitives and runs on the display task. It must never postpone HID, USB, or networking work.

### Test-state language

| Display state | Meaning | Operator action |
|---|---|---|
| `READY` | Wi-Fi is connected and no test is armed. | Safe to load a script. |
| `SCRIPT LOADED` | Script passed admission and CRC validation. | Arm only after observers are ready. |
| `ARMED` | Fixture is ready to emit reports. | Start the synchronized run or abort. |
| `DEMO ARMED` | The fixed offline demo is loaded; no key has been sent. | Tap the screen only after the Jig says it is armed. |
| `TYPING` or `SENDING KEYS` | Reports are being emitted from locally timed script data. | Avoid disconnecting USB unless testing removal. |
| `HID SENT / CHECK JIG` | The offline demo finished sending reports. | Read the independent Jig result; this is not itself a pass. |
| `HID PRIORITY` | Timing pressure was detected and display work was reduced to 8 FPS. | The test may continue; inspect trace timing afterward. |
| Pass, fail, or inconclusive result | Campaign supplied a classified outcome and metrics. | Preserve the campaign evidence. |
| `ATTENTION` | Safety or runtime error. | Record the detail, query `status` and `trace`, and do not blindly retry. |

## Work split across both ESP32-S3 cores

- **Core 1:** the priority-20 HID scheduler. It owns locally timed keyboard reports and uses a
  short polling loop only while a script is running.
- **Core 0:** priority-18 TinyUSB service, priority-8 HTTP control, priority-6 display, priority-5
  button and buzzer work, and the ESP-IDF Wi-Fi task.
- Animation quality automatically steps from showcase to active to `HID PRIORITY`; visual fidelity
  is expendable, report timing is not.

The ESP-IDF TCP/IP task currently has no hard affinity. That is acceptable for the first-board
baseline because the HID task has higher priority, but it is a deliberate measurement item during
load acceptance. Pin TCP/IP to Core 0 only if traces show Core 1 interference; do not make that
change without comparing before-and-after timing evidence.

## Physical UX sign-off

Record pass, fail, or notes for each item before calling the device finished:

- Splash is upright, centered, legible, and feels brief rather than like a boot delay.
- Splash dissolves cleanly into the live scene without a black flash or stale frame.
- `JOINING LAB` names the network currently being attempted.
- `READY` shows a readable IP address and unambiguous USB status.
- Color, icons, and motion distinguish loaded, armed, running, protected, complete, and error.
- `HID PRIORITY` visibly calms the display without making it appear frozen.
- Ordinary tests: touch and BOOT abort armed or running scripts. Offline demo: top power arms,
  touch starts, and BOOT/touch during execution aborts.
- Tones are audible but not distracting; current-board revision 2 uses GPIO42.
- Pass, fail, and inconclusive remain understandable without reading the HTTP response.
- At typical viewing distance, there is no clipping, tearing, unreadably small text, or excessive
  brightness.

## Configuration knobs

The target's `KeyPath HID fixture` menu exposes:

- Board revision: `2` by default; use `1` only if the delivered board has the older buzzer wiring.
- Brightness: `85%` by default.
- State-change tones: enabled by default.
- Reduced motion: available without removing state, color, or progress feedback.

Do not tune these before seeing the physical display. Capture the default result first so changes
address observed hardware behavior rather than simulator assumptions.

## Deferred improvements, not first-flash blockers

- Pin the TCP/IP task to Core 0 if physical traces demonstrate scheduler interference.
- Tune brightness, tone duration, touch coordinates, or splash timing from observed hardware.
- Capture a short reference video after visual acceptance so later firmware changes can be compared.
- Add factory-reset or over-the-air update UX only if repeated physical maintenance demonstrates a
  real need. USB flashing remains simpler and safer for this lab-only fixture.

Avoid adding USB serial, storage, or a composite debug interface. The device must continue to look
like one ordinary keyboard to the VM; status and trace diagnostics belong on the independent Wi-Fi
control plane.
