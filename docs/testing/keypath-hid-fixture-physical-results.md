# KeyPath HID fixture physical acceptance results

## 2026-07-27 first-board session

Hardware: Waveshare ESP32-S3-Touch-LCD-1.69 revision 2. The fixture reported firmware
`0.3.0-esp32s3`, build `f24be33f2d7b`, Wi-Fi `529beach`, and a mounted native USB HID interface.
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

## 2026-07-28 Shift-matrix readiness

The fixture and harness are ready for the next dedicated physical window, but no new KeyPath result
is claimed yet. Firmware build `4d1cb1cb54c4` is running from a valid OTA slot on `beachFi`;
authenticated status reports mounted USB, healthy live display frames, and a completed boot splash.
The complete host, core, client, and QEMU suite passes.

The diagnostic compiler now independently varies Shift lead and release lag around a fixed key hold.
The combined runner persists the firmware's exact report trace alongside Jig focus, event, output,
release, and timing evidence. A three-cell smoke attempt was excluded before HID execution: the first
attempt could not acquire Jig focus after reopening the app, and the second was rejected by elevated
macOS memory pressure. These are fail-closed harness admissions, not KeyPath test outcomes.

Focus orchestration now preserves an existing healthy Jig, waits for resources without activating it,
and requests focus only immediately before arm. Physical runs require exclusive use of the active
desktop because real USB keyboard input cannot target a background application. Reserve about 10
minutes for the three-cell smoke matrix; after it is valid, reserve another 20-30 minutes for the full
5x5 Shift lead/release matrix.
