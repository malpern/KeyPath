# HID Jig readiness counted a configured limit as live threads

On 2026-10-12 the macOS26 guest refused arming at 4096 threads despite idle CPU,
low load and ample free memory. SystemResourceMonitor read kern.num_taskthreads.
Apple XNU exposes task_threadmax through that name: the maximum threads allowed
per task, not a measurement. Thus a four-core guest always failed the900/core
inventory threshold. kern.num_threads is also a limit and is not a replacement.

The Jig now obtains the live system total from /usr/bin/top -l1 -n0, using a
fixed C locale, on a utility queue. Only one query can run at a time. Queries
are bounded to two seconds; unknown, failed and over-three-second-old inventory
samples refuse arming. Existing CPU, load, memory, thermal, thread thresholds
and the three-sample stable window are preserved.

Summing proc_pidinfo results is unsafe without privileged visibility: ordinary
users cannot inspect every other user's task. Apple's top executable has the
required system visibility; no Jig privileges or guest settings are changed.
ps -M -A is useful corroboration but its visible rows are not guaranteed to match
top's total. Historical4096 readings must not be relabeled as measurements.

Tests cover failed/timeout/malformed reads, the real production collector,
cache expiry, pending-query exclusion and unavailable-inventory refusal. The
unavailable-inventory regression failed before the fix (two assertions).

Apple sources:
- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c
- https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/thread.c
