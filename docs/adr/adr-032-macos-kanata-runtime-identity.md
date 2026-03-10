# ADR-032: Stable App-Bundled Runtime Identity for macOS Kanata Input Capture

## Status

Proposed

## Date

2026-03-07

## Context

KeyPath currently uses two different identities for macOS Kanata operation:

1. `SMAppService` launches `Contents/Library/KeyPath/kanata-launcher` from the app bundle.
2. The launcher prefers `exec` into `/Library/KeyPath/bin/kanata`.
3. `PermissionOracle`, wizard guidance, and documentation have historically treated
   `/Library/KeyPath/bin/kanata` as the canonical Input Monitoring target.

This split has produced an unstable and confusing model:

- runtime launch subject, permission target, and user guidance can disagree
- health could previously report green while built-in keyboard capture was denied
- users can be instructed to grant permissions to a binary path that does not match the
  effective runtime subject observed by macOS
- upgrades and redeployments can invalidate the apparent working state without any real
  architecture change

Recent investigation on a laptop-only setup showed:

- KeyPath.app had Input Monitoring
- Kanata was running and TCP-responsive
- stderr reported `IOHIDDeviceOpen error: (iokit/common) not permitted Apple Internal Keyboard / Trackpad`
- the launchd job lived in the user GUI domain and identified `kanata-launcher` as the program

This means the current model is not a reliable long-term basis for built-in keyboard capture on
macOS.

The relevant architectural constraints remain:

- `PermissionOracle` owns permission-state detection ([ADR-001](adr-001-oracle-pattern.md))
- Apple APIs remain authoritative where applicable ([ADR-006](adr-006-apple-api-priority.md))
- installer and repair mutations must flow through `InstallerEngine` ([ADR-015](adr-015-installer-engine.md))
- validation must prefer prerequisites over derivative health signals ([ADR-026](adr-026-validation-ordering.md))
- runtime readiness must be postcondition-verified, not inferred from registration metadata
  ([ADR-031](adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md))

External platform and upstream evidence points in the same direction:

- Apple’s Input Monitoring model is app/process oriented.
- Apple’s daemon guidance distinguishes system daemons from user-specific agents.
- Kanata upstream found `IOHIDCheckAccess()` unreliable for root-process self-checks on macOS.
- Karabiner-Elements uses a split architecture with a stable app-owned runtime identity rather
  than a loose copied CLI path as its public permission model.

Additional local runtime evidence from the bridge-host spike:

- a bundled host process running as the logged-in user can validate config and construct a real
  Kanata runtime in-process
- but a full in-process launch reaches pqrs VirtualHID access and then fails against
  `/Library/Application Support/org.pqrs/tmp/rootonly/...`
- this indicates the long-term design must separate **user-session input capture** from whatever
  **privileged/root-scoped output bridge** is required to talk to the DriverKit daemon

## Decision

Adopt a long-term macOS runtime architecture in which a **stable app-bundled executable identity**
owns Kanata input capture.

### Core rules

1. **The process that opens HID devices must be the stable permission-bearing identity.**
   - Do not rely on a thin launcher that immediately `exec`s into a different raw binary path for
     actual input capture.

2. **Input capture must be intentionally user-session scoped.**
   - The HID-owning runtime should run as an app-bundled background runtime in the logged-in user
     context, not as an accidental hybrid of GUI registration plus copied system binary execution.

3. **System-installed raw Kanata binaries are not the long-term TCC contract.**
   - `/Library/KeyPath/bin/kanata` may remain as an implementation artifact during migration, but
     it must not remain the canonical user-facing Input Monitoring identity.

4. **Permission detection remains in the GUI layer.**
   - `PermissionOracle` continues to own permission detection and wizard guidance.
   - Root/runtime self-checks are not promoted to the source of truth for TCC state.

5. **Runtime truth remains mandatory.**
   - Permission declaration alone is insufficient.
   - Health and installer postconditions must continue to require real runtime readiness, including
     successful built-in keyboard capture where applicable.

### Target component model

- `KeyPath.app`
  - UI
  - permission guidance and detection
  - diagnostics
  - orchestration

- `KeyPath macOS input runtime` (new bundled runtime identity)
  - the executable that directly opens HID devices
  - hosts or embeds the macOS Kanata runtime in-process
  - owns the stable bundle/code-signing identity used for Input Monitoring

