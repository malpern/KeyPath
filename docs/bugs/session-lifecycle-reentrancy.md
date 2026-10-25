# Session worker ownership across async lifecycle calls

Reviewed 2026-10-04 UTC against driverless experiment checkpoint `f274374e9`.
This is source-level analysis, not a claim of physical D8 acceptance.

`@MainActor` serializes synchronous sections, not complete async operations.
Settings/wizard startup, the menu and emergency-stop tasks, and Secure Input
supervision can independently enter `ServiceLifecycleCoordinator`. Previously,
startup awaited stopping, daemon inspection, NSWorkspace launch, TCP readiness
and AppContext startup while sharing mutable worker/report/nonce fields.
Two starts could launch separate workers and overwrite ownership. A stop could
resume after another launch and clear its fields. Restart released ownership
between its stop and start phases. Neither the transition UI flag nor
`ProcessLifecycleManager.reconcileWithIntent()` prevented these interleavings.

One coordinator-owned `ConfigurationOperationGate` now admits the complete
operation, including both restart phases. It has no configuration directory or
file lease; lifecycle admission is independent of configuration transactions.
Private cleanup never recursively enters that gate. The existing DEBUG start
and stop operations run inside this same production boundary.

Requests publish a new intent generation before admission. A later request
invalidates older startup work. A late NSWorkspace launch remains owned until
its shutdown and ledger recovery complete; cancellation cannot discard its
handle. Stop captures application, nonce and report URL and clears only matching
ownership. Failed termination retains ownership and prevents replacement.

Accepted stop cleanup survives caller cancellation. A cancelled latest queued
start completes with an admitted stop, because its changed intent has already
invalidated the previous worker's supervision. Automatic Secure Input recovery
carries its old intent and cannot override a newer manual stop. Supervision
starts detached so it does not inherit the gate's recursive-operation TaskLocal.
Repeated healthy starts re-adopt the existing worker under the latest generation;
failed TCP readiness stops it rather than leaving it unsupervised.

`SessionLifecycleInterleavingTests` use controlled continuations and fake held
output in the existing DEBUG operations. They cover overlapping starts, stop
during late startup, atomic restart, cancelled queued starts/stops, cancellation
after launch, Secure Input resume versus manual stop, and healthy-worker
supervision adoption. They create no NSRunningApplication, signal no process,
post no CGEvent and never invoke NSWorkspace. Narrow DEBUG readiness and
supervision seams exercise the production healthy-session adoption helper.

The unchanged launch guard prevents application launches in unit tests.
Compilation and targeted execution must be recorded separately from this source
review. Physical held-modifier Secure Input, timeout, sleep/wake and session
transition acceptance remain separate D8 gates.
