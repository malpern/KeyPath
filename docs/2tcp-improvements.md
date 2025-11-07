TCP Improvements – Development Plan (Revised)

Scope guardrails (unchanged)
- Minimal TCP-only: Hello, Status, Reload(wait/timeout_ms). No UDP, no auth for now.
- Single source of truth in UI: derive readiness from Hello/Status only.
- Client tolerance: degrade gracefully if a capability isn’t present.
- Upstream-friendly: keep changes small, isolated, and defensible.

Current status (this checkpoint)
- Kanata
  - TCP Hello → HelloOk { server, capabilities } implemented.
  - TCP Status → StatusInfo { ready } implemented (minimal shape tolerated by client).
  - TCP listener active; logs quieted (removed --debug/--log-layer-changes from LaunchDaemon).
-  Reload(wait/timeout_ms) request accepted; server returns minimal ReloadResult { ready, timeout_ms } (non-blocking v1).
- KeyPath
  - `KanataTCPClient` tolerant decoding for minimal Hello/Status.
  - Capability gating split: reload requires "reload"; status requires "status".
  - Wizard summary/detail and Diagnostics aligned on Hello+Status readiness.
  - Permanent status chip + first-run validation on launch.
  - Helper repaired and running; install flow working from /Applications.
  - Client prefers Reload(wait:true, timeout_ms) and falls back to Ok/Error automatically.
  - UI: Save mapping path uses the new reload; verified deterministic success with Wizard all green.

Completed in this step
1) Deterministic reload (v1/minimal)
   - Implemented request/response contract and client wiring; UI validated (save works reliably).
   - NOTE: current server implementation returns immediate ready=true (no engine-level blocking yet).

2) Backwards-compat fallback
   - Implemented in client; falls back to Ok/Error when ReloadResult is absent.

Next steps (ordered)
3) Deterministic reload (v2/blocking)
   - Kanata: add real engine-level wait until reload completes (or timeout) before sending ReloadResult.
   - Consider lightweight readiness flag/epoch to avoid polling.

4) Diagnostics hardening
   - Add a single health snapshot call that reads Hello, Status, and last reload outcome.
   - Ensure SystemValidator records TCP readiness alongside engine/service state.

5) Test coverage
   - Add integration tests for Hello/Status/Reload(wait) parsing and capability gating.
   - Add UI smoke test: save-mapping path turns green with wait=true.

6) Upstream hygiene
   - Split PRs: (a) protocol structs + minimal handlers, (b) wait/timeout reload, (c) internal engine plumb.
   - Keep feature flags small; avoid touching unrelated modules.

7) Optional (later)
   - Subscribe/notifications for layer changes (push) once minimal path is proven.
   - Consider authentication design separately.

Developer notes
- Build+deploy: use ./build.sh; install bundled kanata via Wizard; keep app in /Applications for helper.
- Logging: leave kanata at non-debug for normal use; enable only when investigating issues.

Checkpoint tags
- `checkpoint/2025-11-06-kanata-tcp-hello-status-ready` (Hello/Status integrated; UI green)
- `checkpoint/2025-11-06-reload-wait-v1` (Reload(wait) v1 integrated; UI save validated)

## Step-by-step plan for the next improvements

1) Engine reload completion signal (blocking without polling)
- Implement a condition variable (or channel) inside `Kanata` that is notified at the end of `do_live_reload` with the new reload epoch and duration.
- Measure and store `last_reload_duration_ms` and `last_reload_epoch` atomically.
- Acceptance: unit test that waits on the condition and unblocks when reload finishes.

2) Server wait on signal; single reply
- In `tcp_server`, replace the polling loop with a timed wait on the engine signal; on completion/timeout send exactly one JSON reply: `ReloadResult { ok, duration_ms, epoch }`.
- Ensure the legacy `Ok/Error` secondary line is removed for this command path.
- Acceptance: `nc` shows a single object reply; client parser no longer sees interleaved responses.

3) Protocol v2 (explicit version/capabilities)
- Add `PROTOCOL_VERSION = 2` and include it in `HelloOk { version, capabilities }`.
- Extend `ReloadResult` to `{ ok, duration_ms, epoch, error? }`.
- Extend `StatusInfo` to include `last_reload { ok, at, duration_ms, epoch }`.
- Maintain compatibility: v1 fields still accepted by client.
- Acceptance: round-trip serde tests for v1/v2; client negotiates correctly.

4) Client negotiation and UI
- On Hello, capture `version` and `capabilities`; gate features accordingly.
- Prefer v2 `ReloadResult`; fall back to v1 or `Ok/Error` when needed.
- Surface duration/timeout distinctly in Save flow; log error text when provided.
- Acceptance: Save works on both v1 and v2 server; UI shows accurate results.

5) Framing cleanup
- Ensure request/response path emits one JSON object per request; move server-initiated notifications (e.g., `LayerChange`) onto a separate notification send path (or buffer until after reply).
- Client filters/handles notification stream independently of request/response.
- Acceptance: no interleaving in hex dump; request path parsing is deterministic.

6) Tests
- Integration tests covering Hello/Status/Reload(wait ok/timeout/error) and framing.
- Smoke test: Save mapping end-to-end flips green after reload completes.
- Acceptance: tests pass in CI; flake-free.

7) Logging defaults
- Set daemon default to `info`; gate verbose "not mapped/unrecognized" behind a debug flag and add rate-limiting.
- Acceptance: kanata log tail is quiet under normal operation.

8) Helper/daemon ergonomics
- Provide a single "Regenerate Services" action that rewrites plists, verifies codesign and BTM state, and kickstarts daemons.
- Acceptance: one-click repair returns helper/kanata to running within 5s.

9) Migration & rollout
- Feature-flag v2 protocol; default off for canary builds.
- Document rollback to v1; include tag names and installer steps.
- Acceptance: documentation updated; canary toggles verified.

 