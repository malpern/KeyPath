# KeyPath physical HID fixture

This lab-only firmware turns a Wi-Fi microcontroller into a deterministic USB keyboard. The VM
owns the fixture's USB device; the Mac mini uses the independent Wi-Fi control plane to load, arm,
start, abort, and inspect locally timed HID scripts.

The fixture is deliberately not part of any KeyPath product target.

## First board: one-command install from a Mac

The checked-in `pico-hid-fixture-tool` owns setup, tests, builds, flashing, and the first Wi-Fi
health check. Before the board arrives, configure the four Wi-Fi profiles and control
token without putting their values in a shell history or chat:

```bash
Scripts/lab/pico-hid-fixture-tool configure
Scripts/lab/pico-hid-fixture-tool doctor
```

`configure` opens Add Secret.app once for each missing value and stores it through sops. A doctor
result of `wait  board not connected` is healthy before the hardware arrives. When the board is
connected tomorrow, the complete path is:

```bash
Scripts/lab/pico-hid-fixture-tool install
```

That command validates the Mac and credentials, runs the host and QEMU suites, builds production
firmware, detects an unambiguous serial port, flashes it, and waits for the authenticated Wi-Fi
status endpoint. If no port appears, hold **BOOT**, tap **RESET**, then release **BOOT** and rerun;
use `install --port /dev/cu...` only when more than one serial device is connected. The exact
hands-on checklist and failure routing are in
[`docs/testing/keypath-hid-fixture-first-board.md`](../../../docs/testing/keypath-hid-fixture-first-board.md).
The operator-facing states, dual-core allocation, UX acceptance criteria, and deferred refinements
are in
[`docs/testing/keypath-hid-fixture-readiness.md`](../../../docs/testing/keypath-hid-fixture-readiness.md).

## Hardware targets

- **Primary:** Waveshare ESP32-S3-Touch-LCD-1.69 (240×280 display, capacitive touch, buzzer,
  function button, 8 MB PSRAM, and 16 MB flash)
- **Legacy:** Raspberry Pi Pico 2 W
- One data-capable USB cable to the Mac mini
- Lab Wi-Fi access

The Waveshare board needs no shield, speaker, external debugger, power supply, or second
microcontroller. Its display presents the run state and timing pressure; touch or the physical
button aborts an ordinary armed/running script, and its buzzer provides sparse transition cues.
The top power button also arms a bounded offline demo while the fixture is terminal; tapping the
screen is the separate confirmation that starts it. Pico 2 W uses its onboard green LED instead.

On a cold boot, the display briefly presents the official Hacker Dojo torii mark before dissolving
into the live KeyPath startup scene. The mark is rendered from lightweight LVGL vector primitives,
so the splash needs no image decoder and does not delay USB, Wi-Fi, or the HID executor.

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
- Firmware updates are accepted only while the fixture is safely idle, are authenticated with a
  token-bound HMAC-SHA256, and are SHA-256 checked before ESP-IDF validates the application image.
- Two application slots preserve the currently working image. A newly installed image must bring
  its Wi-Fi control plane up within 60 seconds or the bootloader rolls back automatically.
- Control traffic is HTTP rather than TLS, so operate it only on the isolated, WPA2-protected lab
  Wi-Fi; the bearer token is defense in depth, not a substitute for network isolation.
- The fixture schedules every report locally. Wi-Fi jitter can shift the start acknowledgement but
  cannot alter inter-key timing after the script starts.
- The built-in demo requires two deliberate actions—top power, then touch—and uses a fixed,
  compiled-in `KeyPath demo OK` sequence. Once armed, it does not abort if Wi-Fi disconnects. It
  reports `HID SENT / CHECK JIG`, never an invented pass; only the independent Jig can classify it.
- The deterministic physical timing contract starts at a 4 ms character interval with a 2 ms key
  hold. That is already a 250 Hz key cadence. A physical 3 ms diagnostic preserved output but
  missed USB deadlines because its alternating 2 ms/1 ms press-release gaps leave no scheduling
  margin on the full-speed interrupt endpoint, so the compiler rejects intervals below 4 ms.
- Combined physical runs are strict by default: any report more than 1 ms late fails the run. A
  load case may opt into both `--max-late-reports` and `--max-lateness-us` to classify bounded
  timing pressure separately from correctness. Exact output, report count, ordering, and
  all-keys-released remain mandatory regardless of that budget.
