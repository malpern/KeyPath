#!/bin/bash
# One-click cleanup for privileged helper artifacts (SMJobBless & SMAppService)
# Safe to run multiple times. Requires admin for system locations.

set -euo pipefail

echo "🧹 Cleaning up KeyPath privileged helper artifacts..."

CMDS=(
  "/bin/launchctl bootout system/com.keypath.helper || true"
  "/bin/rm -f /Library/LaunchDaemons/com.keypath.helper.plist || true"
  "/bin/rm -f /Library/PrivilegedHelperTools/com.keypath.helper || true"
  "/bin/rm -rf /Library/PrivilegedHelperTools/com.keypath.helper.app || true"
  "/bin/rm -f /var/log/com.keypath.helper.stdout.log /var/log/com.keypath.helper.stderr.log || true"
)

for c in "${CMDS[@]}"; do
  echo "→ sudo $c"
  sudo bash -lc "$c"
done

echo "🔍 launchctl state after cleanup (best-effort)"
/bin/launchctl print system/com.keypath.helper 2>/dev/null | egrep 'state|pid|program' || echo "(no registration)"

echo "✅ Cleanup complete"

