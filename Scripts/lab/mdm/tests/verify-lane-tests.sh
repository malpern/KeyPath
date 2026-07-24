#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../../.." >/dev/null && pwd -P)
VERIFY="$ROOT/Scripts/lab/mdm/verify-lane"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/keypath-verify-lane-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/policy"

cat > "$TMP/bin/id" <<'SH'
#!/bin/bash
printf '%s\n' "${FAKE_UID:-501}"
SH

cat > "$TMP/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$CALLS"
[[ ${FAKE_SUDO_FAIL:-0} == 0 ]] || exit 1
[[ ${1:-} == -n ]] && shift
FAKE_ROOT=1 exec "$@"
SH

cat > "$TMP/bin/profiles" <<'SH'
#!/bin/bash
if [[ $1 == show ]]; then
    [[ ${FAKE_ROOT:-0} == 1 || ${FAKE_UID:-501} == 0 ]] || {
        echo "There are no configuration profiles installed for user 'admin'"
        exit 0
    }
    cat <<'OUT'
profileIdentifier: com.keypath.lab.pppc
profileIdentifier: com.keypath.lab.system-extension
profileIdentifier: com.keypath.lab.service-management
OUT
elif [[ $1 == status ]]; then
    echo "MDM enrollment: Yes (User Approved)"
else
    exit 2
fi
SH

cat > "$TMP/bin/sw_vers" <<'SH'
#!/bin/bash
echo 15.7.7
SH

chmod +x "$TMP/bin/"*

for profile in keypath-pppc.mobileconfig keypath-system-extension.mobileconfig keypath-service-management.mobileconfig; do
    printf '%s\n' "$profile" > "$TMP/policy/$profile"
done

python3 - "$TMP/policy" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
profiles = {}
for identifier, filename in {
    "com.keypath.lab.pppc": "keypath-pppc.mobileconfig",
    "com.keypath.lab.system-extension": "keypath-system-extension.mobileconfig",
    "com.keypath.lab.service-management": "keypath-service-management.mobileconfig",
}.items():
    profiles[identifier] = {
        "filename": filename,
        "sha256": hashlib.sha256((root / filename).read_bytes()).hexdigest(),
    }
(root / "manifest.json").write_text(json.dumps({
    "lane": "managed-functional",
    "profiles": profiles,
    "supportedMacOSMajorVersions": [15, 26],
}))
PY

export CALLS="$TMP/calls.log"
touch "$CALLS"

output=$(PROFILES_BIN="$TMP/bin/profiles" ID_BIN="$TMP/bin/id" \
    SUDO_BIN="$TMP/bin/sudo" SW_VERS_BIN="$TMP/bin/sw_vers" \
    "$VERIFY" managed-functional --manifest "$TMP/policy/manifest.json")
grep -Fq $'profile_count\t3' <<<"$output"
grep -Fq "sudo -n $TMP/bin/profiles show -type=configuration" "$CALLS"

set +e
failure=$(FAKE_SUDO_FAIL=1 PROFILES_BIN="$TMP/bin/profiles" ID_BIN="$TMP/bin/id" \
    SUDO_BIN="$TMP/bin/sudo" SW_VERS_BIN="$TMP/bin/sw_vers" \
    "$VERIFY" managed-functional --manifest "$TMP/policy/manifest.json" 2>&1)
failure_status=$?
set -e
[[ $failure_status -ne 0 ]]
grep -Fq 'system profile inventory requires root or non-interactive sudo' <<<"$failure"

rm -f "$CALLS"
FAKE_UID=0 PROFILES_BIN="$TMP/bin/profiles" ID_BIN="$TMP/bin/id" \
    SUDO_BIN="$TMP/bin/sudo" SW_VERS_BIN="$TMP/bin/sw_vers" \
    "$VERIFY" managed-functional --manifest "$TMP/policy/manifest.json" >/dev/null
[[ ! -e $CALLS ]]

echo "verify-lane tests: passed"
