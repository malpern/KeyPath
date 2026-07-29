# KeyPath HID fixture: first-board runbook

This is the shortest safe path from an unopened Waveshare ESP32-S3-Touch-LCD-1.69 to a verified
KeyPath physical keyboard fixture. Run it from the KeyPath feature worktree on the Mac.

## Before the board arrives

```bash
Scripts/lab/pico-hid-fixture-tool configure
Scripts/lab/pico-hid-fixture-tool doctor
```

The secure setup stores four SSID/password pairs plus the control token. Connection priority is
the current-location network first, followed by the established `1, 3, 2` fallback order:

- Profile 4: `beachFi`, attempted first at the current location.
- Profile 1: `529beach`, the primary lab fallback.
- Profile 3: `iPhone`, used when its hotspot has **Maximize Compatibility** enabled.
- Profile 2: `Alpern-Home`, the non-5 GHz home fallback.
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

   While the application is still running, holding the middle **BOOT** button shows `BOOT HELD`
   and `KEEP HOLDING + TAP BOTTOM RESET`. The display freezes when RESET transfers control to the
   ROM downloader; that is expected because the fixture application is no longer running.
4. Confirm the brief Hacker Dojo splash is upright and clean, then wait for the display to progress
   from `WAKING UP` to `JOINING LAB` to `READY`.
5. Confirm `READY` shows an IP address and `USB READY` or `USB WAIT`. `USB WAIT` is expected until
   the board is attached to a guest or host that has enumerated its HID interface.
6. Recheck at any time with:

   ```bash
   Scripts/lab/pico-hid-fixture-tool status
   ```

The returned `firmware` and `build` fields identify exactly what is running.

The current installation command also lays down the two-slot firmware partition table. This is the
last update that inherently requires BOOT/RESET. Once `status` reports an `otaSlot` beginning with
`ota_`, future application firmware can be installed and verified without touching the board:

```bash
Scripts/lab/pico-hid-fixture-tool update
```

An OTA result is not accepted merely because upload completed: the board must reboot, restore Wi-Fi,
and report the exact newly built identity. A new image that cannot restore the control plane within
60 seconds rolls back to the previous slot automatically.

The complete screen language, core allocation, UX sign-off list, and explicitly deferred cleanup
are documented in
[`keypath-hid-fixture-readiness.md`](keypath-hid-fixture-readiness.md).
Live first-board evidence and the remaining manual rows are tracked in
[`keypath-hid-fixture-physical-results.md`](keypath-hid-fixture-physical-results.md).

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
| OTA command says the fixture is not update-safe | A test is loaded/running or a release is pending | Finish or abort the run, wait for the release report, then retry. |
| OTA upload succeeds but the new build never appears | New image failed health validation or networking | Query `status` for the prior build; it should have rolled back. Use USB BOOT/RESET recovery if unreachable. |

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
