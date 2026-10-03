# Scope VirtualHID safety shutdown to the DriverKit backend

The first signed parent remap trial produced the correct physical `q`→`a`,
exact fixture trace and released keys, but failed the live-worker postcondition.
The app log proved MainAppStateController emergency-stopped it after two
confirmed VirtualHID failures. That daemon is intentionally absent in session
mode. Evidence: parent-remap-session-22defddc3cd740e9.

Skip VirtualHID observations in this polling branch for session mode and bind
the pure emergency-stop decision to the selected backend. DriverKit still
requires repeated confirmed failures before emergency shutdown. Session tap,
report heartbeat, TCP readiness and emitted-key cleanup remain supervised by
the existing session lifecycle owner. Tests distinguish absent VirtualHID in
session mode from unsafe DriverKit operation. Signed parent retest is required.
