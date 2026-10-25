# Session worker AppKit launch completion

The signed guest trial reported startup failure after about 30 seconds and the
session report was subsequently removed during cleanup. The original NSError was
not captured, so the exact cause of that failure is not proven.

Persistent session workers and capability probes bypass SwiftUI application startup.
Their entrypoint scheduled the worker task and ran a Foundation run loop without
completing NSApplication launch. Apple's [finishLaunching documentation](https://developer.apple.com/documentation/appkit/nsapplication/finishlaunching())
states that run normally invokes it before entering the event loop. A delayed
NSWorkspace launch handshake is a source-based hypothesis, pending signed guest
integration, rather than an established explanation of the prior failure.

The specialized entrypoint now creates NSApplication, selects prohibited activation,
and calls the real finishLaunching before scheduling the worker task or entering the
run loop. It does not construct KeyPathApp, fabricate delegate callbacks, or post a
launch notification. Worker permissions, ownership validation, output cleanup, and
parent lifecycle admission remain unchanged.

The parent logs the requested nonsecret nonce before NSWorkspace launch, then the
returned PID or bounded NSError domain/code/description. Known bundle, profile,
report-directory, and home paths are redacted. After current-generation readiness
checks and supervision setup, the ready log includes parentPID, workerPID, and nonce.
Generation, application identity, nonce, and liveness are rechecked after arbitrary
callbacks and again after supervision setup before logging readiness. A stale start
returns false without stopping a newer intent. A launch-return log alone is not
runtime readiness.

Validation for this source slice is Swift parsing and pinned formatting. Exercising
the real ready callback sequence requires NSWorkspace startup; no new pure mirror or
large test seam was added. Existing lifecycle/interleaving tests and a signed guest
run remain required to verify launch completion and canonical parent readiness.
