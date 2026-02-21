#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHPAGES="$REPO_ROOT/.worktrees/gh-pages"
CSS_FILE="$GHPAGES/assets/css/main.css"
APP_HELP_CSS="$REPO_ROOT/Sources/KeyPathAppKit/Resources/help-theme.css"

if [[ ! -d "$GHPAGES" ]]; then
  echo "ERROR: gh-pages worktree not found at $GHPAGES"
  exit 1
fi

if [[ ! -f "$CSS_FILE" ]]; then
  echo "ERROR: missing CSS file: $CSS_FILE"
  exit 1
fi
if [[ ! -f "$APP_HELP_CSS" ]]; then
  echo "ERROR: missing app help CSS file: $APP_HELP_CSS"
  exit 1
fi

extract_block() {
  local selector="$1"
  awk -v sel="$selector" '
    $0 ~ "^" sel "[[:space:]]*\\{" { in_block=1 }
    in_block { print }
    in_block && $0 ~ "^[[:space:]]*\\}[[:space:]]*$" { exit }
  ' "$CSS_FILE"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if ! grep -q "$needle" <<<"$haystack"; then
    echo "ERROR: $msg"
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if grep -q "$needle" <<<"$haystack"; then
    echo "ERROR: $msg"
    exit 1
  fi
}

echo "Checking header image CSS regression guards..."
header_wrap_block="$(extract_block "\\.article-header-image")"
header_img_block="$(extract_block "\\.article-header-img")"

if [[ -z "$header_wrap_block" || -z "$header_img_block" ]]; then
  echo "ERROR: missing article header CSS blocks"
  exit 1
fi

assert_contains "$header_wrap_block" "width:[[:space:]]*100%;" \
  ".article-header-image must remain content-width (width: 100%)"
assert_not_contains "$header_wrap_block" "width:[[:space:]]*100vw" \
  ".article-header-image must not use viewport full-bleed width"
assert_not_contains "$header_wrap_block" "transform:[[:space:]]*translateX" \
  ".article-header-image must not use centering transform hacks"

assert_contains "$header_wrap_block" "overflow:[[:space:]]*hidden;" \
  ".article-header-image must clip oversized art to avoid blank-canvas viewport"
assert_contains "$header_img_block" "height:[[:space:]]*clamp" \
  ".article-header-img must have bounded responsive height"
assert_contains "$header_img_block" "object-fit:[[:space:]]*cover;" \
  ".article-header-img must fill header box (object-fit: cover)"
assert_contains "$header_img_block" "object-position:[[:space:]]*center 72%;" \
  ".article-header-img must keep lower focal point visible (center 72%)"

echo "Checking screenshot sizing CSS guards..."
assert_contains "$(cat "$CSS_FILE")" "\\.parchment-theme \\.content img" \
  "website CSS must include base content image sizing rules"
assert_contains "$(cat "$CSS_FILE")" "\\.parchment-theme \\.content p > img\\[alt\\^=\"Screenshot\"\\]" \
  "website CSS must include screenshot-specific sizing rules"
assert_contains "$(cat "$CSS_FILE")" "max-width:[[:space:]]*100%;" \
  "website screenshot rules must keep images within content width"
assert_contains "$(cat "$APP_HELP_CSS")" "\\.help-img\\[alt\\^=\"Screenshot\"\\]" \
  "app help CSS must include screenshot-specific sizing rules"
assert_contains "$(cat "$APP_HELP_CSS")" "max-width:[[:space:]]*100%;" \
  "app help images must keep max-width: 100%"

echo "Checking screenshot insertion parity..."
src_count="$(rg -n '^<!-- screenshot:' "$REPO_ROOT"/Sources/KeyPathAppKit/Resources/*.md | wc -l | tr -d ' ')"
web_count="$(rg -n -F "![Screenshot]({{ '/images/help/" \
  "$GHPAGES"/getting-started/*.md \
  "$GHPAGES"/guides/*.md \
  "$GHPAGES"/migration/*.md | wc -l | tr -d ' ')"

if [[ "$src_count" != "$web_count" ]]; then
  echo "ERROR: screenshot embed count mismatch (source=$src_count, web=$web_count)"
  exit 1
fi

echo "Checking divider asset geometry regression guards..."
src_divider="$REPO_ROOT/Sources/KeyPathAppKit/Resources/decor-divider.png"
web_divider="$GHPAGES/images/help/decor-divider.png"

for f in "$src_divider" "$web_divider"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing divider asset: $f"
    exit 1
  fi
done

read_png_dims() {
  local png="$1"
  python3 - "$png" <<'PY'
import struct, sys
p = sys.argv[1]
with open(p, "rb") as f:
    sig = f.read(8)
    if sig != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("NOT_PNG")
    length = struct.unpack(">I", f.read(4))[0]
    chunk = f.read(4)
    if chunk != b"IHDR" or length != 13:
        raise SystemExit("BAD_IHDR")
    data = f.read(13)
    width, height = struct.unpack(">II", data[:8])
print(f"{width} {height}")
PY
}

read -r src_w src_h < <(read_png_dims "$src_divider")
read -r web_w web_h < <(read_png_dims "$web_divider")

if [[ "$src_w" -ne "$web_w" || "$src_h" -ne "$web_h" ]]; then
  echo "ERROR: source/web divider dimensions differ ($src_w x $src_h vs $web_w x $web_h)"
  exit 1
fi

# Guard against reintroducing the old giant canvas (1584x672) with whitespace.
if [[ "$src_h" -gt 260 || "$src_w" -gt 1400 ]]; then
  echo "ERROR: divider image canvas too large ($src_w x $src_h) — whitespace regression likely"
  exit 1
fi

echo "Publish regression checks passed."
