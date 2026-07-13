#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd -P)
LAB_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/peekaboo-ui-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

FAKE="$TMP/peekaboo"
cat > "$FAKE" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$PEEKABOO_CALLS"
if [[ ${1:-} == --version ]]; then
  echo "${PEEKABOO_TEST_VERSION:-Peekaboo 3.9.0}"
else
  printf '{"success":true}\n'
fi
EOF
chmod +x "$FAKE"
export PEEKABOO_BIN="$FAKE"
export PEEKABOO_CALLS="$TMP/calls"

"$LAB_DIR/peekaboo-ui" preflight > "$TMP/preflight.json"
grep -q 'permissions status --json' "$PEEKABOO_CALLS"

for unsupported in 'Peekaboo 2.3.0' 'Peekaboo 13.0.0'; do
  if PEEKABOO_TEST_VERSION="$unsupported" "$LAB_DIR/peekaboo-ui" preflight >/dev/null 2>&1; then
    echo "expected unsupported version to fail: $unsupported" >&2
    exit 1
  fi
done

"$LAB_DIR/peekaboo-ui" snapshot --app 'System Settings' --output "$TMP/out/snapshot.json"
grep -q 'see --app System Settings --json' "$PEEKABOO_CALLS"
grep -q '"success":true' "$TMP/out/snapshot.json"

"$LAB_DIR/peekaboo-ui" click --app KeyPath --query 'Get Started' --foreground --output "$TMP/out/click.json"
grep -q 'click Get Started --app KeyPath --json --foreground' "$PEEKABOO_CALLS"

"$LAB_DIR/peekaboo-ui" dialogs --app 'System Settings' --output "$TMP/out/dialogs.json"
grep -q 'dialog list --app System Settings --json' "$PEEKABOO_CALLS"

"$LAB_DIR/peekaboo-ui" file --app 'System Settings' --path /Applications/KeyPath.app --select Open --output "$TMP/out/file.json"
grep -q 'dialog file --app System Settings --path /Applications --name KeyPath.app --select Open --json' "$PEEKABOO_CALLS"

"$LAB_DIR/peekaboo-ui" screenshot --app KeyPath --retina --output "$TMP/out/keypath.png"
grep -q 'image --app KeyPath --mode window --path .*keypath.png --json --retina' "$PEEKABOO_CALLS"
grep -q '"success":true' "$TMP/out/keypath.png.json"

if "$LAB_DIR/peekaboo-ui" file --app KeyPath --path relative --output "$TMP/out/bad.json" >/dev/null 2>&1; then
  echo 'expected relative file path to fail' >&2
  exit 1
fi

if "$LAB_DIR/peekaboo-ui" click --app KeyPath --output "$TMP/out/bad.json" >/dev/null 2>&1; then
  echo 'expected missing query to fail' >&2
  exit 1
fi

DRAG_PEEKABOO="$TMP/drag-peekaboo"
cat > "$DRAG_PEEKABOO" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$PEEKABOO_CALLS"
if [[ ${1:-} == see && "$*" == *"--app Finder"* ]]; then
  printf '{"data":{"ui_elements":[{"label":"kanata-launcher","is_actionable":true,"bounds":{"x":10,"y":20,"width":40,"height":60}}]}}\n'
elif [[ ${1:-} == see ]]; then
  printf '{"data":{"ui_elements":[{"identifier":"KeyPath_Title","bounds":{"x":600,"y":100,"width":100,"height":20}}]}}\n'
else
  printf '{"success":true}\n'
fi
EOF
chmod +x "$DRAG_PEEKABOO"

FAKE_OPEN="$TMP/open"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$OPEN_CALLS"\n' > "$FAKE_OPEN"
chmod +x "$FAKE_OPEN"
export OPEN_CALLS="$TMP/open-calls"

FAKE_OSASCRIPT="$TMP/osascript"
cat > "$FAKE_OSASCRIPT" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$OSASCRIPT_CALLS"
if [[ "$*" == *'return w.position().concat(w.size()).join'* ]]; then
  [[ "${*: -1}" == Finder ]] && echo '80,90,640,480' || echo '700,100,800,600'
  exit 0
fi
[[ "$*" == *'AXSecureTextField'* ]] && echo secure
exit 0
EOF
chmod +x "$FAKE_OSASCRIPT"
export OSASCRIPT_CALLS="$TMP/osascript-calls"

touch "$TMP/kanata-launcher"
KEYPATH_PERMISSION_DRAG_REVEAL_SECONDS=0 KEYPATH_PERMISSION_DRAG_SETTLE_SECONDS=0 \
  PEEKABOO_BIN="$DRAG_PEEKABOO" OPEN_BIN="$FAKE_OPEN" OSASCRIPT_BIN="$FAKE_OSASCRIPT" \
  "$LAB_DIR/permission-drag" --path "$TMP/kanata-launcher" --target-identifier KeyPath_Title --output "$TMP/out/drag.json" > "$TMP/drag-result"
grep -q $'permission_drag\tauthorization-required' "$TMP/drag-result"
grep -q -- '-R .*kanata-launcher' "$OPEN_CALLS"
grep -q 'drag --from-coords 30,50 --to-coords 650,110 --duration 1500 --steps 30 --profile linear --json' "$PEEKABOO_CALLS"
grep -q 'Finder 80,90,640,480' "$OSASCRIPT_CALLS"
grep -q 'System Settings 700,100,800,600' "$OSASCRIPT_CALLS"

echo 'peekaboo-ui shell tests passed'