- On ESP32-S3, the HID scheduler owns core 1 at high priority. USB service, network control, sound,
  and display work remain on core 0. The motion governor drops the display from 30 to 20 to 8 FPS
  and removes expensive particle layers before animation can compete with HID timing.
- Production exposes HID only—no USB serial console—so the VM observes the same device shape used
  by the test. The screen reports Wi-Fi/IP/USB state, while authenticated `/v1/status` and
  `/v1/trace` provide the deeper diagnostics and exact firmware build identifier. Status also
  reports uptime/reset, heap, Wi-Fi reconnect, HTTP restart/request, and handler-latency counters.

## 30-second offline demo

The showroom path does not compile the Jig or depend on Wi-Fi after arming. From the KeyPath
worktree, run:

```bash
Scripts/lab/hid-capture-jig-tool demo
```

The command reuses the signed app when its source hash is unchanged, brings the Jig forward, arms
the exact expected text, and puts `PRESS TOP POWER, THEN TAP DEVICE` in the Jig itself. Press the
board's top power button once, then tap the display. The command returns the Jig's exact pass/fail
within 30 seconds and the Jig writes its normal evidence artifact. BOOT or another screen tap while
the demo is running remains a fail-closed abort.

This is the presentation path, not a replacement for the strict matrix runner. It demonstrates a
known physical HID sequence quickly; product conclusions still require correlated fixture trace,
Jig, resource, Kanata, and VirtualHID evidence.

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

## Waveshare ESP32-S3 manual build

ESP-IDF 5.5.5 and its Python tools are installed locally under
`~/.cache/keypath-esp32/esp-idf`. The target uses Waveshare's official board component and LVGL.
Build credentials are supplied only through the environment:

```bash
source ~/.cache/keypath-esp32/esp-idf/export.sh
export KEYPATH_WIFI_SSID_1='primary-network'
export KEYPATH_WIFI_PASSWORD_1='...'
export KEYPATH_WIFI_SSID_2='fallback-network-one'
export KEYPATH_WIFI_PASSWORD_2='...'
export KEYPATH_WIFI_SSID_3='fallback-network-two'
export KEYPATH_WIFI_PASSWORD_3='...'
export KEYPATH_WIFI_SSID_4='current-location-network'
export KEYPATH_WIFI_PASSWORD_4='...'
export KEYPATH_FIXTURE_TOKEN='at-least-16-random-characters'
idf.py -C Scripts/lab/pico-hid-fixture/targets/waveshare-esp32-s3-touch-lcd-1.69 build
```

The board revision defaults to 2, whose buzzer is on GPIO42. Revision 1 used GPIO33; change
`KeyPath fixture → Waveshare board revision` with `idf.py menuconfig` if the delivered board is an
older revision. Flashing waits for the physical board:

```bash
idf.py -C Scripts/lab/pico-hid-fixture/targets/waveshare-esp32-s3-touch-lcd-1.69 -p PORT flash
```

Prefer `pico-hid-fixture-tool install` for normal use. The manual commands remain documented for
toolchain debugging and CI reproduction.

The on-device scene is continuously alive: a breathing reactor, orbiting HID packets, a live
progress arc, and time-based motion remain smooth even when the frame rate changes. Preparing,
countdown, typing, observation, resolution, pass, fail, and inconclusive phases morph through
colored icons instead of hard cuts. A visible `HID PRIORITY` mode keeps a restrained orbit at 8 FPS
while shedding most particles, so the display still communicates life without competing with
keyboard delivery.

Secure OTA uses the same KeyPath visual language as the host capture Jig: the opened amber keycap,
illuminated center, and four-point glint. The key light fills from the authenticated image's real
receive/validation progress; the orbiting glint communicates liveness without implying extra
progress.

The device UI uses LVGL's native Montserrat bitmaps at 12, 14, 16, 20, and 24 px rather than scaling
a single size. Small telemetry stays crisp, the 24 px state and splash wordmark carry the hierarchy,
and icons retain the symbol-complete 20 px cut. These fonts are compiled into flash and require no
runtime rasterization, allocation, or work on the HID core.

