# Optional TCP Status must be advertised

October 5, 2026. Experimental driverless branch.

The signed session bridge replies to Hello with protocol1 and supported capabilities,
but implements neither Status nor StatusInfo. An actual guest Status request returned
an unknown-variant error. The mapping-added toast was the only production getStatus
caller and used it only for optional reload timing, after the existing save/error/rollback
checks. It now shows the existing success message directly. getStatus remains available
for compatible servers but checks the advertised status capability before sending.
No status or readiness response is fabricated and no server protocol is extended.

Canonical focused tests passed69 cases (TCPStatusCapabilityTests, TCPClientRobustnessTests
and SimpleModsSaveTests). The new regression proves an unadvertised Status request is
refused before opening a connection and preserves cached Hello. Earlier save failures
were fixture admission failures: those tests selected a missing production bridge path.
They now use the existing SessionBridgeTestFixture and explicitly supplied hash-verified
signed bridge, retaining real parser admission. Log `/private/tmp/keypath-tcp-status-safe-03.log`.
Independent source review and accessibility380/whitespace checks passed.

Legacy opt-in live TCP tests still assume server Status support, echoed request IDs and
uncached repeated Hello requests; those assumptions do not match the bundled bridge.
Keep that test debt distinct from this source fix. The already signed247822796 physical
recovery trials do not contain this newer UI/capability patch. No host installation occurred.

Fresh signed64a1e52a3 acceptance passed in the disposable UID502 guest on October5:
normal AX/IM consent, full7168 tap, editor addition of bspc→del beside q→a,
saved configuration and successful ReloadResult, then physical ESP32 q→a with
all eight checks and empty held ledgers. Hello advertised reload but not status;
the bounded save log contained no unsupported Status request/error. Toast appearance
was not captured, and bspc→del was not a separate physical sample. The worker's
diagnostic config hash retains initialization provenance after reload. Original
profile/process cleanup, VM deletion, retained template and detached nonpersistent
USB independently passed. The hydration-stop255 warning remains recorded.
[Selected live receipt](https://github.com/malpern/KeyPath/blob/experiment/macos-permission-footprint/docs/testing/evidence/2026-10-05-protocol-live-acceptance.json).
