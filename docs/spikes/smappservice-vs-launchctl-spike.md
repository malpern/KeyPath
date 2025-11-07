### Spike: Evaluate SMAppService for service management vs launchctl

#### Questions
- Can `SMAppService` reliably manage our Kanata LaunchDaemon (install, enable, restart, uninstall) across supported macOS versions without breaking TCC and our current lifecycle?
- What user-facing prompts/approvals occur (Login Items, background items, privileged helper approval), and how do they compare to the current `launchctl` + helper path?
- Does `SMAppService` improve reliability/observability (status, errors) vs. our current approach enough to justify migration risk?

#### Background
- Current production path:
  - Kanata runs as a LaunchDaemon (`com.keypath.kanata`), installed/managed via privileged helper (XPC) which uses `launchctl` and plist installation under `/Library/LaunchDaemons`.
  - Benefits: Battle-tested, explicit control, deterministic logs/behavior. Downsides: Manual plumbing, varied error surfaces, and brittle parsing when diagnosing.
- Existing `SMAppService` usage:
  - The repo already uses `SMAppService` for the privileged helper registration path (see `HelperManager`).
  - We have experience with statuses like `.enabled`, `.notRegistered`, `.requiresApproval` and their user flows.

#### POC Approach (no production switch)
1) Create a minimal POC daemon plist packaged into the app bundle (separate from Kanata), managed via `SMAppService.daemon(plistName:)`.
   - Register → verify status transitions → unregister.
   - Observe System Settings → Login Items and background items UI for prompts/approval flows.
   - Record OSLog diagnostics from `SMAppService` operations.
2) Repeat with a POC that mirrors Kanata’s needs:
   - Supply `ProgramArguments` similar to Kanata (including `--port`), log to a temp file, and validate lifecycle (start, restart, kill).
   - Measure time-to-ready and failure modes.
3) TCC/Permissions sanity:
   - Verify Input Monitoring/App-level TCC identity remains stable (no extra resets) with the app using `SMAppService` for daemon deployment.
   - Confirm we do not inadvertently require additional approvals that harm UX.
4) Rollback plan:
   - Ensure POC uninstall fully removes SM-registered daemon and that our current helper-based `launchctl` path can re-install cleanly.

#### Evaluation Criteria
- Reliability:
  - Register/unregister success rate, clear error reporting, status introspection (vs `launchctl print`).
  - Startup race behavior and restart handling (kickstart parity).
- UX/Prompts:
  - Number and clarity of prompts (Login Items approvals). Any additional friction vs current approach.
- Compatibility:
  - macOS version coverage (SMAppService daemon requires macOS 13+). Behavior on older versions (fallback required).
- TCC Stability:
  - No regression in Input Monitoring/Accessibility permissions persistence across updates.
- Observability:
  - OSLog clarity, diagnostic value compared to current logs.

#### Trade-offs
- Pros of `SMAppService`:
  - First-party API for app-managed services with structured status, fewer `launchctl` shell calls.
  - Potentially clearer user approval flows aligned with System Settings’ background items.
- Cons/Risks:
  - Behavior and approval UI vary by macOS version; tighter coupling with Login Items.
  - Migration risk: users mid-upgrade might end up with duplicated/competing registrations if not handled carefully.
  - Requires robust rollback to `launchctl` path.

#### Proposed Plan (if POC is positive)
- Keep default path as-is for one release; ship POC code path behind a developer flag (not exposed to users).
- Add automated checks in Diagnostics to report `SMAppService` status (off by default).
- Document migration steps for a future staged rollout (detect legacy `launchctl` job → unregister → register via `SMAppService` → verify).

#### Rollback Plan
- One-click rollback in Diagnostics: Unregister SM daemon, re-install via helper/`launchctl` and kickstart.
- Ensure log surfaces clearly indicate which path is active.

#### Acceptance (for enabling the option in dev builds only)
- POC daemon can be registered/unregistered reliably with clear OSLog.
- No unexpected TCC or Login Items regressions during POC testing.
- Diagnostics can report SM status without interfering with current behavior.
- Legacy path remains default and fully functional.

#### Open Questions
- How does `SMAppService` daemon registration interact with sandbox/signing in our distribution pipeline (notarization, stapling)?
- Are there edge cases with user migrations (e.g., existing LaunchDaemon left registered) that require extra cleanup?

#### Status
- ✅ POC utility added as executable target in Package.swift
- ✅ Standalone test scripts created
- ✅ App bundle exists at `dist/KeyPath.app` with helper plist
- 🚀 Ready for Phase 1 testing now
- Default behavior remains helper + `launchctl`.

#### Execution (dev-only; no app changes)
- Enhanced debug utility: `dev-tools/debug/smappservice-poc.swift`
  - Usage: `swift run smappservice-poc <plistName> [action] [options]`
  - Actions: `status`, `register`, `unregister`, `lifecycle`
  - Options: `--verbose`, `--create-test-plist`
  - Example: `swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose`
  - Features:
    - OSLog diagnostics integration
    - Timing measurements for register/unregister operations
    - Lifecycle testing (register → wait → check → unregister)
    - Test plist generation utility
    - Comparison with `launchctl print` output
  - Note: For a Kanata daemon POC, the target plist must be packaged in the app bundle at `Contents/Library/LaunchDaemons/<plistName>`.