- `KeyPathHelper`
  - privileged install/repair operations only
  - no ownership of Input Monitoring detection

- Driver/VHID services
  - remain separate and privilege-scoped
  - continue to be installed/repaired via `InstallerEngine`

- Root-scoped output bridge (new or adapted)
  - owns whatever privileged connection is required for pqrs VirtualHID output
  - must not become the Input Monitoring identity
  - should be treated as the output half of a split runtime rather than the full remapping owner
  - should speak a narrow versioned protocol:
    - session handshake
    - key event emission
    - modifier synchronization
    - reset / ping / explicit error reporting

## Comparison with Karabiner-Elements

### Similarities we should adopt

- Split GUI, privileged install, and input-runtime responsibilities cleanly.
- Use a stable app-owned runtime identity for Input Monitoring.
- Keep permission UX in the user session rather than relying on root-runtime self-reporting.
- Separate driver/device management from user-facing permission guidance.

### Differences from Karabiner-Elements

- KeyPath should preserve its existing `InstallerEngine` / `PermissionOracle` architecture rather
  than cloning Karabiner’s full process graph.
- KeyPath should aim for the minimum number of long-lived support processes needed to get a stable
  permission and runtime model.
- KeyPath currently depends on upstream cross-platform Kanata source rather than owning a fully
  native macOS remapping core, so its migration path is primarily about **runtime hosting** rather
  than inventing a new remapping engine.

## Consequences

### Positive

- Gives macOS a single stable runtime identity for built-in keyboard capture.
- Removes the current mismatch between launch subject and permission target.
- Aligns KeyPath more closely with Apple’s user-session model for permissioned input capture.
- Makes wizard guidance and runtime behavior easier to reason about across upgrades.
- Preserves the March 2026 health-model fix as a correct guardrail rather than a workaround.

### Negative

- Introduces macOS-specific runtime-hosting work around Kanata.
- Likely requires refactoring away from `kanata-launcher -> exec(/Library/KeyPath/bin/kanata)`.
- Increases packaging and upgrade complexity during migration.
- Requires careful regression testing for app updates, stale registrations, and permission
  persistence.

## Maintenance Impact

This approach **does add some macOS-specific maintenance**, but it does not require KeyPath to fork
Kanata wholesale.

The intended maintenance boundary is:

- keep using upstream Kanata as the cross-platform core where possible
- add a macOS-specific host/runtime layer in KeyPath that gives the core a stable app identity
- minimize permanent divergence by keeping macOS-specific packaging, launch, and permission logic in
  KeyPath rather than in a long-lived downstream Kanata fork

Preferred order of implementation effort:

1. Host the existing macOS Kanata runtime inside a bundled KeyPath-owned executable identity.
2. Keep upstream Kanata source updates flowing normally.
3. Limit downstream patches to narrowly scoped macOS integration work when upstream cannot absorb
   them.

This is still a better trade than continuing to depend on a fragile raw-binary TCC identity that
breaks unpredictably across reinstalls, redeployments, and system state changes.

## Alternatives Considered

### 1. Revert to the prior raw-binary permission model

Rejected.

It may appear to work when TCC state happens to line up, but it does not provide a stable contract
between launch subject, installer guidance, and runtime capture behavior.

### 2. Keep the current launcher but retarget `PermissionOracle` to `kanata-launcher`

Rejected as the long-term solution.

This improves observability of the current mismatch but does not solve the deeper problem that the
HID-owning process should itself be the stable runtime identity rather than a launcher that hands
off work to another executable path.

### 3. Move all permission logic into the runtime daemon

Rejected.

This conflicts with `PermissionOracle` ownership and with upstream evidence that daemon/root
permission self-checks are unreliable on macOS.

## Implementation Notes

When implementing this ADR:

- use `InstallerEngine` for all install/repair/migration flows
- keep `PermissionOracle` as the only owner of permission-state detection
- do not weaken health checks to hide runtime capture failure
- update launch-domain assumptions in service/diagnostic code to match the actual target model
- add upgrade and regression coverage for:
  - fresh install
  - in-place update
  - stale registration recovery
  - laptop-only built-in keyboard capture
  - permission persistence across redeployments
- remember that upstream already exposes a Rust library target, `kanata_state_machine`, but not a
  stable C ABI for Swift to call directly
