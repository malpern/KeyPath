# Published queued-writer checkpoint must not unwind

The DEBUG mapping-only guest trial on October 5 created a checkpoint for child2283, then lost both worker2276 and the child before the first independent observation. Parent2266 survived; original mapping remained empty. Explicit Restart preserved the uncertainty marker and refused recovery. No resume signal or physical event was sent. The original child-survival receipt remains failed; the exact child exit reason is unproven.

`terminateOwnerWithSuspendedWriter` installs a defer that kills and joins its unreaped child on failure. After publishing the checkpoint it requested self-SIGKILL and then threw. If execution continues after the signal request, Swift unwinding invokes that cleanup and destroys the child whose handoff was just published.

The successful publication path now calls `_exit(128 + SIGKILL)` after the signal request, preventing Swift unwinding. Failure before publication retains the existing cleanup. This is DEBUG-only; it does not change normal HID writes, restoration, permissions or default Caps eligibility.

The actual focused lease/transport runner compiles and passes; independent source review passed. These checks do not establish orphan survival. Before claiming queued-writer acceptance, independently observe the exact child executable/arguments/stopped state after worker death, then verify refusal before and after a single validated resume and mapping readback. A suspended queued writer is not evidence of execution inside an opaque HID mutation.

Raw evidence: `/private/tmp/keypath-queued-writer-live-02`; selected receipt on branch `experiment/macos-permission-footprint`: `docs/testing/evidence/2026-10-05-queued-writer-attempt02.json`. Normal Quit and independent canonical disposal passed; no owned VM remains.
