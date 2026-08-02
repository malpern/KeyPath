# KeyPath HID fixture physical acceptance results

## 2026-07-27 first-board session

Hardware: Waveshare ESP32-S3-Touch-LCD-1.69 revision 2. The fixture reported firmware
`0.3.0-esp32s3`, build `f24be33f2d7b`, a configured lab Wi-Fi network, and a mounted native USB
HID interface.
The host oracle was the isolated AppKit HID Capture Jig on macOS 27.0.

Combined artifacts are stored with mode `0600` under
`~/.local/state/keypath-hid-capture-jig/combined/`. An interrupted attempt named
`physical-jig-burst-10ms-1` is excluded; its fixture run was remotely aborted and it is not test
evidence.

## Automated physical results

| Case | Result | Characters | Reports | Timing evidence |
|---|---:|---:|---:|---|
| Cooperative baseline | Pass | 34 / 34 | 68 / 68 | 0 late; 32 us maximum lateness |
| Shift and symbols | Pass | 36 / 36 | 72 / 72 | 0 late; modifiers released |
| 10 ms burst | Pass | 240 / 240 | 480 / 480 | 0 late; 40 us maximum |
| 5 ms burst | Pass | 600 / 600 | 1,200 / 1,200 | 0 late; 48 us maximum |
| 4 ms boundary | Pass | 1,200 / 1,200 | 2,400 / 2,400 | 0 late; 44 us maximum |
| 4 ms with 8 saturated host cores | Pass | 1,200 / 1,200 | 2,400 / 2,400 | 0 late; 48 us maximum |
| 5 ms with CPU and storage contention | Pass | 1,200 / 1,200 | 2,400 / 2,400 | 0 late; 65 us maximum |
| Sustained 5 ms with 8 saturated host cores | Pass | 3,600 / 3,600 | 7,200 / 7,200 | 3 late within the explicit 5-report / 5,000 us stress budget; 2,165 us maximum |
| Remote abort during active typing | Pass | Correct 10-character prefix | Stopped at 20 / 6,800 | Final release transfer completed; no stuck key or modifier |
| Post-flash cooperative baseline | Pass | 34 / 34 | 68 / 68 | Safety/button-feedback build; exact output and final release |
| Physical BOOT abort | Pass | Correct 1,332-character prefix | Stopped at 2,663 / 6,800 | Final release completed; no repeat, duplicate-down, or unmatched-up events |
| Physical touchscreen abort | Pass | Correct 668-character prefix | Stopped at 1,335 / 6,800 | Final release completed; no repeat, duplicate-down, or unmatched-up events |

Every passing completion case had exact output, the full requested report count, no duplicate
downs, no AppKit repeat events, no unmatched ups, and an empty final key/modifier set.

## Boundaries and defects found

- A 3 ms diagnostic delivered all 1,200 characters and all 2,400 reports in order, but 1,601
  reports missed the 1 ms deadline and the worst miss was 6,727 us. The compiler now rejects
  intervals below 4 ms instead of promising a cadence the full-speed USB path cannot guarantee.
- A 4 ms CPU-plus-storage boundary run delivered exact output but recorded three deadline misses.
  The zero-lateness stress floor is therefore 5 ms; load runs can use explicit, recorded timing
  budgets without weakening output, ordering, count, or release checks.
- The first sustained load attempt exposed two HID Capture Jig crashes in text drawing. The jig
  was snapshotting and redrawing on every event and the launcher could leave multiple instances
  racing on one RPC directory. Drawing is now bounded to 20 FPS, fonts and paragraph styles are
  cached, terminal snapshots stop refreshing, and the launcher enforces one process. The sustained
  rerun passed and produced no new crash report; completed-jig CPU returned below 1%.
- Load-aware capture timeouts now include a 50% or 10-second drain margin so WindowServer can
  deliver queued events before the oracle freezes its fail-closed result.
- Wi-Fi loss previously rotated profiles without stopping an active script, contradicting the
  safety checklist. The new firmware aborts only armed/running scripts on a connected-to-disconnected
  transition and queues the same all-keys-released report as other abort paths.

## Remaining manual gate

The following checks require a person to manipulate or observe the board and are not yet physical
proof:

- During active typing, unplug and reconnect USB; verify the unmount error, remount, and final
  release report before another run arms.
- The held-BOOT overlay is proven: it remained visible and instructed `KEEP HOLDING + TAP BOTTOM
  RESET`. The POWER overlay and tone are proven, including restoration of the prior `TEST PASSED`
  state. The post-reset overlay is also visually confirmed, followed by a normal return to `READY`.
  Confirm the protected-motion state remains legible.
