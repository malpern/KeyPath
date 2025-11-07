TCP Improvements – Development Plan (Revised)

Scope guardrails (unchanged)
- Minimal TCP-only: Hello, Status, Reload(wait/timeout_ms). No UDP, no auth for now.
- Single source of truth in UI: derive readiness from Hello/Status only.
- Client tolerance: degrade gracefully if a capability isn’t present.
- Upstream-friendly: keep changes small, isolated, and defensible.

Current status (this checkpoint)
- Kanata
  - ✅ TCP Hello → HelloOk { server, version, protocol, capabilities } (v2) implemented.
  - ✅ TCP Status → StatusInfo { ready, last_reload { ok, duration_ms, epoch } } implemented.
  - ✅ TCP listener active; logs quieted (removed --debug/--log-layer-changes from LaunchDaemon).
  - ✅ Reload(wait=true, timeout_ms) now performs a synchronous reload and replies with a single ReloadResult { ready, timeout_ms, ok, duration_ms, epoch } (blocking v2). Framing cleaned: one object per request.
- KeyPath
  - ✅ `KanataTCPClient` negotiates HelloOk (version/protocol), tolerant decoding for v1 and v2.
  - ✅ Capability gating split: reload requires "reload"; status requires "status".
  - ✅ Wizard summary/detail and Diagnostics aligned on Hello+Status readiness.
  - ✅ Permanent status chip + first-run validation on launch.
  - ✅ Helper repaired and running; install flow working from /Applications.
  - ✅ Client prefers Reload(wait:true, timeout_ms) and falls back to Ok/Error automatically.
  - ✅ Diagnostics shows Last Reload (ok, duration_ms, epoch) and treats Karabiner background services disabled as info (OK).
  - ✅ UI: Save mapping path uses the new reload; verified deterministic success with Wizard all green.

Completed in this step
1) ✅ Deterministic reload (v2/blocking)
   - ✅ Engine tracks reload_epoch and last_reload_duration_ms; server performs sync reload on wait=true and replies once.
   - ✅ Framing cleanup: one JSON object per request (no interleaved Ok/LayerChange in reply path).

2) ✅ Protocol v2 and client/UI updates
   - ✅ HelloOk now includes version/protocol; StatusInfo includes last_reload.
   - ✅ Client parses v2 (with fallback to v1), default timeout raised to 5s, logs reload duration/epoch on success.
   - ✅ Diagnostics surfaces Last Reload info and clarifies Karabiner services disabled is OK.

Next steps (ordered)
3) Diagnostics/UI polish
   - Show HelloOk version/protocol/capabilities in Diagnostics.
   - Include reload duration in Save success toast consistently.

4) Test coverage
   - Keep integration tests for Hello/Status/Reload(wait) and framing running in CI; add UI smoke for Save.

5) Logging defaults
   - Set daemon default to info; rate-limit verbose "not mapped/unrecognized" debug.

6) Helper/daemon ergonomics
   - Provide a one-click "Regenerate Services" (rewrite plists, verify codesign/BTM, kickstart).

7) Migration & rollout
   - Feature-flag protocol v2 (default on), checkpoint tag and GitHub Release.

8) Upstream hygiene
   - Split PRs: (a) protocol v2 structs, (b) blocking Reload(wait) + epoch/duration, (c) framing cleanup, (d) Hello/Status additions.

Developer notes
- Build+deploy: use ./build.sh; install bundled kanata via Wizard; keep app in /Applications for helper.
- Logging: leave kanata at non-debug for normal use; enable only when investigating issues.

Checkpoint tags
- `checkpoint/2025-11-06-kanata-tcp-hello-status-ready` (Hello/Status integrated; UI green)
- `checkpoint/2025-11-06-reload-wait-v1` (Reload(wait) v1 integrated; UI save validated)
 - `checkpoint/2025-11-06-reload-wait-v2-protocol-fix` (Blocking reload, protocol v2, framing cleanup, diagnostics)

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

 