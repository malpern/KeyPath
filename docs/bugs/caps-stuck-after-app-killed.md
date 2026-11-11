# Caps Lock stayed remapped after KeyPath was killed (2026-11-11)

## Symptom

With a managed Caps Lock rule active (Caps Lock Remap), killing KeyPath with
`kill -9` left Caps Lock mapped to its intermediate key (F18) on every keyboard.
Nothing was running, so Caps Lock did nothing useful until KeyPath next
launched; that launch recovered the mapping.

Found during the Sparkle release gate (`driverless-update-cleanup.md`,
scenario 2) on the Mac mini, macOS 27.3. It reproduced without any update:
3 of 5 plain `kill -9` runs failed.

## Evidence

- The worker noticed its owner die and retired as designed
  (`reason=owner-exited`), but its report said `state: failed`,
  `failure: managed-caps-restoration-pending`.
- One pending restore record per keyboard stayed under
  `~/.config/keypath/.session-caps-mapping/keyboards/<id>/`, owned by the dead
  worker.
- With the error logged, every keyboard's recovery failed with `busy`.

## Cause

The worker restores Caps in `finish()` by calling
`SessionCapsRuntimeSupport.recoverPending`. Each keyboard's lease is taken with
a non-blocking `flock`, so the restore fails at once if anyone holds the lock.

The worker's periodic keyboard check (`checkCapsFleetIfNeeded`) reconciles the
fleet on a global queue, and it holds those same per-keyboard locks while it
runs. Nothing ordered the two. When the owner died during a check, the restore
ran beside it, got `busy` for every keyboard, and gave up.

A graceful Quit never showed this, because the app restores the mapping itself
after the worker exits. Only a dead app left the worker as the sole restorer.

The error was also swallowed: `finish()` recorded the failure in the report
but logged nothing, so the cause took a diagnostic build to find.

## Fix

`SessionCapsFleetSerializer` runs the periodic check and the restore at exit on
one serial queue:

- The restore waits for a check in flight, so the locks are free.
- It sets a flag first, so a check queued later is skipped. Otherwise that
  check could re-apply the mapping after the restore had removed it.

Both failure paths now log the error.

Two consequences:

- **Exit can now wait for a check.** The wait is bounded, because each
  `hidutil` call has a 2-second limit, but a check covering several keyboards
  can take a few seconds. That time comes before the worker's terminal report
  and its power acknowledgement. Before the fix the restore failed at once; a
  short delay that restores Caps is the better trade.
- **Checks run at `.userInitiated` priority** instead of the global `.utility`
  queue, because the restore at exit shares their queue.

The serializer's tests cover the ordering. Only the live runs on the mini cover
the worker's real lease locks.

Verified on the mini: 8 of 8 `kill -9` runs restored Caps (state `stopped`),
against 3 failures in 5 before.
