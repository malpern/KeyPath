# KeyPath physical HID fixture

This lab-only firmware turns a Wi-Fi microcontroller into a deterministic USB keyboard. The VM
owns the fixture's USB device; the Mac mini uses the independent Wi-Fi control plane to load, arm,
start, abort, and inspect locally timed HID scripts.

The fixture is deliberately not part of any KeyPath product target.

## Hardware targets

- **Primary:** Waveshare ESP32-S3-Touch-LCD-1.69 (240×280 display, capacitive touch, buzzer,
  function button, 8 MB PSRAM, and 16 MB flash)
- **Legacy:** Raspberry Pi Pico 2 W
- One data-capable USB cable to the Mac mini
- Lab Wi-Fi access

The Waveshare board needs no shield, speaker, external debugger, power supply, or second
microcontroller. Its display presents the run state and timing pressure; touch or the physical
button aborts an armed/running script, and its buzzer provides sparse transition cues. Pico 2 W
uses its onboard green LED instead.

## Safety model

- USB exposes only a standard boot-keyboard HID interface. There is no USB serial control path for
  the VM to confuse with the input oracle.
- Every cycle must end with a full all-keys-released report.
- Boot, arm, remote abort, watchdog recovery, and USB reconnect all queue an all-keys-released
  report before further input.
- A running script fails closed if USB is removed.
- Scripts are bounded by event, repeat, duration, request-size, and trace limits.
- Uploaded event bytes are CRC32-verified before the fixture can arm.
- HTTP endpoints require a bearer token. Credentials are build inputs and are never committed.
- Control traffic is HTTP rather than TLS, so operate it only on the isolated, WPA2-protected lab
  Wi-Fi; the bearer token is defense in depth, not a substitute for network isolation.
- The fixture schedules every report locally. Wi-Fi jitter can shift the start acknowledgement but
  cannot alter inter-key timing after the script starts.
- On ESP32-S3, the HID scheduler owns core 1 at high priority. USB service, network control, sound,
  and display work remain on core 0. The motion governor drops the display from 30 to 20 to 4 FPS
  before animation can compete with HID timing.

## Pico LED states

| State | Onboard LED |
|---|---|
| Wi-Fi disconnected | repeating double blink |
| Wi-Fi connected / idle | brief heartbeat |
| Script loaded | double blink |
| Armed | solid |
| Running | fast blink |
| Complete | repeating triple blink |
| Error | rapid blink |

## Waveshare ESP32-S3 build

ESP-IDF 5.5.5 and its Python tools are installed locally under
`~/.cache/keypath-esp32/esp-idf`. The target uses Waveshare's official board component and LVGL.
Build credentials are supplied only through the environment:

```bash
source ~/.cache/keypath-esp32/esp-idf/export.sh
export KEYPATH_WIFI_SSID='lab-network'
export KEYPATH_WIFI_PASSWORD='...'
export KEYPATH_FIXTURE_TOKEN='at-least-16-random-characters'
idf.py -C Scripts/lab/pico-hid-fixture/targets/waveshare-esp32-s3-touch-lcd-1.69 build
```

The board revision defaults to 2, whose buzzer is on GPIO42. Revision 1 used GPIO33; change
`KeyPath fixture → Waveshare board revision` with `idf.py menuconfig` if the delivered board is an
older revision. Flashing waits for the physical board:

```bash
idf.py -C Scripts/lab/pico-hid-fixture/targets/waveshare-esp32-s3-touch-lcd-1.69 -p PORT flash
```

The on-device scene is intentionally calm while idle and more expressive during state changes and
runs: orbital particles, a live report-progress arc, animated key cells, color-coded state changes,
and a completion flourish. A visible `HID PRIORITY` mode means detected timing pressure has reduced
the animation rate to protect keyboard delivery.

## Pico 2 W build

Install CMake, an Arm embedded compiler, and the Raspberry Pi Pico SDK. Keep Wi-Fi credentials and
the fixture token out of the repository:

```bash
export PICO_SDK_PATH=/absolute/path/to/pico-sdk
export KEYPATH_WIFI_SSID='lab-network'
export KEYPATH_WIFI_PASSWORD='...'
export KEYPATH_FIXTURE_TOKEN='at-least-16-random-characters'
cmake -S Scripts/lab/pico-hid-fixture -B Scripts/lab/pico-hid-fixture/build -G Ninja
cmake --build Scripts/lab/pico-hid-fixture/build
```