- Where the lab network can be intentionally interrupted, verify physical Wi-Fi loss aborts the
  active run and safely releases the keyboard.

Do not call the first-board gate complete until these manual rows are recorded.

The `physical-jig-button-abort-post-flash-1` attempt is excluded: its 30-second external-action
window expired without a physical button event, after which the fixture completed normally. It is
not evidence of either a passing or failing physical-button abort.

## Open repeated-key research campaign

The original report of repeated keypresses while compiling a large Swift program remains distinct
from the Shift-demotion defect below. `Scripts/lab/physical-hid-repeat-matrix` now defines the strict,
resumable campaign needed to investigate it. The plan covers repeated, alternating, rolling, and
shifted corpora at 50, 10, and 5 ms pacing under calm CPU, bounded CPU saturation, generated Swift
type-check pressure, and combined compiler/CPU pressure.

The campaign starts every load only after the ordinary three-sample host admission and capture arm.
It records exact output, inserted/deleted/substituted characters, AppKit duplicate-down/repeat/up
counters, focus and release state, firmware timing, and the full bounded report trace. It contains
no demo-mode bypass. This campaign is implemented and host-tested but has not yet emitted physical
HID; do not claim a KeyPath result until its strict case artifacts exist.

## 2026-07-27 shifted-key CPU matrix

Firmware build `ccd910cb18d9` ran the same 20-cycle shifted corpus
`aZ9!?-_=+[]\n` at a 50 ms character interval under four controlled host CPU levels. The Jig
performed its normal three-sample calm admission before each case; bounded CPU workers started only
after capture was armed. Artifacts are under
`~/.local/state/keypath-hid-capture-jig/load-matrix/20260727-1925/`.

| CPU workers | Measured CPU avg / max | Received | Wrong characters | Oracle state |
|---:|---:|---:|---:|---|
| 0 (calm control) | 29.8% / 67.1% | 240 / 240 | 12 | Focus retained; released |
| 2 (moderate) | 40.0% / 63.3% | 240 / 240 | 5 | Focus retained; released |
| 6 (high) | 70.6% / 81.1% | 240 / 240 | 4 | Focus retained; released |
| 10 (saturated) | 90.9% / 96.2% | 37 / 240 | 204 including missing tail | Focus lost; Shift release unobserved |

The fixture submitted all 480 requested reports plus its final release transfer in every case, with
zero device-side late reports. In the calm-through-high cases, every corruption was an unshifted
version of the expected character (`Z→z`, `!→1`, `?→/`, `_→-`, or `+→=`). The error rate did not
increase with CPU load: the calm control had the most errors and the high case the fewest. This is
evidence that CPU load up to the measured 81.1% peak is not required for, and did not amplify, the
modifier-order defect in this matrix.

Full saturation crossed a different boundary: the AppKit oracle became unresponsive long enough to
lose focus and did not observe most input or the final Shift release. Because the independent oracle
lost validity, that row is a system/harness starvation result, not clean KeyPath product attribution.
After all ten workers were terminated, a calm recovery baseline passed 34 / 34 characters and 68 /
68 reports with no stuck key or modifier. KeyPath, Kanata, VHID, the Jig, Wi-Fi, and USB all remained
healthy.

### Kanata-off isolation attempt

The installed `keypath-cli service stop` could not stop the system service because its
`SystemFacade` calls `launchctl kill SIGTERM system/com.keypath.kanata` directly as the unprivileged
user instead of routing through KeyPath's privileged helper. The native **Stop KeyPath Runtime…**
menu command did use the privileged path and successfully stopped Kanata without disabling VHID.

With Kanata confirmed stopped, the fixture submitted all 480 reports for the same 20-cycle shifted
corpus with zero device-side lateness, but the Jig received 0 / 240 characters. This Mac therefore
does not currently route the physical fixture directly to applications when Kanata is absent, so
the result cannot distinguish a Kanata modifier-order defect from device admission/routing below
Kanata. It does establish that the prior corruptions came through the working Kanata/VirtualHID
delivery path. KeyPath was relaunched afterward, and a recovery baseline passed 34 / 34 characters
and 68 / 68 reports with all keys and modifiers released.

## 2026-07-28 Shift-matrix readiness and smoke result

Firmware build `4d1cb1cb54c4` is running from a valid OTA slot and rotated successfully from its stale
`192.168.4.21` address to the configured lab network at `10.0.0.47`. Authenticated status reports
mounted USB, healthy live display frames, and a completed boot splash. The complete host, core,
client, and QEMU suite passes.

