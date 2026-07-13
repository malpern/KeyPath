# Service Readiness Contract

KeyPath uses one evidence contract when deciding whether the Kanata runtime can
currently remap input: `KanataRuntimeReadiness` in `KeyPathWizardCore`.

Runtime readiness requires all three current observations:

1. the Kanata process is running;
2. its TCP endpoint responds; and
3. input capture is active.

Registration is not liveness. An enabled `SMAppService`, a loaded launchd job,
or a startup grace period can explain why readiness is not available yet, but
none of them proves readiness.

## Current ownership

| Type | Responsibility | Relationship to readiness |
| --- | --- | --- |
| `KanataRuntimeReadiness` | Process, TCP, and input-capture evidence | Canonical readiness decision |
| `ServiceHealthChecker.KanataServiceRuntimeSnapshot` | Collects readiness plus launchctl, registration, freshness, and diagnosis metadata | Projects `readiness` |
| `HealthStatus` | Broader system snapshot used by wizard, UI, and CLI | Projects `kanataRuntimeReadiness`; preserves the legacy summary fallback only when explicit process/TCP evidence is absent |
| `ServiceHealthChecker.KanataHealthDecision` | Monitoring policy, including restart warm-up as transiently healthy | Not a readiness result; `.transient` must not satisfy postconditions |
| `ServiceHealthMonitor` | Time-based monitoring, cooldown, and recovery policy | Consumes health observations; does not redefine readiness |
| `ServiceLifecycleCoordinator` | Start, stop, and restart orchestration | A start succeeds only after canonical readiness or explicit pending approval |
| `InstallerPostcondition.runtimeReadyOrApprovalPending` | Installer transaction verification | Uses canonical readiness, with pending approval as a separate terminal state |

## Decision rules

- Current process + TCP + input-capture evidence outranks stale registration
  metadata. This avoids treating an actually running runtime as unavailable
  because an earlier registration probe was stale.
- Pending Login Items approval is an explicit lifecycle result, not runtime
  readiness.
- A TCP warm-up grace period may suppress premature recovery, but it does not
  make a start or installer postcondition successful.
- Input-capture failures are degraded runtime failures even when process and TCP
  checks pass.

## Consolidation boundary

Do not merge `ServiceHealthChecker` and `ServiceHealthMonitor` solely to share
this decision. They live on opposite sides of the installation/AppKit module
boundary and have different jobs: evidence collection versus time-based
recovery policy. Consolidate those types only when a concrete behavior change
requires moving the module boundary.
