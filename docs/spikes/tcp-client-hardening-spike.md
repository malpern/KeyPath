### Spike: TCP client hardening (timeouts, backoff, reconnect)

#### Questions
- What minimal retry/backoff strategy meaningfully improves resilience to transient failures without increasing complexity or changing APIs?
- What is the latency/UX impact when the server is healthy? When the server is temporarily down but comes back quickly?
- Are framing, protocol v2 handling, and capability gating preserved under retry paths?

#### Scope and Constraints
- Client-only (KeyPath app); do not change transport or server protocol.
- Keep the current `KanataTCPClient` public API.
- Align with `docs/2tcp-improvements.md` (protocol v2, blocking Reload(wait), clean framing).

#### Method (what we tested)
- Baseline behavior with a healthy server:
  - Hello → Status → Reload(wait) end-to-end using existing integration tests (`Tests/KeyPathTests/TCPClientIntegrationTests.swift`).
  - Verified single-object framing and presence of `last_reload` in Status.
- Transient failure scenarios (manual/local):
  - Server temporarily unavailable during connect, then becomes available within hundreds of milliseconds.
  - Timeout on `Reload(wait)` path (simulated by very small `timeout_ms`), then a normal request right after.
- Observability:
  - App logs via `AppLogger` (OSLog backend) for connect/send timeouts and retries.
  - Console to confirm no duplicate or interleaved response framing.

#### Observations
- Healthy server:
  - Connect + Hello + Status + Reload(wait) behave deterministically; latency dominated by server processing time.
  - No regression in baseline latency; retry logic does not trigger when the first attempt succeeds.
- Server down then up (short window, <1s):
  - First attempt times out or fails to connect; a short backoff before a single retry allows the second attempt to succeed when the server has come up.
  - Framing invariants preserved (one JSON object in reply path); subscribe/event flow unaffected.
- Server persistently down:
  - Behavior remains a bounded-failure: the client surfaces timeout/connectionFailed after the limited retry, avoiding long hangs.

#### Trade-offs and Justification
- A single retry with a small backoff (on connect/send) is sufficient to mask brief races (daemon/service startup, short hiccups) without the risk of connection storms or cascading retries.
- Not introducing parameterization/jitter yet keeps complexity low and avoids changing public APIs.

#### Compatibility and Invariants
- API: unchanged; all public methods remain the same.
- Protocol: unchanged; client remains tolerant of v1 and prefers v2.
- Framing: request/response remains one object per request in the blocking reload path.
- Logging: OSLog messages clearly indicate the retry path when triggered.

#### Risks
- Excessive retrying in many clients could amplify load during broader outages; mitigated here by a single retry and small fixed backoff.
- If the backoff is too short relative to daemon startup time, the second attempt may still fail; still acceptable since failure is returned promptly.

#### Metrics (informal, local)
- Healthy path: no measurable overhead; retry path is not exercised.
- Transient outage (~100–300ms): additional ~150ms backoff before the second attempt; success observed when the server comes up within that window.
- Persistent outage: total added latency ≈ timeout + 150ms + second attempt timeout (bounded; see integration test time limits).

#### Alternatives Considered (not pursued in this spike)
- Multi-attempt exponential backoff (e.g., 150ms → 300ms → 600ms): more resilient but higher complexity and longer waits on persistent failure.
- Jitter: beneficial for many concurrent clients; likely overkill for single-localhost IPC.
- Configurable backoff via preferences: increases surface area; defer until a real need appears.

#### Next Steps (if needed)
- Add a small DI seam around the connection factory to unit-test retry without relying on a live server.
- Consider a tiny jitter (±50ms) if future evidence shows thundering herd behavior during concurrent restarts.
- Optional: Prometheus-style counters in logs (connect_attempts, retries, timeouts) to quantify real-world behavior.

#### Alignment with docs/2tcp-improvements.md
- Protocol v2, blocking reload, and framing cleanup remain intact.
- This spike focuses strictly on client resilience (timeouts + single retry) and preserves the documented invariants and capabilities.




