# Kanata TCP Improvements — Proposals from KeyPath Usage

Status: Proposal
Audience: Kanata maintainers and client authors (KeyPath, others)

## Context
KeyPath integrates tightly with Kanata via its TCP server to hot‑reload configuration. For a robust, user‑friendly pipeline we need: reliable validation, transactional applies, explicit readiness, and observable errors. The ideas below reflect real integration needs and should also benefit other GUIs, CLIs, and automation.

## Summary of Gaps Observed
- TCP supports Reload but not Validate; we must shell out to `kanata --check`.
- Reload acknowledges request but doesn’t guarantee “ready to remap”; we poll logs for `driver_connected 1`.
- Errors are returned as free‑form strings; line/column/warning distinctions are lost.
- No health/status endpoint to query driver or service readiness.
- No event stream; consumers scrape log files for signals.

## Proposed Improvements

1) Validate over TCP (preflight)
- Endpoint: `{"Validate":{"config": "<kbd text>", "mode":"strict|lenient"}}`
- Response: `{ status:"Ok", warnings:[…], errors:[{ message, line, column, code }] }`
- Why: Enables instant pre‑write validation and better UX; unlocks editor integrations; avoids shelling out. Useful for any client that lets users edit config.

2) Reload with readiness contract
- Extend `Reload` with options: `{"Reload":{"wait":true, "timeout_ms":2000}}`
- Response semantics:
  - Immediate errors → `{ status:"Error", error:"…" }`
  - If `wait:true`: block until the engine reaches a “ready to remap” state or timeout → `{ status:"Ok", ready:true }`
- Why: Removes reliance on log parsing; simplifies apply pipelines; reduces race conditions across all clients.

3) Health/Status endpoint
- `{"Status":{}}` → `{ status:"Ok", engine_version, uptime_s, ready:true|false, last_reload: { ok:bool, at:"iso8601" }, driver: { installed:bool, connected:bool } }`
- Why: Introspection for GUIs/automation; better troubleshooting; enables dashboards.

4) Structured error taxonomy
- Standard error codes (e.g., `CONFIG_PARSE`, `DUPLICATE_MAPPING`, `UNSUPPORTED_TOKEN`, `RUNTIME_DRIVER`) with human message + optional `line/column`.
- Why: Programmatic handling, localization, consistent UX across tools.

5) Capabilities handshake
- `{"Hello":{}}` → `{ status:"Ok", version:"x.y.z", capabilities:["reload","validate","events","ready"], protocol:1 }`
- Why: Backward/forward compatibility; clients can feature‑detect.

6) Event subscription (log‑free)
- `{"Subscribe":{"events":["ready","config_error","driver_connected","driver_failed"]}}`
- Server sends framed JSON messages per event with timestamps; keep‑alive pings.
- Why: Real‑time UI without parsing `/var/log`; helpful for any controller or GUI.

7) Transactional apply (config push)
- `{"Apply":{"config":"<kbd text>", "wait":true, "timeout_ms":2000}}`
- Server does: validate → swap atomically → reload → wait → respond with `{status:"Ok"}` or detailed failure + rollback.
- Why: Single round‑trip for the common UX; safer applies for everyone.

8) Safe‑mode restart
- `{"Restart":{"mode":"safe"}}` starts engine with remapping disabled; `{"SetMode":{"normal"}}` to resume.
- Why: Allows recovery from bad configs without killing the process; helps users and automated installers.

9) Diagnostics bundle
- `{"Diagnostics":{}}` → returns a small JSON bundle (version, last errors, driver status, last N log events, active config hash).
- Why: Easier bug reports; useful for any support scenario.

10) Request correlation IDs
- Accept optional `request_id`; echo in responses and events; log it server‑side.
- Why: Tracing across clients/threads; useful in multi‑window GUIs and automated systems.

11) Rate limits and back‑pressure
- Return `busy:true` with `retry_after_ms` when the engine is processing a prior apply.
- Why: Prevents thrash from rapid edits; clearer client behavior.

12) JSON schema + examples
- Publish a versioned schema for TCP messages and responses in the repo.
- Why: Encourages compatible clients in any language; reduces ambiguity.

13) Authn/authz options
- Optional local secret or domain socket; allow anonymous on loopback by default.
- Why: Safer default for multi‑user hosts; lets distros harden as needed.

14) Introspection endpoints (stretch)
- `{"ActiveMappings":{}}` returns the resolved mapping set for quick diffs.
- `{"Explain":{"from":"caps"}}` shows which rule wins and why (shadowing).
- Why: Powerful tooling/UX for troubleshooting.

## Prioritization (MVP → Nice‑to‑have)
- MVP: Validate endpoint; Reload `wait` flag; structured error taxonomy; Status endpoint; Event subscription.
- Next: Transactional `Apply`; safe‑mode restart; correlation IDs; rate limits.
- Later: Introspection endpoints; diagnostics bundle; auth options; JSON schema formalization.

## Why This Helps the Ecosystem
- Reduces client complexity and duplicate shelling/heuristics across GUIs/CLIs.
- Makes Kanata easier to integrate with editors and wizards.
- Improves reliability and user trust by making applies observable and reversible.
- Creates a clearer contract for third‑party tooling.


