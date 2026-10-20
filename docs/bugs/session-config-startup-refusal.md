# Unsupported session configuration is a definitive startup refusal

The startup gate previously checked only permissions and runtime health. Its
created-at grace lasted 140 seconds even when no runtime had launched. Parsed
config admission ran on writes and inside the runtime worker, while capability
workers exited before admission. A preserved unsupported Caps config could
therefore cause repeated capability launches, a long checking state, and setup
wizard routing that could not repair the config.

The live default-profile receipts showed no active worker and repeated
capabilities-only workers during transient validation waits. They did not capture
an actual worker config rejection; the admission and grace defect above was
identified by reviewing the source paths.

The existing lifecycle owner now validates the unchanged current config before
launch or restart stop. Invalid and unavailable validation remain distinct, and
the parser's reason is preserved. A proven invalid result remains failed without
a worker report and bypasses startup grace. A valid retry clears that refusal.
The startup gate also obtains admission once before polling, covering skipped
starts without adding parser polling to its loop. It publishes an edit-and-retry
issue with no automatic repair action. Automatic startup setup routing opens
status instead of the installer for a proven config refusal; explicit wizard
requests remain available.

An owned running tap takes precedence over a rejected edited file. Invalid
restart admission does not stop that runtime, and an explicit stop still uses
the existing owned restoration path. Because each request advances intent, a
refused start or restart rebinds retained worker ownership to supervision under
the new generation, even with a missing/stale heartbeat or a terminated worker.
The existing supervisor checks application/nonce identity and owns cleanup; no
identity remains a no-op. Cancellation and newer stops still supersede that
generation.
Worker validation remains unchanged as the
execution-time safety check.

Focused regressions are in `ServiceLifecycleCoordinatorTests` and
`MainAppStateControllerTests`: no launch for invalid/unavailable admission,
invalid-vs-unavailable status/grace, valid correction, rejected restart preserving
an owned tap with supervision transferred to current intent, and no-start config
refusal without permission/health polling.