The host Jig keeps product and tool identity separate. Its in-window header bundles and renders the
real KeyPath application artwork, while its Dock/Finder icon depicts a physical test fixture—base
plate, opposing clamps, test key, and measurement probe—and does not reuse the KeyPath app icon.

## Host capture Jig resource preflight

### Foreground ownership requirement

A physical completion run needs exclusive keyboard focus on the macOS desktop under test. USB HID
reports are delivered to the foreground application; they cannot be addressed to a background Jig.
The runner therefore leaves the Jig unfocused during resource checks, script compilation, and fixture
setup, then focuses it immediately before the atomic arm step. Losing focus after arming invalidates
the run. Do not type or switch applications until the runner returns.

This does not require an otherwise empty Mac. Normal background services are allowed when the
resource gate accepts them, and deliberate load cases add their own bounded workers after arming.
It does require reserving the active desktop for the test. For unattended runs while the host remains
usable, pass the fixture USB device through to a dedicated macOS VM and keep the Jig focused inside
that guest; retain a smaller bare-metal acceptance set because VM USB scheduling is not identical to
physical macOS.

The focused Shift diagnostic is split into a short admission run and a full matrix:

```bash
# About 10 minutes including admission, evidence inspection, and one retry allowance.
Scripts/lab/physical-hid-shift-matrix \
  --lead-values 0,4,8 --release-values 0 --repeat 2

# Reserve 20-30 minutes. Runs the complete 5x5 lead/release grid.
Scripts/lab/physical-hid-shift-matrix
```

The matrix waits up to 60 seconds for a stable Jig resource window before each cell. It does not
focus the Jig while waiting. Each artifact combines exact expected/received text, focus and release
state, macOS event history, fixture timing totals, and the bounded ESP32 report trace.

The native AppKit HID Capture Jig samples the Mac once per second and will not arm until three
consecutive checks are inside the baseline capture envelope. It evaluates instantaneous CPU use,
one-minute runnable load normalized per logical core, reclaimable memory, macOS memory pressure,
thermal state, and an extreme system-thread ceiling. Current thresholds are centralized and tested
in `hid-capture-jig/Sources/HIDCaptureCore/SystemReadiness.swift`:

- CPU below 80%
- normalized load below 0.9× per logical core
- at least 2 GB or 8% of physical memory reclaimable, whichever is larger
- normal macOS memory pressure
- no serious/critical thermal state
- fewer than 900 system threads per logical core

While blocked, the Jig remains idle and shows `PAUSED · MAC BUSY`, live measurements, the specific
reason, and the best first operator action. The file-RPC response contains the same structured
`systemReadiness` assessment. `physical-hid-capture-run` checks it before loading or arming the
fixture, so a busy host cannot mutate the USB test state and then fail late. The Jig rechecks
automatically; no app or machine restart is required.

During capture, every real key-down is also rendered as a labeled KeyPath keycap at a shared focal
point. The face compresses immediately, then joins a short, fanned stack of the most recent presses;
dense input widens the fan and raises the live burst count without drawing a full keyboard. The model
uses capture timestamps, caps the visible stack at ten keycaps, and gives faster-than-display bursts a
36 ms minimum presentation cadence so each genuine key-down remains perceptible and in order. Each cap
ages out in 900 ms, while the complete, unmodified event ledger remains in the JSON artifact. Reduce
Motion removes travel, compression, and paced playback while preserving live labels and evidence.

This is the baseline reliability policy. Deliberate load-matrix cases use the runner's bounded CPU
envelope rather than bypassing the gate with an unstructured "ignore busy" switch. The runner
performs the normal calm preflight first, then starts the requested number of tracked CPU workers
only after the Jig and fixture are armed:

```bash
Scripts/lab/physical-hid-capture-run \
  --run-id shifted-high-load \
  --text Scripts/lab/pico-hid-fixture/tests/fixtures/burst.txt \
  --interval-ms 50 --hold-ms 12 --repeat 20 --cycle-gap-ms 50 \
  --cpu-load-workers 6 --cpu-sample-ms 250
```

`--cpu-load-workers` accepts zero through the host's logical CPU count. Every worker is owned and
terminated by the runner, including error paths. The combined artifact records worker count,
logical CPUs, average/maximum CPU, and timestamped CPU/load samples. If capture fails early, the
runner still waits for the fixture to finish and for the macOS event queue to settle, preserving the
complete event ledger instead of a first-mismatch prefix.

