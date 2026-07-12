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

echo 'peekaboo-ui shell tests passed'
