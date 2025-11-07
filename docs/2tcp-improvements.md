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

 