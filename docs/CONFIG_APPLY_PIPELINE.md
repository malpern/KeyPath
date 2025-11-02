# Config Apply Pipeline

Status: Proposed
Owner: Core

## Motivation
Create a single, reliable pipeline for applying configuration edits that is easy to reason about, observable, and testable. The current logic is spread across `SimpleModsService`, writer/parser, and manager.

## Design

### Types
```swift
actor ConfigApplyPipeline {
    func apply(command: ConfigEditCommand) async -> ApplyResult { /* ... */ }
}

enum ConfigEditCommand {
    case add(fromKey: String, toKey: String)
    case remove(id: UUID)
    case toggle(id: UUID, enabled: Bool)
}

struct ApplyResult {
    let success: Bool
    let rolledBack: Bool
    let errors: [ConfigError]
    let diagnostics: ConfigDiagnostics
}

enum ConfigError: Error {
    case preValidation(errors: [String])
    case postValidation(errors: [String])
    case writeFailed(reason: String)
    case reloadFailed(reason: String)
    case healthCheckFailed(reason: String)
}

struct ConfigDiagnostics {
    let configPath: String
    let beforeCount: Int
    let afterCount: Int
    let cliErrors: [String]
    let timestamp: Date
}
```

### Flow
1. Build target mappings (inject a provider) and coalesce via debounce in caller
2. Pre-write validation on effective config string
3. Transactional write via `ConfigurationManager` (temp file → atomic rename; suppress file watcher)
4. Post-write CLI validation on disk
5. Hot reload (TCP) and wait-for-ready
   - TCP reload returns a JSON payload (status:"Ok" on success) — supported
   - Readiness: Kanata’s TCP "Reload" acknowledges the request but does not guarantee device readiness; we will watch logs for `driver_connected 1` with a short timeout (2–3s)
6. On failure: rollback file and in-memory state; return typed errors + diagnostics

### Observability
- Use `os.Logger` with subsystem `app.keypath` and categories: `config.apply`, `config.validate`, `config.write`, `config.reload`
- Log durations, counts, config path, and outcome

### UI Contract
- Success toast only when `success == true && rolledBack == false`
- Error toast for rollback with detailed diagnostics (copy button)

### Migration
- `SimpleModsService` becomes adapter: builds `ConfigEditCommand`, calls pipeline, maps `ApplyResult` to UI
- `SimpleModsWriter` returns content; actual writes are centralized in `ConfigurationManager`

## Kanata TCP Support (Checked)
- `KanataTCPClient.reloadConfig()` sends `{ "Reload": {} }` and receives a response. We check for `"status":"Ok"` or "Live reload successful" to confirm the command was accepted.
- There is no TCP endpoint for validating a configuration blob; validation remains CLI-based (`kanata --cfg <file> --check`).
- The reload response does not guarantee device readiness; we will retain the log-based readiness watcher for `driver_connected 1` as the final gate.

## Test Plan
- Unit: parser/writer round-trips; pipeline pre/post validation; rollback logic
- Integration: add invalid mapping → post-write validation error → rollback; add valid mapping → reload ok + log readiness observed; delete last mapping → sentinel removed; rapid toggles → serialized outcome

## Risks & Mitigations
- Race conditions → actor serializes; debounce at service-level
- File watcher loops → suppression within `ConfigurationManager`
- Flaky readiness → log sentinel + timeout; expose result in diagnostics


