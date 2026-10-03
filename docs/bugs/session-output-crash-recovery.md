# Session output crash recovery

The driverless worker can die while a generated key remains down. Its private
report is an emitted-output ledger, not just a readiness heartbeat. Applying the
two-second readiness TTL to crash cleanup discarded valid recovery evidence from
a stalled worker. Stop/restart also removed the report without replaying it when
the worker was already dead, or died during the graceful-stop wait. Reading the
ledger before forced termination could miss an output emitted before death.

Recovery now reads the final report only after the owned `NSRunningApplication`
has terminated. Nonce, PID and UID must match that launch, independently of the
readiness TTL. Both supervision and explicit stop use this recovery path, before
report deletion. Each launch is replayed at most once so a later stop cannot
release the same output again after normal physical typing has resumed.

The worker publishes press state before posting a press, and removes release
state from its durable report only after posting the key-up. A SIGKILL between
report publication and posting therefore leaves a conservative release set.
CoreGraphics posting has no delivery acknowledgment; independent observation is
still required to establish that the release reached a target.

The held-crash physical acceptance uses q-to-a, checks generated a is independently
held, then kills only the previously observed owned worker. An observed a-up must
occur while the same fixture run is running with exactly one submitted report.
`running` alone was insufficient: q releases at eight seconds but the fixture
remains running during the cycle tail. Acceptance still requires the final exact
two-report trace, stable target/boot, and no held generated a.

The pure `SessionOutputStateTests` regression checks that a stale owned ledger
remains eligible for cleanup while failing readiness, rejects foreign nonce/PID/
UID, and translates its held keys into ordered releases without an event tap.
The physical acceptance remains a separate owned-guest test; a targeted unit pass
does not prove CoreGraphics delivery or arbitrary crash timing.