- use `Scripts/build-kanata-runtime-library.sh` only as a non-shipping validation step for the
  future host-embedding path; the next real milestone is a narrow Rust bridge crate with C-callable
  entry points
- keep any bridge crate outside the vendored upstream tree so KeyPath can update Kanata normally
  while owning only the macOS host-integration surface

### Progress note as of 2026-03-08

This ADR remains `Proposed`, but the target architecture has now been proven experimentally in this
worktree.

Verified experimental result:

- a bundled user-session `kanata-launcher` host can capture real keyboard input
- the host can feed that input into an in-process passthrough Kanata runtime
- the passthrough runtime emits output events
- those events can be forwarded over the privileged helper-backed output bridge
- the privileged bridge acknowledges those output events successfully

What this means:

- the architecture direction in this ADR is now validated as technically viable
- the remaining work is primarily productionization:
  - lifecycle hardening
  - bridge-session management
  - clearer long-term privileged output component boundaries
  - migration/rollback safety
  - sustained reliability validation

What this does **not** mean yet:

- the split runtime is ready to replace the legacy shipping path
- the current helper-backed bridge is automatically the final privileged component design
- the current experimental capture path is the final host-owned input implementation

### Naming note

The naming model that emerged from this work is:

- **KeyPath Runtime** for the normal user-facing runtime concept
- **Kanata** for the underlying engine, engine setup, engine binary, versioning, and low-level diagnostics
- **RecoveryDaemonService** / **Output Bridge Daemon** for internal infrastructure seams

This keeps the product UX simple without obscuring that KeyPath is built on Kanata.

### Progress note as of later 2026-03-08

The helper-backed privileged bridge has now been replaced experimentally by a dedicated privileged
launch daemon:

- `com.keypath.output-bridge`
- executable:
  `/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathOutputBridge`

`KeyPathHelper` now prepares and activates bridge sessions but does not own the runtime bridge
listener or output emission path itself. A signed-app validation run confirmed:

- the helper installed and bootstrapped `system/com.keypath.output-bridge`
- `launchctl print system/com.keypath.output-bridge` reported the daemon running
- the user-session host still forwarded output successfully through the daemon and received
  acknowledgements

So the architecture target in this ADR is no longer only “split runtime is viable.” It is now
“split runtime with a dedicated privileged output daemon is viable.” The remaining work is rollout,
lifecycle hardening, and deciding when the split runtime should move beyond experimental/internal
diagnostic paths.

Later on March 8, 2026, the dedicated-daemon design also passed a live signed-app restart-soak
probe in capture mode:

- the persistent split host ran in capture mode
- the dedicated `com.keypath.output-bridge` daemon was restarted mid-run
- the app recovered the split host onto a fresh bridge session
- the host remained alive through the second half of the soak window

That moves the remaining work from “can the app recover from a privileged output restart?” to
“how and when should this recovery path be promoted from experimental/internal tooling into the
default runtime lifecycle.”

Later on March 8, 2026, KeyPath crossed an important cutover threshold in this worktree:

- split runtime became the default-on path for healthy fresh installs
- ordinary startup, restart, and recovery flows were switched to prefer split runtime first
- the old launchd-managed Kanata path was renamed in status/reporting to `Legacy Recovery Daemon`
  to reflect its remaining role
- automatic fallback from an unexpected split-host exit back into the old daemon was removed
- the user-facing `Split Runtime Host` toggle was removed and the app now treats split runtime as
  always on rather than as a persisted experimental setting
- the old `ProcessCoordinator` fast-restart helper was removed from normal app/CLI flows so repair
  now goes through `InstallerEngine` and ordinary runtime control goes through `RuntimeCoordinator`

At this point, the old launchd-managed Kanata path is no longer treated as a co-equal runtime in
the app’s normal lifecycle. It remains only as an explicit recovery seam while the final
deletion/cutover work proceeds.

## Related

- [ADR-001: Oracle Pattern for Permission Detection](adr-001-oracle-pattern.md)
- [ADR-006: Apple API Priority in Permission Checks](adr-006-apple-api-priority.md)
- [ADR-015: InstallerEngine Façade](adr-015-installer-engine.md)
- [ADR-016: TCC Database Reading for Sequential Permission Flow](adr-016-tcc-database-reading.md)
- [ADR-026: System Validation Ordering](adr-026-validation-ordering.md)
- [ADR-031: Kanata Service Lifecycle Invariants and Postcondition Enforcement](adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md)
