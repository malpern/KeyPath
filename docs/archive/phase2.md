## TCP Improvements – Phase 2 Plan (Validate / Subscribe)

### Scope (additive, backward‑compatible, TCP‑only)
- Add two minimal endpoints to kanata’s TCP server:
  - Validate: structured config validation (no change to running state)
  - Subscribe: opt‑in event stream for reload outcomes only
- No UDP, no auth, local IPC only.
- Preserve request/response framing: exactly one JSON object per request. No unsolicited events unless subscribed.

### Goals
- Provide structured, line/column validation feedback before writing configs.
- Eliminate polling for reload readiness/errors (opt‑in events for clients).
- Keep upstream changes minimal, split, and easy to review.

### Protocol additions
- Client → Server:
  - Validate { config: string, mode?: string, session_id?: string }
  - Subscribe { events: ["ready", "config_error"], session_id?: string }
- Server → Client:
  - ValidationResult { warnings: ValidationItem[], errors: ValidationItem[] }
  - ValidationItem { code: string, message: string, line?: number, column?: number }
  - Ready { at: string | number }        // when reload completes ok
  - ConfigError { code: string, message: string, line?: number, column?: number, at: string | number }

Notes:
- Timestamp format: epoch seconds (number). Keep consistent with existing Status/LastReload usage.
- Validate payload limit: 1 MiB max; reject oversize with CONFIG_PARSE/PAYLOAD_TOO_LARGE (see codes below).
- Minimal error codes: CONFIG_PARSE, PAYLOAD_TOO_LARGE, UNSUPPORTED. Avoid large taxonomies.
- All fields optional where reasonable to maintain tolerant decoding.

Examples (framing: exactly one JSON object per line)
```
// Validate (success)
{"Validate":{"config":"defcfg { process-unmapped-keys yes }"}}
{"ValidationResult":{"warnings":[],"errors":[]}}

// Validate (parse error)
{"Validate":{"config":"defcfg { process-unmapped-keys oops }"}}
{"ValidationResult":{"warnings":[],"errors":[{"code":"CONFIG_PARSE","message":"invalid value","line":1,"column":33}]}}

// Subscribe and event flow
{"Subscribe":{"events":["ready","config_error"]}}
{"status":"Ok"}
// After a successful reload (emitted only to subscribers)
{"Ready":{"at":1730959552}}
// After an invalid reload (emitted only to subscribers)
{"ConfigError":{"code":"CONFIG_PARSE","message":"unexpected token","line":12,"column":5,"at":1730959552}}
```

### Kanata server changes
1) Protocol structs
- Add serde types for ValidationResult, ValidationItem, Ready, ConfigError.
- Ensure JSON round‑trip tests.

2) Validate handler (minimal)
- Parse config with kanata_parser::cfg::new_from_str(...).
- On success: return ValidationResult { warnings: [], errors: [] }.
- On parse failure: map parser diagnostics to ValidationItem entries with best‑effort line/column.
- Bound request size (e.g., 1–2 MB) and reject oversize payloads.
  - Decision: hard limit 1 MiB; respond with ValidationResult { errors:[ { code: "PAYLOAD_TOO_LARGE", message: "payload exceeds 1 MiB" } ] }

3) Subscribe handler (scaffold)
- Record per‑connection subscription to ["ready", "config_error"].
- Acknowledge Subscribe with a simple OK object (or reuse existing Ok status if already present).
- Do not emit any events unless subscribed.

4) Event emission (minimal)
- On successful Reload (wait or async), send Ready { at } to subscribed connection(s).
- On reload parse error, send ConfigError with code/message/line/column/at.
- Maintain strict framing and rate limiting (no bursts; one event per reload outcome per subscriber).

### KeyPath client changes
1) TCP client
- Add validate(configString: String) -> ValidationResult (prefer TCP; fallback to local validation if unavailable).
- Add subscribe(events: [String]) helper; ignore silently if not supported.
  - Compatibility: if Subscribe not supported, helper returns false and caller proceeds without events.

2) SimpleMods pipeline
- Pre‑write validation: prefer TCP Validate; if it returns errors, surface structured error details (line/column) and abort write.
- Post‑write: keep Reload(wait) path; optionally subscribe briefly to capture Ready/ConfigError for richer diagnostics (best effort).

3) Diagnostics
- Add a “Validate Now” action to show structured warnings/errors for the current config.
- Keep existing protocol v2 enforcement (auto‑fix via Regenerate Services) unchanged.

### Tests
1) Protocol serde tests (kanata)
- Round‑trip JSON for ValidationResult, ValidationItem.

2) Integration tests (kanata)
- Validate success: empty warnings/errors for a known‑good config snippet.
- Validate failure: errors include code/message with line/column for an invalid snippet.
- Subscribe ACK: returns one JSON object acknowledging subscription.
- Events on reload: with a subscriber, emit Ready on success and ConfigError on failure.
  - Ensure no events are emitted to non‑subscribed connections during request/response path.

3) Client integration (KeyPath)
- validateViaTcp returns structured errors when server supports Validate; falls back to local validation when not.
- Save smoke remains green (duration present); framing invariant maintained.

### Rollout and recovery
- Default behavior unchanged for non‑subscribing clients; Validate is opt‑in.
- Wizard continues to enforce protocol v2; Diagnostics shows handshake and last reload info.
- Rollback: remove Subscribe or Validate handlers without breaking existing endpoints; client already falls back.
  - Compatibility matrix:
    - Server supports Validate & Subscribe → client uses both.
    - Server supports Validate only → client uses Validate; no events.
    - Server supports neither → client falls back to local validation; poll Reload(wait) only.

### Security and performance
- Localhost‑only; no auth.
- Payload limit on Validate and timeouts on handlers.
- Logging stays at info or trace; no noisy debug spam.

### PR split (upstream friendliness)
1) Protocol structs + serde tests only.
2) Validate handler + tests.
3) Subscribe ACK + Ready/ConfigError on reload + tests.

Each PR small, additive, and thoroughly documented with examples.

Files likely touched per PR
- PR1 (structs/tests): External/kanata/tcp_protocol/src/lib.rs; tests under the same crate; docs/tcp.md updates.
- PR2 (Validate): External/kanata/src/tcp_server.rs (handler); parser call‑through; protocol docs; serde tests.
- PR3 (Subscribe + events): External/kanata/src/tcp_server.rs (per‑conn subscriptions + event emit); minimal reload hook; docs + tests.

### Acceptance criteria
- Validate returns structured diagnostics with stable framing; oversize payloads rejected.
- Subscribe only emits events after opt‑in; Ready/ConfigError tested.
- Client uses Validate when available and degrades cleanly otherwise.
- Existing Hello/Status/Reload(wait) behavior and framing remain unchanged.

### Non‑goals
- No UDP, no auth, no global event bus, no breaking changes.
- No long‑lived unsolicited events unless subscribed.

---

Status: Phase 1 complete (v2, reload(wait), framing, logging, diagnostics). Phase 2 implements Validate/Subscribe minimally to improve UX without destabilizing the core TCP path.

