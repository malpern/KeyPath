#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd -P)
MDM_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/keypath-publish-managed-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

base="$TMP/mdm"
profiles="$TMP/profiles"
evidence="$TMP/evidence"
bin="$TMP/bin"
enrollment_id=1DC7C8BB-5FCB-5ADC-8C8F-82A95ACAB35B
uuids=(
    11111111-1111-4111-8111-111111111111
    22222222-2222-4222-8222-222222222222
    33333333-3333-4333-8333-333333333333
    44444444-4444-4444-8444-444444444444
)

mkdir -p \
    "$base/state/nanomdm/dbkv/enrollments/1D/C7" \
    "$base/state/nanomdm/dbkv/queue/1D/C7" \
    "$base/secrets" \
    "$profiles" \
    "$bin"
printf 'Device' > "$base/state/nanomdm/dbkv/enrollments/1D/C7/$enrollment_id.type"
printf 'machine nanomdm login test password test\n' > "$base/secrets/nanomdm.netrc"
for profile in keypath-pppc.mobileconfig keypath-system-extension.mobileconfig keypath-service-management.mobileconfig; do
    printf '<plist version="1.0"><dict/></plist>\n' > "$profiles/$profile"
done
printf '{"lane":"managed-functional"}\n' > "$profiles/manifest.json"

cat > "$bin/cmdr" <<'EOF'
#!/bin/bash
printf '<plist version="1.0"><dict><key>CommandUUID</key><string>%s</string></dict></plist>\n' "$2"
EOF
cat > "$bin/curl" <<'EOF'
#!/bin/bash
printf '{}\n'
EOF
cat > "$bin/uuidgen" <<EOF
#!/bin/bash
counter="$TMP/uuid-counter"
index=0
[[ ! -f "\$counter" ]] || index=\$(cat "\$counter")
case \$index in
  0) uuid=${uuids[0]} ;;
  1) uuid=${uuids[1]} ;;
  2) uuid=${uuids[2]} ;;
  3) uuid=${uuids[3]} ;;
  *) exit 9 ;;
esac
echo \$((index + 1)) > "\$counter"
printf '%s\n' "\$uuid"
EOF
chmod +x "$bin/cmdr" "$bin/curl" "$bin/uuidgen"

/usr/bin/python3 - "$base" "$enrollment_id" "${uuids[@]}" <<'PY'
import plistlib
import sys
from pathlib import Path

base = Path(sys.argv[1])
enrollment = sys.argv[2]
uuids = sys.argv[3:]
queue = base / "state/nanomdm/dbkv/queue/1D/C7"
for uuid in uuids[:3]:
    report = {
        "CommandUUID": uuid,
        "Status": "Acknowledged",
        "UDID": enrollment,
    }
    with (queue / f"{enrollment}.{uuid}.queueitem.report").open("wb") as handle:
        plistlib.dump(report, handle)
profile_list = {
    "CommandUUID": uuids[3],
    "Status": "Acknowledged",
    "UDID": enrollment,
    "ProfileList": [
        {"PayloadIdentifier": "com.keypath.lab.pppc"},
        {"PayloadIdentifier": "com.keypath.lab.system-extension"},
        {"PayloadIdentifier": "com.keypath.lab.service-management"},
    ],
}
with (queue / f"{enrollment}.{uuids[3]}.queueitem.report").open("wb") as handle:
    plistlib.dump(profile_list, handle)
PY

result=$(
    KEYPATH_LAB_MDM_HOME="$base" \
    KEYPATH_LAB_MDM_CMDR="$bin/cmdr" \
    KEYPATH_LAB_MDM_CURL="$bin/curl" \
    KEYPATH_LAB_MDM_UUIDGEN="$bin/uuidgen" \
    KEYPATH_LAB_MDM_SLEEP=/usr/bin/true \
    "$MDM_DIR/publish-managed-profiles" \
        --profile-dir "$profiles" \
        --evidence-dir "$evidence"
)
[[ $result == *$'profile_count\t3'* ]]
[[ $result == *$'verification\tpassed'* ]]
[[ -f $evidence/responses/profile-list-report.plist ]]
[[ -f $evidence/manifest.json ]]

mkdir -p "$base/state/nanomdm/dbkv/enrollments/AA/BB"
printf 'Device' > "$base/state/nanomdm/dbkv/enrollments/AA/BB/AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE.type"
if KEYPATH_LAB_MDM_HOME="$base" \
    KEYPATH_LAB_MDM_CMDR="$bin/cmdr" \
    KEYPATH_LAB_MDM_CURL="$bin/curl" \
    KEYPATH_LAB_MDM_UUIDGEN="$bin/uuidgen" \
    "$MDM_DIR/publish-managed-profiles" \
        --profile-dir "$profiles" \
        --evidence-dir "$TMP/ambiguous" >/dev/null 2>"$TMP/ambiguous.stderr"; then
    echo "expected ambiguous enrollment discovery to fail" >&2
    exit 1
fi
grep -Fq 'expected exactly one NanoMDM enrollment, found 2' "$TMP/ambiguous.stderr"

echo "publish-managed-profiles-tests: passed"