- Standalone test scripts (no build required):
  - `dev-tools/debug/test-smappservice-simple.swift` - Simple validation test
    - Validates SMAppService API availability
    - Creates test plist for future use
    - Works without requiring app build
    - Usage: `swift dev-tools/debug/test-smappservice-simple.swift`
  - `dev-tools/debug/test-smappservice-standalone.swift` - More comprehensive standalone test
    - Finds existing app bundles
    - Creates test plists in app bundles or standalone
    - Usage: `swift dev-tools/debug/test-smappservice-standalone.swift --create-test-plist`

#### Analysis & Findings

##### Current State Assessment
- **SMAppService Usage**: Already successfully used for privileged helper (`HelperManager.swift`)
  - Helper plist packaged at `Contents/Library/LaunchDaemons/com.keypath.helper.plist`
  - Status handling covers `.enabled`, `.notRegistered`, `.requiresApproval`, `.notFound`
  - Registration/unregistration working in production
  
- **Kanata LaunchDaemon**: Currently managed via `launchctl` through `LaunchDaemonInstaller`
  - Uses privileged helper (XPC) to install plist to `/Library/LaunchDaemons`
  - Bootstrap/kickstart via shell commands
  - Service dependency order critical (VirtualHID → Kanata)

##### Open Questions - Answered

**Q: How does SMAppService daemon registration interact with sandbox/signing?**
- **Answer**: Should work identically to helper registration:
  - Plist must be in app bundle at `Contents/Library/LaunchDaemons/`
  - App must be properly signed (Developer ID or App Store)
  - Notarization/stapling should not interfere (helper path demonstrates this)
  - Key requirement: Plist must reference executables within the signed bundle or system paths
  - For Kanata: Would need to use bundled kanata path (`Contents/Library/KeyPath/kanata`) or ensure system-installed kanata is properly signed

**Q: Edge cases with user migrations?**
- **Answer**: Yes, requires careful handling:
  - Legacy `launchctl`-managed daemon may exist at `/Library/LaunchDaemons/com.keypath.kanata.plist`
  - Must detect and clean up before SMAppService registration
  - Migration path: Check `launchctl print system/com.keypath.kanata` → unload → remove plist → register via SMAppService
  - Rollback: SMAppService unregister → helper reinstalls via launchctl

##### Key Differences: Helper vs Daemon SMAppService

| Aspect | Helper (Current) | Daemon (Proposed) |
|--------|------------------|-------------------|
| Plist Location | `Contents/Library/LaunchDaemons/` | Same |
| Executable | `Contents/Library/HelperTools/` | System path or bundled |
| User Approval | Login Items prompt | Same (background items) |
| Privileges | Root via SMJobBless | Root (system daemon) |
| Restart Control | Via XPC | Via SMAppService (limited) |

##### Critical Considerations

1. **Restart/Kickstart Parity**:
   - `launchctl kickstart -k` provides immediate restart
   - SMAppService has no equivalent - unregister/register cycle required
   - May impact recovery time for crashed services

2. **Service Dependencies**:
   - Current: Explicit bootstrap order (VirtualHID → Kanata)
   - SMAppService: No explicit dependency management
   - Risk: Kanata may start before VirtualHID services are ready

3. **Observability Gap**:
   - `launchctl print` provides detailed service state
   - SMAppService status is binary (enabled/notRegistered/requiresApproval/notFound)
   - May need hybrid approach: SMAppService for registration, launchctl for status checks

4. **macOS Version Compatibility**:
   - SMAppService.daemon requires macOS 13+
   - Current minimum: macOS 15.0 (per Info.plist)
   - No compatibility concern, but fallback path still needed for edge cases

##### Recommended POC Testing Sequence

1. **Phase 1: Minimal Test Daemon (Standalone - No Build Required)**
   ```bash
   # Option A: Simple standalone test (no build needed)
   swift dev-tools/debug/test-smappservice-simple.swift
   
   # Option B: If app bundle exists, test with helper plist
   swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose
   
   # Option C: Create test plist for future use
   swift dev-tools/debug/test-smappservice-standalone.swift --create-test-plist
   ```
   - Validates SMAppService API availability
   - Creates test plist for future testing
   - Works without requiring app build
   - Once app is built: Validate basic registration/unregistration
   - Observe System Settings prompts
   - Measure timing

2. **Phase 2: Kanata-like POC**
   - Create plist with Kanata-like ProgramArguments
   - Test with bundled kanata binary
   - Validate lifecycle (start, restart via unregister/register, kill)
   - Compare timing vs launchctl kickstart

3. **Phase 3: TCC/Permissions Validation**
   - Install SMAppService-managed daemon
   - Verify Input Monitoring permissions persist
   - Test app update scenario (TCC identity stability)
   - Compare with current launchctl path

4. **Phase 4: Migration/Rollback Testing**
   - Simulate legacy launchctl installation
   - Test migration: detect → cleanup → register via SMAppService
   - Test rollback: unregister SMAppService → reinstall via launchctl
   - Verify no duplicate registrations

#### Results (to be filled after running POC)
- macOS version tested:
- Status transitions observed:
- Prompts/approvals shown:
- Time-to-ready measurements:
- Errors and their clarity:
- TCC/permissions regressions: yes/no
- Recommendation:


