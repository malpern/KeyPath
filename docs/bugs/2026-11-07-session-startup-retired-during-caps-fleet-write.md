# Session startup retired healthy workers during the Caps Lock fleet write

**Date:** 2026-11-07
**Area:** driverless session runtime, all-keyboards Caps Lock

## Symptom

With a Caps Lock rule enabled, KeyPath on the mini never finished starting.
The log repeated:

```
[SessionRuntime] Startup retired state=starting reason=none failure=none
[SessionWorker] Received signal 15; retiring
```

The wizard then opened with "Start driverless remapping" as the only issue.

## Cause

The parent waited a fixed 40 iterations of 100 ms for the worker to report
`running`. In all-keyboards mode the worker first writes the Caps Lock mapping
to every keyboard interface. For each device it reads the current rows,
writes, and reads back, each through a separate `hidutil` run. The mini had a
cl80, an X2A mouse with a keyboard interface, and the KeyPath physical HID
fixture attached. Acquisition took about 5.1 s, so every attempt was retired
mid-write. A stack sample showed the worker in
`SessionCapsMappingFleet.acquire`, waiting on `hidutil`, not hung.

The single-keyboard path writes one device and stayed under the limit, which is
why this appeared only once that Mac moved to all-keyboards mode.

## Fix

The startup wait is time-bounded (`sessionStartupTimeout`, 20 s) instead of
counted. A worker that reports `failed` or `secureInput`, or exits, still ends
the wait at once.

## Follow-up

Batching the per-device `hidutil` runs would shorten startup itself. A worker
that reports progress during acquisition would also let the parent tell a slow
start from a hung one.
