# Unplugging the Caps Lock keyboard stopped all remapping

Found 2026-10-19 by a hardware unplug test on the mini (build c656e34a0, the
malpern/KeyPath#1307 candidate), with the cl80 chosen for Caps Lock and other
keyboards connected.

## What happened

1. Unplugging the cl80 made the worker's periodic lease check fail. Every
   failure there was reported as `managed-caps-ownership-lost`, which is a
   terminal failure, so the whole session stopped, not just Caps Lock rules.
   The lease restore itself was correct: the leased registry entry was gone,
   so `SessionCapsMappingLease.restore` retired the intent without writing.
2. Starting again could not work. A profile with a Caps Lock rule was only
   admitted with managed Caps, and managed Caps needs a current keyboard
   selection. The saved one named a registry entry that no longer existed,
   and automatic setup refuses to choose among several keyboards, so
   `prepareSessionStart` refused the start ("Caps preparation refused:
   selection"). Replugging did not help: a replugged keyboard is a new
   registry instance, so the selection stayed stale until it was re-chosen.
   The same rule also meant that turning Caps Lock setup off stopped every
   rule of a Caps-using profile, despite Settings saying only that Caps rules
   would not run.
3. Status said only "Runtime is stopped". Settings refreshed its keyboard
   list only when the app became active, so it went on showing
   "On · cl80 · Uses F18" for the vanished instance.
4. `SessionCapsSettingsSection.choose()` returned early while `busy`. The
   click that opens the picker can also activate the app, which starts
   `reviewKeyboard()`, so the pick was dropped and the picker reverted with
   no message.
5. The stuck-key incident snapshot attached the legacy daemon's
   `/var/log/com.keypath.kanata.stderr.log`, stale since the driverless
   switch, under "Kanata Stderr".

## Fix

- The worker separates a vanished leased instance
  (`managed-caps-keyboard-disconnected`) from a present one that no longer
  verifies (`managed-caps-ownership-lost`, unchanged). A registry lookup that
  itself fails counts as lost ownership, never as a disconnect.
- `SessionCapsRuntimeSupport.admit` has a third outcome, `capsPaused`: the
  profile needs managed Caps but no keyboard is usable. It runs with nothing
  mapped, so physical Caps Lock passes through as usual and every other rule
  works. No key is reserved, so the profile only has to parse under some
  candidate intermediate. Managed Caps still requires a verified selection.
- On a disconnect the supervisor restarts the session through ordinary
  admission. Automatic setup no longer refuses the start when it cannot choose;
  the session starts paused and says so, naming the keyboard. A reload while
  paused applies in place rather than restarting on every save.
- Settings refreshes on HID connect/disconnect and says when the saved keyboard
  is disconnected or was reconnected and needs choosing again. A pick made
  while busy is queued and applied afterwards.
- The stuck-key snapshot attaches the session worker's last report in
  driverless mode instead of the daemon logs.

## Same-port re-bind (decided 2026-10-19)

Micah chose to re-bind a replugged keyboard automatically. Consent is no
longer strictly per registry instance: `SessionCapsSelection.rebound` accepts
the one connected instance with the chosen keyboard's VID, PID, LocationID and
serial (or the same absence of one), in the same boot. It refuses a different
port, twins at one locator, the original instance still present, and any
other boot. The choice displaced by a disconnect is kept
(`SessionCapsSelectionStore.displaced`), so the keyboard gets it back even
after automatic setup moved Caps rules to the built-in keyboard. Automatic
setup tries the re-bind first. While a displaced choice exists, the session
polls hidutil every two seconds and restarts onto the keyboard when it is
back. An explicit choice, turning setup off, or a new boot ends the claim.