The diagnostic compiler now independently varies Shift lead and release lag around a fixed key hold.
The combined runner persists the firmware's exact report trace alongside Jig focus, event, output,
release, and timing evidence. Three three-cell smoke attempts were excluded before HID execution:
the first could not acquire Jig focus after reopening the app, the second was rejected by elevated
macOS memory pressure, and the third timed out at the 0.9x-per-core competing-load ceiling while the
operator was on a video call. The third artifact is
`~/.local/state/keypath-hid-capture-jig/modifier-matrix/shift-smoke-20260728T140721Z/summary.json`;
it records zero completed cases and zero submitted reports. These are fail-closed harness admissions,
not KeyPath test outcomes.

Focus orchestration now preserves an existing healthy Jig, waits for resources without activating it,
and requests focus only immediately before arm. Physical runs require exclusive use of the active
desktop because real USB keyboard input cannot target a background application.

The admitted smoke run `shift-smoke-20260728T222037Z` completed all three cells:

| Shift lead | Release lag | Output | Firmware trace | Timing |
|---:|---:|---:|---:|---:|
| 0 ms | 0 ms | 24 / 24 exact | 48 reports | 0 late; 34 us maximum |
| 4 ms | 0 ms | 24 / 24 exact | 58 reports | 0 late; 35 us maximum |
| 8 ms | 0 ms | 24 / 24 exact | 58 reports | 0 late; 34 us maximum |

Every cell retained Jig focus and ended with no pressed keys or active modifiers. The combined
summary is
`~/.local/state/keypath-hid-capture-jig/modifier-matrix/shift-smoke-20260728T222037Z/summary.json`.
This proves the harness can execute and correlate the timing variants, but 24 characters per cell
are too few to supersede the earlier 240-character calm failure.

### Full 5x5 Shift lead/release matrix

The full matrix completed all 25 timing cells with a 60-character shifted corpus per cell, a fixed
8 ms key hold, and a 50 ms character interval. It covered Shift lead and release-lag values of 0,
2, 4, 8, and 12 ms. Across 1,500 received characters and 4,000 firmware trace reports, every cell
retained Jig focus, every key and modifier was released, and the fixture recorded zero late reports;
maximum firmware lateness was 175 us.

| Shift lead | Exact cells | Wrong characters | Shift demotions | Result |
|---:|---:|---:|---:|---|
| 0 ms | 1 / 5 | 10 / 300 | 10 | Defect reproduced in 4 / 5 release-lag variants |
| 2 ms | 5 / 5 | 0 / 300 | 0 | Exact |
| 4 ms | 5 / 5 | 0 / 300 | 0 | Exact |
| 8 ms | 5 / 5 | 0 / 300 | 0 | Exact |
| 12 ms | 5 / 5 | 0 / 300 | 0 | Exact |

Every mismatch was a Shift demotion: `_→-`, `?→/`, `Z→z`, or `!→1`. Release lag did not show a
monotonic relationship with corruption: the 0 ms-lead / 4 ms-release cell was exact, while the
other four zero-lead cells produced between one and five demotions. All 20 cells with a 2 ms or
greater Shift lead were exact (1,200 / 1,200 characters).

This isolates the observed defect to modifier assertion timing in the working
fixture → Kanata → VirtualHID → application path. CPU load is not required, firmware deadline
misses are not implicated, and adding a single 2 ms lead before the shifted key removed every
observed corruption in this matrix. The result identifies a reliable reproduction boundary; it
does not yet prove whether the product-side fault is in Kanata's physical-input handling or the
VirtualHID delivery boundary.

The result is combined from these fail-closed artifacts:

- `shift-full-20260728T222602Z`: 10 valid cells (0 and 2 ms lead rows). The next cell was not
  executed after the fixture's Wi-Fi control service timed out.
- `shift-full-resume-20260728T223504Z`: 14 valid cells (4 and 8 ms rows plus four 12 ms cells). The
  final cell was not executed because the Jig's macOS memory-pressure admission timed out.
- `shift-full-final-20260728T224119Z`: the single missing 12 / 12 ms cell, retried only after three
  consecutive healthy resource samples.

The Wi-Fi timeout and memory-pressure rejection are harness-infrastructure events, not product test
outcomes. Neither submitted HID reports for its blocked cell, and only the completed, independently
validated cells are included in the 25-cell result.

## 2026-07-28 demo/control reliability evidence

Two audience-demo attempts are excluded from KeyPath conclusions. The first capture expected 1,200
characters and received 18; the second expected 120 and received 3 before the control request
failed and the old runner finalized early. Both captures ended with no pressed keys or modifiers,
but neither completed the synchronized protocol. Their artifacts are:

