# Manual test: upgrade from public 1.0.1 to the session runtime

Issue [#1353](https://github.com/malpern/KeyPath/issues/1353), ADR-045 Upgrade Constraint.

**Status: not yet run.** It needs a clean macOS VM from `vm-lab` on the mini.
Record each run at the bottom, with the build under test and the lease.

## Setup

1. Create a clean macOS 26 desktop lease (and repeat on 27):
   `vm-lab keypath create --macos 26 --lane unmanaged-ui --desktop --ttl 2h --commit <sha> --installer <signed build>`.
   Follow `docs/testing/remote-installer-lab.md` for admission.
2. Install public **1.0.1** from its GitHub release DMG. Finish its wizard:
   helper, Karabiner driver, Input Monitoring, Accessibility, kanata daemon.
3. Add one simple rule (for example `caps → esc`) and confirm it works.
4. Record the starting state (all should show the 1.0.1 stack):
   ```
   sudo launchctl print system/com.keypath.kanata | head -5
   sudo launchctl print system/com.keypath.helper | head -5
   ps -axo user,pid,command | grep -E 'Library/(KeyPath|HelperTools)/' | grep -v grep
   ls -l /Library/PrivilegedHelperTools/com.keypath.helper /Library/LaunchDaemons/com.keypath.*
   systemextensionsctl list | grep -i karabiner
   ```

## Upgrade

5. Install the build under test over 1.0.1 (drag to Applications, replace). Do
   not reboot. Open it.
6. Expect: remapping does not start. **Settings → Status** shows
   "The keyboard service from KeyPath 1.0.1 is still running" with a
   **Remove Old Service** button. The 1.0.1 rule may still work through the old
   daemon; that is expected until removal.
7. Choose **Remove Old Service**, then **cancel** the password prompt.
   Expect: an error toast "Administrator authorization was cancelled."; the
   refusal and button remain; the daemon is still loaded (step 4 commands).
8. Choose **Remove Old Service** again and authenticate. Count prompts: exactly **one**.
9. Expect: a success toast, KeyPath running, and a sentence about the Karabiner
   driver (it is still installed). The `caps → esc` rule works through the
   session runtime.

## Verify

10. Re-run the step 4 commands. Expect:
    - both `launchctl print` commands report "Could not find service"
    - no root process with a KeyPath bundle path
    - no `/Library/PrivilegedHelperTools/com.keypath.helper`, no `/Library/LaunchDaemons/com.keypath.*`
    - the Karabiner driver still listed by `systemextensionsctl` (not removed by design)
11. `~/Library/Logs/KeyPath/keypath-debug.log` contains `[legacy-cleanup] Verified: nothing left`.
12. Reboot. Log in. Expect: no 1.0.1 daemon or helper comes back, and KeyPath
    starts with no refusal. Check System Settings → General → Login Items:
    record whether a stale KeyPath background item is still listed (a
    ServiceManagement record the app could not unregister; cosmetic, but note it).
13. Follow the guide's driver removal command once (`Karabiner-VirtualHIDDevice-Manager deactivate`)
    and record whether it works as written. Update `guides/upgrading-from-1-0-1.md` if not.

## Variations

- **Karabiner-Elements installed** before the upgrade: the toast says
  Karabiner-Elements uses the driver; Karabiner-Elements still works afterwards.
- **Sparkle update** from 1.0.1 instead of a manual replace, if 1.0.1's appcast
  can reach the build under test.
- **Already removed**: run step 8 a second time. Expect no password prompt.

## Results

| Date | Build | macOS | Lease | Result | Notes |
| ---- | ----- | ----- | ----- | ------ | ----- |
| — | — | — | — | not run | mini offline (Nov 2026) |
