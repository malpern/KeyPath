# TCP Client Integration Plan (Hello/Status, Reload wait, Validate, Subscribe)

Status: Plan only (no code)

## Goals
- Use Kanata TCP protocol additions to improve reliability and UX without breaking older servers.
- Strictly additive; fall back gracefully via capability detection.

## Scope
1) Capability handshake (Hello)
   - Send `Hello` on connection; persist `protocol` and `capabilities`.
   - Feature-gate client behavior based on capabilities.

2) Status endpoint
   - Add a lightweight method to fetch `StatusInfo` (engine_version, uptime_s, ready, last_reload).
   - Drive diagnostics/health surfaces from this instead of heuristics.

3) Reload with readiness
   - Send `Reload{ wait: true, timeout_ms: configurable }`.
   - Parse second-line `ReloadResult{ ready, timeout_ms? }`.
   - Fallback: if no capability or timeout, revert to existing behavior.

4) Validate (preflight)
   - Send `Validate{ config, mode }` before write/apply.
   - Parse `ValidationResult{ warnings[], errors[] }` -> surface in UI.
   - Fallback: CLI `--check` when not supported.

5) ErrorDetail (optional second line)
   - When `status: Error` is received, try to read a second structured line `ErrorDetail{ code, message, line?, column? }`.
   - Map structured codes to user-facing diagnostics.

6) Subscribe (optional)
   - Minimal client subscription to `ready` and `config_error` when supported.
   - Non-blocking UI signal path; keep disabled if server does not emit yet.

## Backward Compatibility
- If `Hello` not supported or capabilities are missing:
  - Use current TCP reload without wait; retain existing fallbacks.
  - Use CLI validation.
  - Avoid relying on events.

## Testing
- Unit: request builders and response parsers (StatusInfo, ReloadResult, ValidationResult, ErrorDetail).
- Integration: run vendored Kanata (PR branches) and exercise end-to-end flows.
- Manual: use example client for sanity checks.

## Rollout
- Behind capability detection only; no user-facing toggles required.
- Update internal docs/help surfaces; no behavioral breaking changes.

# TCP Client Integration Plan (Hello/Status, Reload wait, Validate, Subscribe)

Status: Plan only (no code)

## Goals
- Use Kanata TCP protocol additions to improve reliability and UX without breaking older servers.
- Strictly additive; fall back gracefully via capability detection.

## Scope
1) Capability handshake (Hello)
   - Send `Hello` on connection; persist `protocol` and `capabilities`.
   - Feature-gate client behavior based on capabilities.

2) Status endpoint
   - Add a lightweight method to fetch `StatusInfo` (engine_version, uptime_s, ready, last_reload).
   - Drive diagnostics/health surfaces from this instead of heuristics.

3) Reload with readiness
   - Send `Reload{ wait: true, timeout_ms: configurable }`.
   - Parse second-line `ReloadResult{ ready, timeout_ms? }`.
   - Fallback: if no capability or timeout, revert to existing behavior.

4) Validate (preflight)
   - Send `Validate{ config, mode }` before write/apply.
   - Parse `ValidationResult{ warnings[], errors[] }` -> surface in UI.
   - Fallback: CLI `--check` when not supported.

5) ErrorDetail (optional second line)
   - When `status: Error` is received, try to read a second structured line `ErrorDetail{ code, message, line?, column? }`.
   - Map structured codes to user-facing diagnostics.

6) Subscribe (optional)
   - Minimal client subscription to `ready` and `config_error` when supported.
   - Non-blocking UI signal path; keep disabled if server does not emit yet.

## Backward Compatibility
- If `Hello` not supported or capabilities are missing:
  - Use current TCP reload without wait; retain existing fallbacks.
  - Use CLI validation.
  - Avoid relying on events.

## Testing
- Unit: request builders and response parsers (StatusInfo, ReloadResult, ValidationResult, ErrorDetail).
- Integration: run vendored Kanata (PR branches) and exercise end-to-end flows.
- Manual: use example client for sanity checks.

## Rollout
- Behind capability detection only; no user-facing toggles required.
- Update internal docs/help surfaces; no behavioral breaking changes.


