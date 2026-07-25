#!/bin/zsh
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../.." >/dev/null && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat > "$tmp/bin/keypath-cli" <<'EOF'
#!/bin/zsh
print -r -- "${KEYPATH_TEST_STATUS_JSON:?}"
exit "${KEYPATH_TEST_STATUS_EXIT:-0}"
EOF

cat > "$tmp/bin/launchctl" <<'EOF'
#!/bin/zsh
if [[ ${KEYPATH_TEST_LAUNCHD_RUNNING:-0} == 1 ]]; then
  print 'state = running'
  exit 0
fi
exit 113
EOF

cat > "$tmp/bin/tcp-probe" <<'EOF'
#!/bin/zsh
[[ ${KEYPATH_TEST_TCP_READY:-0} == 1 ]]
EOF

cat > "$tmp/bin/verify-lane" <<'EOF'
#!/bin/zsh
[[ ${KEYPATH_TEST_MANAGED_POLICY_VALID:-0} == 1 ]]
EOF

chmod +x "$tmp/bin/"*

ready='{"apiVersion":1,"data":{"isOperational":true,"helperInstalled":true,"helperWorking":true,"helperVersion":"1.2.3","keyPathAccessibility":true,"keyPathInputMonitoring":true,"kanataAccessibility":true,"kanataInputMonitoring":true,"kanataBinaryInstalled":true,"karabinerDriverInstalled":true,"vhidDeviceHealthy":true,"kanataRunning":true,"karabinerDaemonRunning":true,"vhidHealthy":true}}'
degraded='{"apiVersion":1,"data":{"isOperational":false,"helperInstalled":true,"helperWorking":true,"helperVersion":"1.2.3","keyPathAccessibility":true,"keyPathInputMonitoring":true,"kanataAccessibility":true,"kanataInputMonitoring":true,"kanataBinaryInstalled":true,"karabinerDriverInstalled":true,"vhidDeviceHealthy":true,"kanataRunning":false,"karabinerDaemonRunning":true,"vhidHealthy":true}}'
managed_ready='{"apiVersion":1,"data":{"isOperational":true,"helperInstalled":true,"helperWorking":true,"helperVersion":"1.2.3","keyPathAccessibility":true,"keyPathInputMonitoring":true,"kanataAccessibility":false,"kanataInputMonitoring":true,"kanataBinaryInstalled":true,"karabinerDriverInstalled":true,"vhidDeviceHealthy":true,"kanataRunning":true,"karabinerDaemonRunning":true,"vhidHealthy":true}}'

env KEYPATH_LAB_CLI="$tmp/bin/keypath-cli" \
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl" \
  KEYPATH_LAB_TCP_PROBE="$tmp/bin/tcp-probe" \
  KEYPATH_TEST_STATUS_JSON="$ready" KEYPATH_TEST_LAUNCHD_RUNNING=1 KEYPATH_TEST_TCP_READY=1 \
  "$repo/Scripts/lab/assert-runtime-state" ready

env KEYPATH_LAB_CLI="$tmp/bin/keypath-cli" \
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl" \
  KEYPATH_LAB_TCP_PROBE="$tmp/bin/tcp-probe" \
  KEYPATH_LAB_VERIFY_LANE="$tmp/bin/verify-lane" \
  KEYPATH_TEST_STATUS_JSON="$managed_ready" KEYPATH_TEST_LAUNCHD_RUNNING=1 KEYPATH_TEST_TCP_READY=1 \
  KEYPATH_TEST_MANAGED_POLICY_VALID=1 \
  "$repo/Scripts/lab/assert-runtime-state" ready \
    --managed-policy-manifest "$tmp/manifest.json"

if env KEYPATH_LAB_CLI="$tmp/bin/keypath-cli" \
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl" \
  KEYPATH_LAB_TCP_PROBE="$tmp/bin/tcp-probe" \
  KEYPATH_LAB_VERIFY_LANE="$tmp/bin/verify-lane" \
  KEYPATH_TEST_STATUS_JSON="$managed_ready" KEYPATH_TEST_LAUNCHD_RUNNING=1 KEYPATH_TEST_TCP_READY=1 \
  KEYPATH_TEST_MANAGED_POLICY_VALID=0 \
  "$repo/Scripts/lab/assert-runtime-state" ready \
    --managed-policy-manifest "$tmp/manifest.json" >/dev/null 2>&1; then
  print -u2 "invalid managed policy incorrectly substituted for Accessibility evidence"
  exit 1
fi

env KEYPATH_LAB_CLI="$tmp/bin/keypath-cli" \
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl" \
  KEYPATH_LAB_TCP_PROBE="$tmp/bin/tcp-probe" \
  KEYPATH_TEST_STATUS_JSON="$degraded" KEYPATH_TEST_LAUNCHD_RUNNING=0 KEYPATH_TEST_TCP_READY=0 \
  "$repo/Scripts/lab/assert-runtime-state" degraded

if env KEYPATH_LAB_CLI="$tmp/bin/keypath-cli" \
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl" \
  KEYPATH_LAB_TCP_PROBE="$tmp/bin/tcp-probe" \
  KEYPATH_TEST_STATUS_JSON="$ready" KEYPATH_TEST_LAUNCHD_RUNNING=1 KEYPATH_TEST_TCP_READY=1 \
  "$repo/Scripts/lab/assert-runtime-state" degraded >/dev/null 2>&1; then
  print -u2 "ready runtime incorrectly passed the degraded assertion"
  exit 1
fi

if env KEYPATH_LAB_CLI="$tmp/bin/keypath-cli" \
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl" \
  KEYPATH_LAB_TCP_PROBE="$tmp/bin/tcp-probe" \
  KEYPATH_TEST_STATUS_JSON="$degraded" KEYPATH_TEST_LAUNCHD_RUNNING=0 KEYPATH_TEST_TCP_READY=0 \
  "$repo/Scripts/lab/assert-runtime-state" ready >/dev/null 2>&1; then
  print -u2 "degraded runtime incorrectly passed the ready assertion"
  exit 1
fi

print "runtime-state tests passed"
