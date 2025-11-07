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
- Pending POC. Default behavior remains helper + `launchctl`.

#### Execution (dev-only; no app changes)
- Added debug utility: `dev-tools/debug/smappservice-poc.swift`
  - Usage: `swift run smappservice-poc <plistName> [status|register|unregister]`
  - Example: `swift run smappservice-poc com.keypath.helper.plist status`
  - Note: For a Kanata daemon POC, the target plist must be packaged in the app bundle. This tool reports status and attempts register/unregister, surfacing OSLog diagnostic messages.

#### Results (to be filled after running POC)
- macOS version tested:
- Status transitions observed:
- Prompts/approvals shown:
- Time-to-ready measurements:
- Errors and their clarity:
- TCC/permissions regressions: yes/no
- Recommendation:


