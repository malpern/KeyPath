#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd -P)
MDM_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/keypath-managed-probe-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

write_tool() {
    local name=$1 body=$2
    printf '#!/bin/bash\n%s\n' "$body" > "$TMP/$name"
    chmod +x "$TMP/$name"
}

write_tool keypath-cli 'cat <<JSON
{"isOperational":true,"helperInstalled":true,"helperWorking":true,"helperVersion":"1.2.3","keyPathAccessibility":true,"keyPathInputMonitoring":true,"kanataAccessibility":true,"kanataInputMonitoring":true,"kanataBinaryInstalled":true,"karabinerDriverInstalled":true,"vhidDeviceHealthy":true,"kanataRunning":true,"karabinerDaemonRunning":true,"vhidHealthy":true}
JSON'
write_tool tcp-probe 'echo "{\"CurrentLayerName\":{\"name\":\"base\"}}"'
write_tool systemextensionsctl 'echo "activated enabled team org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"'
write_tool sfltool 'echo "background items available"'
write_tool launchctl 'echo "state = running"'

run_probe() {
    KEYPATH_LAB_CLI="$TMP/keypath-cli" \
    KEYPATH_LAB_TCP_PROBE="$TMP/tcp-probe" \
    KEYPATH_LAB_SYSTEMEXTENSIONSCTL="$TMP/systemextensionsctl" \
    KEYPATH_LAB_SFLTOOL="$TMP/sfltool" \
    KEYPATH_LAB_LAUNCHCTL="$TMP/launchctl" \
        "$MDM_DIR/probe-managed-capabilities" --output "$1"
}

run_probe "$TMP/pass" >/dev/null
grep -Fq $'managed_capabilities\tpassed' "$TMP/pass/result.tsv"
test -s "$TMP/pass/service-status.json"
test -s "$TMP/pass/system-extensions.txt"
test -s "$TMP/pass/kanata-launchd.txt"
test -s "$TMP/pass/tcp-readiness.json"

write_tool keypath-cli 'cat <<JSON
{"isOperational":true,"helperInstalled":true,"helperWorking":true,"helperVersion":"1.2.3","keyPathAccessibility":true,"keyPathInputMonitoring":true,"kanataAccessibility":false,"kanataInputMonitoring":true,"kanataBinaryInstalled":true,"karabinerDriverInstalled":true,"vhidDeviceHealthy":true,"kanataRunning":true,"karabinerDaemonRunning":true,"vhidHealthy":true}
JSON'
if run_probe "$TMP/missing-permission" >"$TMP/missing.stdout" 2>"$TMP/missing.stderr"; then
    echo "expected missing Kanata Accessibility to fail" >&2
    exit 1
fi
grep -Fq 'managed capabilities missing: kanataAccessibility' "$TMP/missing.stderr"

write_tool keypath-cli 'cat <<JSON
{"isOperational":true,"helperInstalled":true,"helperWorking":true,"helperVersion":"1.2.3","keyPathAccessibility":true,"keyPathInputMonitoring":true,"kanataAccessibility":true,"kanataInputMonitoring":true,"kanataBinaryInstalled":true,"karabinerDriverInstalled":true,"vhidDeviceHealthy":true,"kanataRunning":true,"karabinerDaemonRunning":true,"vhidHealthy":true}
JSON'
write_tool systemextensionsctl 'echo "no matching extension"'
if run_probe "$TMP/missing-extension" >"$TMP/extension.stdout" 2>"$TMP/extension.stderr"; then
    echo "expected missing VirtualHID extension to fail" >&2
    exit 1
fi
grep -Fq 'VirtualHID system extension is absent' "$TMP/extension.stderr"

write_tool systemextensionsctl 'echo "activated enabled team org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"'
write_tool launchctl 'echo "state = exited"'
if run_probe "$TMP/stopped-runtime" >"$TMP/stopped.stdout" 2>"$TMP/stopped.stderr"; then
    echo "expected stopped Kanata launchd job to fail" >&2
    exit 1
fi
grep -Fq 'Kanata launchd job is not running' "$TMP/stopped.stderr"

echo "managed-capability-probe-tests: passed"
