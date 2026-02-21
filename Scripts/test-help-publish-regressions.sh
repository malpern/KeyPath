#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHPAGES="$REPO_ROOT/.worktrees/gh-pages"
CSS_FILE="$GHPAGES/assets/css/main.css"

if [[ ! -d "$GHPAGES" ]]; then
  echo "ERROR: gh-pages worktree not found at $GHPAGES"
  exit 1
fi

if [[ ! -f "$CSS_FILE" ]]; then
  echo "ERROR: missing CSS file: $CSS_FILE"
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

assert_contains "$header_img_block" "object-fit:[[:space:]]*contain;" \
  ".article-header-img must render full image (object-fit: contain)"
assert_contains "$header_img_block" "object-position:[[:space:]]*center top;" \
  ".article-header-img must anchor to top (object-position: center top)"
assert_not_contains "$header_img_block" "object-fit:[[:space:]]*cover;" \
  ".article-header-img must not crop artwork with object-fit: cover"

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

echo "Publish regression checks passed."