The resulting `keypath_pico_hid_fixture.uf2` can be installed by holding BOOTSEL while connecting
the Pico and copying the UF2 to the mounted `RPI-RP2` volume. Build-time secrets remain in the
local build directory and embedded firmware; delete that directory before sharing artifacts.

When real lab credentials are provisioned, store them through the existing sops-backed secret
workflow and have the build wrapper export them without printing their values.

## Script protocol

The first line is:

```text
KPHID1 RUN_ID EVENT_COUNT REPEAT_COUNT CYCLE_US CRC32
```

Each remaining line is one complete boot-keyboard report:

```text
AT_US MODIFIERS KEY1 KEY2 KEY3 KEY4 KEY5 KEY6
```

Times are absolute within one cycle and must increase. The last report must contain seven zeros.
The event payload, including final newlines, is protected by the header CRC32. A short cycle can be
repeated many times without storing tens of thousands of reports in Pico RAM.

## HTTP API

The fixture advertises `keypath-hid-fixture.local` over mDNS on port 8080. Every request requires
`Authorization: Bearer TOKEN`.

| Method | Path | Body |
|---|---|---|
| GET | `/v1/status` | — |
| POST | `/v1/script` | Complete `KPHID1` script |
| POST | `/v1/arm` | Run ID |
| POST | `/v1/start` | `RUN_ID DELAY_MS` |
| POST | `/v1/abort` | Empty |
| GET | `/v1/trace?from=N&limit=8` | — |

Commands are state-checked. A script cannot start unless the same run ID was loaded and armed.
The start delay must be 100–60000 ms, giving the guest observer time to become ready.

## Mac mini client

`Scripts/lab/pico-hid-fixture-client` uses only Python's standard library. It compiles US-keyboard
text into full HID reports and calls the fixture API:

```bash
export KEYPATH_FIXTURE_HOST=keypath-hid-fixture.local
export KEYPATH_FIXTURE_TOKEN='...'

Scripts/lab/pico-hid-fixture-client status
Scripts/lab/pico-hid-fixture-client compile-text \
  --run-id swift-load-001 --text reference.txt --repeat 20 --output /tmp/swift-load.kphid
Scripts/lab/pico-hid-fixture-client load-script /tmp/swift-load.kphid
Scripts/lab/pico-hid-fixture-client arm swift-load-001
Scripts/lab/pico-hid-fixture-client start swift-load-001 --delay-ms 2000
Scripts/lab/pico-hid-fixture-client trace
```

`run-text` combines compile, load, arm, and start. Production scenarios should still perform each
stage explicitly so the VM can prove USB admission, arm its independent observers, and verify the
requested load threshold before `start`.

## Verification without hardware

```bash
Scripts/lab/pico-hid-fixture/tests/run-tests.sh
python3 Scripts/lab/tests/pico-hid-fixture-client-tests.py
Scripts/lab/pico-hid-fixture/tests/run-esp32-qemu-smoke.sh
```

These tests cover CRC and script admission, timing/repeat execution, trace ordering, lateness
metrics, boot/abort/unmount releases, US-keyboard compilation, bearer authentication, endpoint
selection, NDJSON trace decoding, and the adaptive UI model. The QEMU test boots an ESP32-S3 image
and executes the real parser, scheduler, trace logic, and UI state model on the emulated Xtensa
cores. QEMU does not emulate the Waveshare LCD/touch/buzzer or the ESP32-S3 native USB device
controller, so the physical USB/VM, display, touch, sound, and timing acceptance checks still wait
for the board.

## First-board acceptance

1. Flash revision 2, confirm the display, touch coordinates, function button, and transition tones;
   retry revision 1 only if the buzzer is silent.
2. Confirm macOS reports exactly one boot-keyboard HID interface and no serial or storage interface.
3. Attach USB directly to a disposable VM and verify a baseline script's received text, report
   count, submitted CRC32, transfer completions, and lateness trace.
4. Repeat under sustained CPU, memory, disk, and UI load; `HID PRIORITY` should reduce animation
   while the trace remains complete and correctly ordered.
5. During an active run, test touch abort, button abort, Wi-Fi abort, and USB removal. Every path
   must end with an all-keys-released report before the fixture can be called hardware-proven.