- `~/.local/state/keypath-hid-capture-jig/artifacts/physical-usb-cycle-instructed-20260729T010245Z-failed.json`
- `~/.local/state/keypath-hid-capture-jig/artifacts/physical-demo-immediate-20260729T011124Z-failed.json`

These exposed harness defects: transient ESP control loss could discard later evidence, the runner
could finalize before confirming release, the showroom path rebuilt/re-signed the Jig, and the demo
depended on a live Wi-Fi start request. The runner now writes an atomic inconclusive artifact on
every exception, retries bounded control operations, aborts best-effort, waits for the Jig to
observe release, and records control degradation separately. The showroom path now reuses a
source-hashed Jig app and starts a fixed on-device script with top-power then touch, so Wi-Fi is not
on the critical start path.

A read-only control soak against the still-installed pre-diagnostic firmware then completed 20/20
status requests with a 206.745 ms p95, 219.339 ms maximum, no observed reboot, and no build change.
The artifact is
`~/.local/state/keypath-hid-fixture/control/control-soak-20260729T013236Z.json`. An earlier version
of the soak measured 3.2–5.3 second calls because it repeated `.local` resolution for every request;
that result is retained but superseded. Discovery and ESP endpoint latency are now measured
separately. The next firmware install will add reset, heap, Wi-Fi, HTTP restart/request, and handler
latency counters to this evidence.

The USB-removal gate remains unproven on this board without a battery or other independent power:
disconnecting its sole USB-C cable removes both data and power, so it cannot execute or report the
reconnect safety path. Do not count a power-cycle as a USB-unmount acceptance result.

### Post-update control soak

Authenticated OTA installed build `f92209f3ea52` into valid slot `ota_1`; the fixture returned to
idle with mounted USB, healthy display frames, completed splash, and an update-safe release state.
The first diagnostic-bearing soak then passed 120/120 status requests with no failure, reset, build
change, or HTTP server restart. Host-observed latency was 28.153 ms median, 93.715 ms p95, and
105.845 ms maximum. Firmware handler latency peaked at 7.465 ms; the remaining time is host/network
transport rather than response construction. Free heap remained 8.33 MB and minimum free heap was
8.29 MB. The artifact is
`~/.local/state/keypath-hid-fixture/control/control-soak-20260729T014347Z.json`.

This validates the updated control plane under a 120-request idle soak. It does not yet validate
the two-step offline demo's physical buttons/touch/output or control responsiveness concurrent with
a high-rate HID run; those require an exclusive desktop window because the next action emits real
keyboard reports.

### Exact showroom proof

With exclusive desktop ownership and the Jig's three-sample resource gate green, the authenticated
showroom path passed end to end. ESP32 build `f92209f3ea52` submitted all 40 locally timed USB HID
reports for `KeyPath demo OK` plus Return. The independent Jig captured all 16 expected characters,
reported no capture issues, and observed every key and modifier released. The fixture trace also
contained all 40 reports with no lateness beyond the configured zero-tolerance budget. Evidence is
stored in `~/.local/state/keypath-hid-capture-jig/artifacts/showroom-live.json`.

The packaged zero-touch command was then validated separately in 7.1 seconds with the same 40/40
reports, 16/16 characters, clean release, and exact independent result. Its timestamped evidence is
`~/.local/state/keypath-hid-capture-jig/artifacts/showroom-20260729T030744Z.json`.

The saved showroom command now runs 14 cycles for a 20.006-second active presentation. Firmware
build `612941a38ed8` submitted all 560 expected reports; the Jig captured all 224 expected
characters exactly, observed no capture issues, and verified every key and modifier released. The
run deliberately used `admissionMode: demo-bypass`, so it is presentation evidence rather than a
strict KeyPath acceptance result. Its artifact is
`~/.local/state/keypath-hid-capture-jig/artifacts/showroom-20260729T053642Z.json`.

The immediately preceding attempt was rejected before HID emission because an older Jig executable
was still resident after the app bundle had been rebuilt. Showroom and offline demo launches now
restart the source-hashed Jig before arming, preventing an old in-memory protocol or admission policy
from being mistaken for the current build. The rejected attempt retained an inconclusive artifact
and confirmed all keys and modifiers released.

The preceding offline attempt is not counted as a product or fixture failure: the Jig remained
focused and ready but received zero events, while the fixture recorded no top-power or touch event.
That proves only that the physical two-step trigger was not completed during its 30-second window.
The repeatable audience path is now `Scripts/lab/hid-capture-jig-tool showroom`; it requires no
operator timing and retains the full combined artifact.