For the repeated-key regression, use the strict resumable campaign rather than an ad hoc typing
script:

```bash
Scripts/lab/physical-hid-repeat-matrix --exclusive-desktop-confirmed
```

The default 60-case plan crosses four input shapes (one repeated key, alternating keys, a rolling
home-row sequence, and shifted symbols), 50/10/5 ms pacing, and five load profiles: calm, two and
six bounded CPU workers, generated Swift compilation, and generated Swift compilation plus two CPU
workers. Every case still passes the normal calm admission gate before its bounded load begins; the
campaign never uses demo mode. The generated compiler workload lives in a temporary directory and
does not clean, touch, or build the KeyPath worktree.

Each combined artifact distinguishes additions from deletions and substitutions and retains the
Jig's duplicate-down, host-repeat, unmatched-up, focus, release, and event evidence alongside the
ESP32 trace and timing. The summary classifies any inserted character or unexpected repeat event as
`repeated-input-observed`, while focus loss or incomplete release fails closed as `harness-invalid`.
Use the same `--run-id-prefix` and `--resume` after an infrastructure interruption to reuse completed
case artifacts without repeating valid HID runs. The explicit desktop confirmation is mandatory
because a real USB keyboard cannot safely target a background window while the operator is typing.

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
| POST | `/v1/presentation` | Bounded JSON phase, result, progress, labels, and metrics |
| POST | `/v1/firmware` | Binary ESP32 application image plus SHA-256 and HMAC headers |

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
Scripts/lab/pico-hid-fixture-client present --phase observing --progress 850 \
  --title 'Swift stress' --detail 'Comparing received text'
Scripts/lab/pico-hid-fixture-client present --phase result --result pass --progress 1000 \
  --title 'Swift stress' --detail 'No repeated keys' \
  --reports-expected 400 --reports-observed 400 --latency-p95-us 620 --safe-release
```

Measure the control plane without emitting HID reports:

```bash
Scripts/lab/pico-hid-fixture-tool soak --requests 120
```

The soak resolves mDNS once, then measures the ESP endpoint by IP, stops after three consecutive
failures, enforces a 750 ms p95 budget, and atomically writes an artifact under
`~/.local/state/keypath-hid-fixture/control/`. Discovery time is recorded separately so slow mDNS
cannot be mistaken for a slow firmware handler.

`run-text` combines compile, load, arm, and start. Production scenarios should still perform each
stage explicitly so the VM can prove USB admission, arm its independent observers, and verify the
requested load threshold before `start`.

## Safe Wi-Fi firmware updates

The initial dual-slot partition layout must be installed once over USB with the normal BOOT/RESET
flash path. After that migration, routine application updates are one command and do not change
the HID-only USB interface:

```bash
Scripts/lab/pico-hid-fixture-tool update
```

The tool builds an exact source-identified image, confirms the fixture is reachable and update-safe,
authenticates the image with the fixture token, streams it into the inactive slot, and waits through
the reboot. Success requires the board to reconnect over Wi-Fi on the exact expected build. The
device shows receive/validation progress while keeping HID execution disabled. Never remove power
during the update. If the new image cannot restore its Wi-Fi control plane within 60 seconds, the
bootloader returns to the previous slot. USB BOOT/RESET remains the recovery path if both application
slots or the network configuration are unusable.

The matrix campaign executor mirrors live phases and its final classified result to the display
when invoked with `--hid-presentation`. This path is intentionally presentation-only: display
delivery failures are logged to `hid-fixture-presentation.log` and never change test evidence or
campaign classification. The fixture token remains environment-only.

## Verification without hardware

```bash
Scripts/lab/pico-hid-fixture/tests/run-tests.sh
python3 Scripts/lab/tests/pico-hid-fixture-client-tests.py
python3 Scripts/lab/tests/pico-hid-fixture-control-soak-tests.py
Scripts/lab/pico-hid-fixture/tests/run-esp32-qemu-smoke.sh
```

These tests cover CRC and script admission, timing/repeat execution, trace ordering, lateness
metrics, boot/abort/unmount releases, US-keyboard compilation, bearer authentication, endpoint
selection, authenticated OTA image construction and build verification, secure installer behavior,
presentation/result resolution, NDJSON trace decoding, and
the adaptive UI model. The QEMU test boots an ESP32-S3 image
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
