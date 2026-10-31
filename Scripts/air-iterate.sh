#!/bin/bash
# Local iteration on the Air: build a Developer ID-signed KeyPath (no notarization,
# DMG or deploy on this machine), sync it to a staging bundle on the Air, swap it
# into /Applications preserving rules/preferences, relaunch, and verify the owned
# runtime. The previous app is kept as one rolling backup on the Air.
#
# Usage: Scripts/air-iterate.sh [--no-build]
#   AIR_HOST=air            ssh host for the test Mac
#   KEYPATH_DEV_XCODE_DEVELOPER_DIR is honored by the build, as elsewhere.
#
# Not a release path: the installed build is signed but not notarized. Files
# synced over ssh carry no quarantine, and the Developer ID designated
# requirement keeps existing TCC grants.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO="$SCRIPT_DIR/.."
AIR_HOST="${AIR_HOST:-air}"
SSH=(ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=10 "$AIR_HOST")
APP="$REPO/dist/KeyPath.app"
cd "$REPO"

# Keep the Air's display awake for an hour. If it reaches the lock screen,
# loginwindow holds Secure Input and the engine stops seeing keys, which reads
# as a broken build. Uses the dotfiles `agent-awake` when the Air has it.
"${SSH[@]}" 'if [ -x ~/.local/bin/agent-awake ]; then ~/.local/bin/agent-awake local 60;
    else nohup caffeinate -d -i -t 3600 >/dev/null 2>&1 & fi' || true

# Sign from the login keychain unless the caller chose a signing command.
export KP_SIGN_CMD="${KP_SIGN_CMD:-$SCRIPT_DIR/lib/codesign-login-keychain.sh}"

if [ "${1:-}" != "--no-build" ]; then
    SKIP_NOTARIZE=1 SKIP_DEPLOY=1 SKIP_SPARKLE=1 SKIP_SNAPSHOTS=1 SKIP_WEBSITE=1 \
        Scripts/build-and-sign.sh
fi

codesign --verify --deep --strict "$APP"
revision=$(git rev-parse --short=9 HEAD)
dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
built=$(/usr/libexec/PlistBuddy -c "Print :GitCommit" "$APP/Contents/Resources/BuildInfo.plist")
exe_sha=$(shasum -a 256 "$APP/Contents/MacOS/KeyPath" | cut -d' ' -f1)
echo "Candidate: BuildInfo $built (HEAD $revision, $dirty modified tracked files), executable $exe_sha"

# Incremental transfer: only changed files cross the network.
"${SSH[@]}" 'mkdir -p ~/.keypath-iterate'
rsync -a --delete -e "ssh -o ControlPath=none -o BatchMode=yes" "$APP/" "$AIR_HOST:.keypath-iterate/KeyPath.app/"
rsync -a -e "ssh -o ControlPath=none -o BatchMode=yes" Scripts/verify-installed-app.sh Scripts/verify-apple-silicon.sh \
    Scripts/verify-session-runtime.py "$AIR_HOST:.keypath-iterate/"

"${SSH[@]}" bash -s "$exe_sha" <<'REMOTE'
set -euo pipefail
want=$1
stage="$HOME/.keypath-iterate/KeyPath.app"
app=/Applications/KeyPath.app
exe="$app/Contents/MacOS/KeyPath"
[ "$(shasum -a 256 "$stage/Contents/MacOS/KeyPath" | cut -d' ' -f1)" = "$want" ] || { echo "staged executable mismatch"; exit 1; }
codesign --verify --deep --strict "$stage"

# One rolling backup of the app being replaced (rules/preferences are untouched).
if [ -d "$app" ]; then
    rm -rf "$HOME/.keypath-iterate/KeyPath-previous.app"
    ditto "$app" "$HOME/.keypath-iterate/KeyPath-previous.app"
fi

pids=$(ps -axww -o pid=,args= | awk -v e="$exe" '{p=$1; $1=""; sub(/^ /,""); if ($0==e || index($0, e" ")==1) print p}')
parent=$(ps -axww -o pid=,args= | awk -v e="$exe" '{p=$1; $1=""; sub(/^ /,""); if ($0==e) print p}')
[ -n "$parent" ] && kill -TERM $parent
alive=0
for _ in $(seq 1 30); do
    alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ $alive = 0 ] && break; sleep 1
done
[ $alive = 0 ] || { echo "old KeyPath processes did not exit"; exit 1; }

aside="/Applications/.KeyPath-old-$$.app"
[ -d "$app" ] && mv "$app" "$aside"
if ! ditto "$stage" "$app"; then
    rm -rf "$app"; [ -d "$aside" ] && mv "$aside" "$app"; echo "copy failed, restored"; exit 1
fi
rm -rf "$aside"
open "$app"
sleep 8
cd "$HOME/.keypath-iterate"
# Signature, bundle and CLI checks never depend on the screen: fail on them.
if ! CHECK_RUNTIME=0 REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 bash ./verify-installed-app.sh >verify.log 2>&1; then
    tail -5 verify.log
    exit 1
fi
if ! REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 bash ./verify-installed-app.sh >verify.log 2>&1; then
    # Only the runtime check may wait: a locked screen holds Secure Input and
    # KeyPath starts after unlock. Any other Secure Input holder is a failure.
    locked=$(ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw - 2>/dev/null || true)
    if [ "$locked" = "true" ] && ioreg -l -w0 | grep -q '"kCGSSessionSecureInputPID"'; then
        echo "Installed and verified. The screen is locked: remapping starts after unlock."
        exit 0
    fi
    tail -5 verify.log
    exit 1
fi
tail -2 verify.log
REMOTE
echo "Installed on $AIR_HOST at $(date '+%T')."
echo "Roll back (on the Air, KeyPath quit): mv /Applications/KeyPath.app /Applications/.KeyPath-bad.app && ditto ~/.keypath-iterate/KeyPath-previous.app /Applications/KeyPath.app && rm -rf /Applications/.KeyPath-bad.app"
