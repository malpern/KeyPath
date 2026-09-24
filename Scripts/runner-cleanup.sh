#!/bin/bash
# Installed as ~/actions-runner-cleanup.sh; replaces the old worktree sweep.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
config="$HOME/.config/keypath-ci-storage.env"
[[ -f "$config" ]] || { echo "Missing $config"; exit 1; }
source "$config"
if pgrep -x Runner.Worker >/dev/null; then
    echo "Runner busy; skipping scheduled CI storage maintenance"
    exit 0
fi
for runner in keypath-mini keypath-mini-2; do
    RUNNER_NAME="$runner" python3 "$HOME/.local/lib/keypath/ci-storage.py" cleanup
done
df -h /System/Volumes/Data "$KEYPATH_CI_VOLUME"
# A warning arrives before the 100 GiB admission floor is crossed. The existing
# weekly LaunchAgent provides the cadence; CI also emits a warning on each run.
headroom=$(python3 - "$KEYPATH_CI_VOLUME" <<'PYTHON'
import shutil
import sys
startup = shutil.disk_usage("/System/Volumes/Data").free // (1024 ** 3)
scratch = shutil.disk_usage(sys.argv[1]).free // (1024 ** 3)
if startup < 150 or scratch < 200:
    print(f"Startup: {startup} GiB free; CI scratch: {scratch} GiB free. Maintenance recommended; CI stops below 100 GiB.")
PYTHON
)
if [[ -n "$headroom" ]]; then
    echo "WARNING: $headroom"
    "$HOME/.local/bin/notify-push" "KeyPath runner disk headroom" "$headroom" 0
fi
