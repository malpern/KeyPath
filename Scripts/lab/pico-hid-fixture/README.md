# KeyPath Pico 2 W physical HID fixture

This lab-only firmware turns an otherwise unmodified Raspberry Pi Pico 2 W into a deterministic
USB keyboard controlled over Wi-Fi. The VM owns the Pico's USB device; the Mac mini uses the
independent Wi-Fi control plane to load, arm, start, abort, and inspect locally timed HID scripts.

The fixture is deliberately not part of any KeyPath product target.

## Hardware

- Raspberry Pi Pico 2 W
- One data-capable micro-USB cable to the Mac mini
- Lab Wi-Fi access

No serial adapter, debugger, shield, speaker, external power supply, or second microcontroller is
required. The onboard green LED reports fixture state.

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
- The Pico schedules every report locally. Wi-Fi jitter can shift the start acknowledgement but
  cannot alter inter-key timing after the script starts.

## LED states

| State | Onboard LED |
|---|---|
| Wi-Fi disconnected | repeating double blink |
| Wi-Fi connected / idle | brief heartbeat |
| Script loaded | double blink |
| Armed | solid |
| Running | fast blink |
| Complete | repeating triple blink |
| Error | rapid blink |

## Build

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
```

These tests cover CRC and script admission, timing/repeat execution, trace ordering, lateness
metrics, boot/abort/unmount releases, US-keyboard compilation, bearer authentication, endpoint
selection, and NDJSON trace decoding. The firmware has also been cross-compiled against Pico SDK
2.3.0 for `pico2_w`; a physical USB/VM run remains required before declaring it hardware-proven.
