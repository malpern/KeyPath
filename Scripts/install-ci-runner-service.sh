#!/bin/bash
# Install the self-hosted GitHub Actions runner as a boot-time LaunchDaemon.
#
# Why this exists:
#   The CI runner ("keypath-mini") runs on this dev Mac under a service account
#   (`clawd`). It was started manually via `run.sh`, so it did NOT survive reboots —
#   after a restart CI jobs sit in "queued" forever until someone re-runs it by hand.
#
#   The runner's own `svc.sh install` creates a per-user LaunchAgent, which on macOS
#   only runs while that user is logged into a GUI session. `clawd` has no GUI
#   session, so an Agent would not auto-start at boot. This installs a system
#   LaunchDaemon instead, which runs headless as `clawd` from boot.
#
#   Safe to run headless: CI does NO Developer ID signing (ci.yml sets
#   KP_SIGN_DRY_RUN=1 and only runs `swift build` / `swift test` / `cp kanata`), so
#   the runner needs no login-keychain access.
#
# Usage:
#   sudo ./Scripts/install-ci-runner-service.sh            # install/refresh
#   sudo ./Scripts/install-ci-runner-service.sh uninstall  # remove the daemon
#
# Overridable via env: RUNNER_USER, RUNNER_DIR, LABEL.

set -euo pipefail

RUNNER_USER="${RUNNER_USER:-clawd}"
RUNNER_DIR="${RUNNER_DIR:-/Users/$RUNNER_USER/actions-runner}"
LABEL="${LABEL:-com.keypath.ci-runner}"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
ACTION="${1:-install}"

if [[ $EUID -ne 0 ]]; then
    echo "❌ Must run as root: sudo $0 $ACTION" >&2
    exit 1
fi

# Collect every PID in a manually-started runner tree.
#
# run-helper.sh and Runner.Listener carry the absolute runner path, so they match
# reliably. The supervisor is launched as `./run.sh`, so its command line is
# `/bin/bash ./run.sh` with NO path — an arg pattern can't target it without
# risking over-match. Resolve it instead as the parent PID of run-helper.sh.
collect_runner_pids() {
    local helper_pids p ppid all=""
    helper_pids="$(pgrep -f "$RUNNER_DIR/run-helper.sh" 2>/dev/null || true)"
    all="$helper_pids $(pgrep -f "$RUNNER_DIR/bin/Runner.Listener" 2>/dev/null || true)"
    for p in $helper_pids; do
        ppid="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
        # Parent of run-helper is the supervisor; skip launchd (PID 1).
        [ -n "$ppid" ] && [ "$ppid" != "1" ] && all="$all $ppid"
    done
    printf '%s\n' $all | grep -E '^[0-9]+$' | sort -u
}

manual_runner_alive() { [ -n "$(collect_runner_pids)" ]; }

stop_manual_runner() {
    local pids
    pids="$(collect_runner_pids)"
    [ -z "$pids" ] && return 0
    # Signal the whole set at once so the supervisor can't respawn a helper before
    # it gets the signal.
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
}

if [[ "$ACTION" == "uninstall" ]]; then
    echo "🗑️  Removing $LABEL"
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "✅ Removed. (Restart the runner manually with: sudo -u $RUNNER_USER $RUNNER_DIR/run.sh)"
    exit 0
fi

if [[ ! -x "$RUNNER_DIR/runsvc.sh" ]]; then
    echo "❌ Runner service entry point not found: $RUNNER_DIR/runsvc.sh" >&2
    echo "   Is the runner configured at $RUNNER_DIR? Override with RUNNER_DIR=..." >&2
    exit 1
fi

echo "⏸️  Stopping any manually-started runner…"
RUNNER_PIDS_BEFORE="$(collect_runner_pids | tr '\n' ' ')"
stop_manual_runner
sleep 2
# Don't proceed while a manual runner is still alive — two runners on one
# registration conflict, and the daemon can't acquire the listener session.
if manual_runner_alive; then
    echo "⚠️  Runner still alive after SIGTERM; sending SIGKILL…"
    # shellcheck disable=SC2086
    kill -9 $(collect_runner_pids) 2>/dev/null || true
    # The supervisor captured before may persist if its child is already gone.
    # shellcheck disable=SC2086
    [ -n "$RUNNER_PIDS_BEFORE" ] && kill -9 $RUNNER_PIDS_BEFORE 2>/dev/null || true
    sleep 2
fi
if manual_runner_alive; then
    echo "❌ Could not stop the existing runner; aborting so CI isn't left in a split state." >&2
    ps -axo pid,ppid,command | grep -iE "$RUNNER_DIR|Runner.Listener" | grep -v grep >&2 || true
    exit 1
fi

mkdir -p "$RUNNER_DIR/_diag"

echo "✍️  Writing $PLIST"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>UserName</key>
    <string>$RUNNER_USER</string>
    <key>WorkingDirectory</key>
    <string>$RUNNER_DIR</string>
    <key>ProgramArguments</key>
    <array>
        <string>$RUNNER_DIR/runsvc.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <!-- Restart on crash/abnormal exit, but NOT on a clean exit 0 — the runner exits
         cleanly on self-update/re-exec and deprecation, and launchd shouldn't fight that. -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>SessionCreate</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/Users/$RUNNER_USER</string>
        <!-- Tells the runner it's running under a service manager (matches svc.sh). -->
        <key>ACTIONS_RUNNER_SVC</key>
        <string>1</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$RUNNER_DIR/_diag/launchd-runner.out.log</string>
    <key>StandardErrorPath</key>
    <string>$RUNNER_DIR/_diag/launchd-runner.err.log</string>
</dict>
</plist>
PLIST_EOF

chown root:wheel "$PLIST"
chmod 644 "$PLIST"

echo "🔄 (Re)loading the daemon…"
launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
launchctl enable "system/$LABEL"
launchctl kickstart -k "system/$LABEL" 2>/dev/null || true

echo "⏳ Waiting for the runner to come online…"
sleep 6
echo "=== launchd state ==="
launchctl print "system/$LABEL" 2>/dev/null | grep -iE "state|pid =|last exit" | head -4 || true
echo

# Verify the daemon actually launched. If it isn't running, fail loudly with a
# fallback so we never silently leave CI without a runner.
if launchctl print "system/$LABEL" 2>/dev/null | grep -qE "state = running"; then
    echo "✅ Installed. The runner auto-starts on boot and restarts if it crashes."
    echo "   Confirm 'online' at: https://github.com/malpern/KeyPath/settings/actions/runners"
    echo "   Logs: $RUNNER_DIR/_diag/launchd-runner.{out,err}.log"
else
    echo "❌ Daemon did not reach a running state. CI may have no runner right now." >&2
    echo "   Recent stderr:" >&2
    tail -n 15 "$RUNNER_DIR/_diag/launchd-runner.err.log" 2>/dev/null >&2 || true
    echo "   Fallback — start the runner manually:" >&2
    echo "     sudo -u $RUNNER_USER bash -c 'cd $RUNNER_DIR && ./run.sh'" >&2
    exit 1
fi
