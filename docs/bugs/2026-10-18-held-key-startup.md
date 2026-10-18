# Held keys must defer startup, not fail it

The Air's October 18 tour candidate refused managed Caps Lock activation while
`CGEventSource` reported keys down. Wake recovery retried this same refusal, but
ordinary launch treated it as terminal and required reopening KeyPath.

After the owned worker has exited and its mappings have been restored, ordinary
startup now joins the existing session-readiness recovery loop for the exact
`managed-caps-activation-refused: physicalKeysHeld` failure. The loop waits for
all keys up, an active console, and secure input to end before retrying. Worker
activation still checks all keys up itself, closing the race between the parent
readiness check and activation. Stop, Quit, and newer intent invalidate recovery.
Foreign reports, incomplete cleanup, and other failures cannot enter this path.

Do not remove the all-up check: remapping a held key can leave an unmatched key
transition. The combined-session observation does not identify which physical
key caused the refusal. Retryable reports are classified before terminal error
logging, so a normal wait no longer produces a misleading terminal-failure log.

Regression coverage: SessionLifecycleInterleavingTests exercises automatic retry
on release, Quit while waiting, ownership/cleanup refusal, repeated activation
races, and cancellation/new intent in the shared recovery loop. Real Air launch
while typing remains a manual acceptance check for the delivered build.
