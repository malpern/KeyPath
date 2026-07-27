# KeyPath HID fixture: first-board runbook

This is the shortest safe path from an unopened Waveshare ESP32-S3-Touch-LCD-1.69 to a verified
KeyPath physical keyboard fixture. Run it from the KeyPath feature worktree on the Mac.

## Before the board arrives

```bash
Scripts/lab/pico-hid-fixture-tool configure
Scripts/lab/pico-hid-fixture-tool doctor
```

The secure setup stores three ordered SSID/password pairs plus the control token:

- Profile 1: `529beach`, always attempted first.
- Profile 2: `Alpern-Home`, the non-5 GHz home fallback.
- Profile 3: `iPhone`, used when its hotspot has **Maximize Compatibility** enabled.
- `KEYPATH_FIXTURE_TOKEN`: a random value of at least 16 characters.

Enter values only in Add Secret.app. Do not paste them into chat or pass them as command-line
arguments. Before hardware is attached, `doctor` should pass everything and report only
`wait  board not connected`.

## Install tomorrow

1. Connect the board directly to the Mac with a known data-capable USB cable.
2. Run:

   ```bash
   cd /Users/malpern/local-code/keypath-pico-hid-fixture
   Scripts/lab/pico-hid-fixture-tool install
   ```

3. If the Mac sees no serial device, hold **BOOT**, tap **RESET**, release **BOOT**, and rerun the
   same command.
4. Confirm the brief Hacker Dojo splash is upright and clean, then wait for the display to progress
   from `WAKING UP` to `JOINING LAB` to `READY`.
5. Confirm `READY` shows an IP address and `USB READY` or `USB WAIT`. `USB WAIT` is expected until
   the board is attached to a guest or host that has enumerated its HID interface.
6. Recheck at any time with:

   ```bash
   Scripts/lab/pico-hid-fixture-tool status
   ```

The returned `firmware` and `build` fields identify exactly what is running.

The complete screen language, core allocation, UX sign-off list, and explicitly deferred cleanup
are documented in
[`keypath-hid-fixture-readiness.md`](keypath-hid-fixture-readiness.md).

## Failure routing

| Evidence | Likely layer | Next action |
|---|---|---|
| No `/dev/cu...` device | Cable, port, or boot mode | Use a data cable; enter BOOT/RESET download mode; retry with `--port` if several devices exist. |
| Flash command cannot connect | Bootloader state | Hold BOOT while tapping RESET, release BOOT, and rerun. |
| Display stays dark | Power, board revision, or LCD initialization | Try another data cable/port; retain the flash output; do not start HID acceptance. |
| `JOINING LAB` persists | Wi-Fi credentials or 2.4 GHz reachability | Run `configure` again, rebuild/flash, and confirm the network is 2.4 GHz. |
| IP appears but health check fails | mDNS or Mac network route | Run `status`; test `keypath-hid-fixture.local`; inspect the router for the displayed IP. |
| `USB WAIT` persists | USB enumeration/ownership | Check System Information before attaching the device to a VM; confirm the cable carries data. |
| `ATTENTION` appears | Firmware safety state | Record the exact on-screen detail; query `status` and `trace`; do not repeat a run blindly. |

Production intentionally has no USB serial console: adding one would change the device exposed to
the VM and weaken the HID-only oracle. Use the display for boot/network/USB routing and use the
authenticated status and trace APIs for runtime diagnosis.

## Physical acceptance gate

The software build is not hardware proof. Before calling the fixture ready:

1. Confirm display orientation, full-frame color, icon animation, touch coordinates, and tones.
2. Confirm macOS enumerates one keyboard HID interface and no serial or storage interface.
3. Run a short baseline script and compare requested reports, transfers, CRC, received text, and
   release state.
4. Repeat under CPU, memory, disk, and UI load; timing pressure may switch to `HID PRIORITY`, but
   reports must remain complete and ordered.
5. Verify touch abort, button abort, Wi-Fi abort, and USB removal all finish with a released-key
   report before another run can arm.
