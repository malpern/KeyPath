#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd -P)
MDM_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/keypath-mdm-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

app="$TMP/KeyPath.app"
mkdir -p "$app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS"
touch "$app/Contents/Library/KeyPath/kanata-launcher"
touch "$app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata"

cat > "$TMP/codesign" <<'EOF'
#!/bin/bash
target=${@: -1}
if [[ $1 == -dv ]]; then
    if [[ $target == *"Kanata Engine.app" ]]; then
        echo 'Identifier=com.keypath.kanata-engine' >&2
    else
        echo 'Identifier=com.keypath.KeyPath' >&2
    fi
    echo 'TeamIdentifier=X2RKZ5TG99' >&2
else
    if [[ $target == *kanata-launcher ]]; then id=kanata-launcher; elif [[ $target == *"Kanata Engine.app" ]]; then id=com.keypath.kanata-engine; else id=com.keypath.KeyPath; fi
    echo "designated => identifier \"$id\" and anchor apple generic and certificate leaf[subject.OU] = X2RKZ5TG99" >&2
fi
EOF
chmod +x "$TMP/codesign"
cat > "$TMP/sw_vers" <<'EOF'
#!/bin/bash
[[ $1 == -productVersion ]] && echo 26.5.2
EOF
chmod +x "$TMP/sw_vers"

CODESIGN_BIN="$TMP/codesign" "$MDM_DIR/generate-keypath-profiles" --app "$app" --output "$TMP/one" >/dev/null
CODESIGN_BIN="$TMP/codesign" "$MDM_DIR/generate-keypath-profiles" --app "$app" --output "$TMP/two" >/dev/null

diff -ru "$TMP/one" "$TMP/two"
for profile in "$TMP/one"/*.mobileconfig; do /usr/bin/plutil -lint "$profile" >/dev/null; done

/usr/bin/python3 - "$TMP/one" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["supportedMacOSMajorVersions"] == [15, 26]
assert len(manifest["profiles"]) == 3

pppc = plistlib.load(open(root / "keypath-pppc.mobileconfig", "rb"))
services = pppc["PayloadContent"][0]["Services"]
assert {"Accessibility", "ListenEvent", "SystemPolicyAllFiles"} == set(services)
assert [item["IdentifierType"] for item in services["Accessibility"]] == ["bundleID", "path", "bundleID"]

system_extension = plistlib.load(open(root / "keypath-system-extension.mobileconfig", "rb"))
payload = system_extension["PayloadContent"][0]
assert payload["AllowedSystemExtensions"]["G43BCU2T37"] == ["org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"]

service_management = plistlib.load(open(root / "keypath-service-management.mobileconfig", "rb"))
assert service_management["PayloadContent"][0]["Rules"][0]["TeamIdentifier"] == "X2RKZ5TG99"
PY

CODESIGN_BIN="$TMP/codesign" SW_VERS_BIN="$TMP/sw_vers" \
    "$MDM_DIR/verify-artifact-policy" --app "$app" --manifest "$TMP/one/manifest.json" >/dev/null

echo "profile-generator-tests: passed"
