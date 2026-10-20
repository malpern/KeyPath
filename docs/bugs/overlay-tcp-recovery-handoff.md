# Overlay TCP warning during recovery handoff

Air logs on October 17, 2026 showed the runtime ready at 20:49:31.170,
validation successful at 20:49:31.637, and the overlay receiving its first TCP
event at 20:49:32.398. Gating the warning only on validation `.checking`
left a 761 ms false-warning window. Runtime validation and event-stream
reconnection are independent asynchronous boundaries.

The header now retains neutral recovery presentation for up to five seconds
after validation completes while disconnected. Connection clears the state;
a persistent disconnect exhausts the window. Routine validation cannot renew
it within the same disconnected episode. Existing health failures remain
visible through the health indicator. Regression tests replay the handoff,
expiration, non-renewal, and reset on a new connection without real sleeps.

Evidence: `~/keypath-review-evidence/20261017-tcp-handoff/`.
Actual post-wake visual confirmation on the Air remains a manual acceptance gate.
