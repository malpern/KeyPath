# Wizard Manual Smoke Checklist (post AutoFixer refactor)

Use this quick pass after AutoFixer or routing changes to confirm UX and readiness polling still feel responsive.

## Pre-req
- Clean macOS user (or fresh test account).
- Build KeyPath debug, ensure `KEYPATH_USE_INSTALLER_ENGINE=1` (default).
- Feature flag `USE_UNIFIED_WIZARD_ROUTER` = true (default).

## Steps
1) **Launch wizard**  
   - Expect summary load without visible long pauses.

2) **Accessibility page**  
   - Deny AX, open page; press “Turn On”.  
   - Grant AX in System Settings.  
   - Verify status flips to green within ~1s (passive 250ms polling).

3) **Input Monitoring page**  
   - Remove KeyPath/kanata entries; open page.  
   - Click Fix → System Settings opens; add both entries, enable.  
   - Verify page goes green within ~5s (250ms polling).

4) **Conflicts page**  
   - Start a dummy conflicting process (e.g., run kanata mock).  
   - Hit Fix; ensure spinner resolves within ~1.5s when process stops.  
   - Refresh shows “No Conflicts”.

5) **Karabiner components**  
   - From a healthy state, tap Fix; ensure it completes without visible stalls.  
   - Check toast/logs for background restart firing only when needed.

6) **Communication page (TCP)**  
   - With service running, page should show “Communication Ready” quickly.  
   - Stop service (`launchctl kickstart -k system/com.keypath.kanata`); page should flip to needs-setup and recover within ~3s after restart.

7) **Fix button (summary)**  
   - Click Fix once; verify no double-spins and state updates after health checks (no arbitrary sleeps).

## Expected signals
- No visible multi-second dead waits; progress moves as polling detects readiness.
- Toasts/errors appear only on actual failures (not timeouts).

## If something regresses
- Re-run `Scripts/lint-no-sleep.sh` (CI enforces).  
- Toggle `USE_LEGACY_VHID_RESTART_FALLBACK=true` for emergency VHID restart path.  
- Capture logs from `~/Library/Logs/KeyPath` and rerun step to see health-check outcomes.
