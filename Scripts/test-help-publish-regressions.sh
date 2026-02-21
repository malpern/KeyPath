#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHPAGES="$REPO_ROOT/.worktrees/gh-pages"
CSS_FILE="$GHPAGES/assets/css/main.css"
APP_HELP_CSS="$REPO_ROOT/Sources/KeyPathAppKit/Resources/help-theme.css"
LAYOUT_FILE="$GHPAGES/_layouts/default.html"

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
if [[ ! -f "$LAYOUT_FILE" ]]; then
  echo "ERROR: missing layout file: $LAYOUT_FILE"
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
header_img_block="$(extract_block "\\.parchment-theme \\.content \\.article-header-image \\.article-header-img")"
if [[ -z "$header_img_block" ]]; then
  # Backward-compatible fallback selector, if the specific override is renamed.
  header_img_block="$(extract_block "\\.article-header-img")"
fi

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
assert_contains "$header_img_block" "max-width:[[:space:]]*none;" \
  ".article-header-img must override generic max-width rules to avoid side whitespace"

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
assert_contains "$(cat "$APP_HELP_CSS")" "\\.help-header-img" \
  "app help CSS must include dedicated header image crop rules"
assert_contains "$(cat "$APP_HELP_CSS")" "object-fit:[[:space:]]*cover;" \
  "app header images must use object-fit: cover"

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

echo "Checking Google Fonts non-blocking load guards..."
layout_html="$(cat "$LAYOUT_FILE")"
assert_contains "$layout_html" 'fonts.googleapis.com' \
  "layout must keep Google Fonts reference"
assert_contains "$layout_html" 'rel="preload"[[:space:]][[:space:]]*as="style"' \
  "Google Fonts should include preload style hint"
assert_contains "$layout_html" 'media="print"[[:space:]][[:space:]]*onload="this.media='\''all'\''"' \
  "Google Fonts stylesheet must be non-blocking (print/onload swap)"
assert_contains "$layout_html" '<noscript><link rel="stylesheet"' \
  "Google Fonts fallback should exist for no-JS clients"

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

echo "Checking header image side-whitespace regression guards..."
python3 - "$REPO_ROOT" "$GHPAGES" <<'PY'
from pathlib import Path
import sys
import numpy as np
from PIL import Image

repo = Path(sys.argv[1])
gh = Path(sys.argv[2])

def side_margin_ratio(p: Path) -> tuple[float, int, int, int]:
    arr = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
    lum = arr.mean(axis=2)
    # "Ink" columns: at least 8% of pixels are below near-white luminance.
    frac = (lum < 245).mean(axis=0)
    idx = np.where(frac > 0.08)[0]
    if len(idx) == 0:
        return 1.0, arr.shape[1], arr.shape[1], arr.shape[1]
    left = int(idx[0])
    right = int(arr.shape[1] - 1 - idx[-1])
    margin = max(left, right)
    return margin / arr.shape[1], left, right, arr.shape[1]

targets = [
    repo / "Sources/KeyPathAppKit/Resources/header-installation.png",
    repo / "Sources/KeyPathAppKit/Resources/header-home-row-mods.png",
    gh / "images/help/header-installation.png",
    gh / "images/help/header-home-row-mods.png",
]

errors = []
for p in targets:
    if not p.exists():
        errors.append(f"missing header asset: {p}")
        continue
    ratio, left, right, width = side_margin_ratio(p)
    if ratio > 0.08:
        errors.append(
            f"excess side whitespace in {p.name} (left={left}px right={right}px width={width}px)"
        )

if errors:
    for e in errors:
        print(f"ERROR: {e}")
    raise SystemExit(1)
PY

echo "Checking generated screenshot source resolution guards..."
python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
import re
import sys
from PIL import Image

repo = Path(sys.argv[1])
res = repo / "Sources/KeyPathAppKit/Resources"

# Snapshot-generated documentation captures should be high-resolution enough
# for retina displays. (Manual system screenshots use separate capture scripts
# and are excluded from this threshold.)
min_width = 900
exclude = (
    r"^screenshot-",
    r"^permissions-",
    r"^install-overlay-health-green\.png$",
    r"^overlay-header-unhealthy\.png$",
    r"^action-uri-overlay-header\.png$",
)

issues = []
for p in sorted(res.glob("*.png")):
    n = p.name
    if n.startswith(("header-", "decor-")):
        continue
    if any(re.search(pattern, n) for pattern in exclude):
        continue
    with Image.open(p) as im:
        w, h = im.size
    # Only enforce on likely UI screenshots (not tiny icons/assets).
    if n.startswith((
        "action-uri-", "concepts-", "hrm-", "install-", "karabiner-",
        "kb-layouts-", "launchers-", "tap-hold-", "use-cases-", "window-mgmt-"
    )):
        if w < min_width:
            issues.append(f"{n} is too small ({w}x{h}), expected width >= {min_width}")

if issues:
    for issue in issues:
        print(f"ERROR: {issue}")
    raise SystemExit(1)
PY

echo "Publish regression checks passed."
