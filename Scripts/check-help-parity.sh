#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$REPO_ROOT/Sources/KeyPathAppKit/Resources"
PUBLISH_SCRIPT="$REPO_ROOT/Scripts/publish-help-to-web.sh"

if [[ ! -d "$RES_DIR" ]]; then
  echo "ERROR: missing resources dir: $RES_DIR"
  exit 1
fi

if [[ ! -f "$PUBLISH_SCRIPT" ]]; then
  echo "ERROR: missing publish script: $PUBLISH_SCRIPT"
  exit 1
fi

app_ids="$(find "$RES_DIR" -maxdepth 1 -type f -name '*.md' -print \
  | sed 's#^.*/##; s#\.md$##' \
  | sort -u)"

registry_ids="$(awk '
  /^REGISTRY=\(/ { in_registry=1; next }
  in_registry && /^\)/ { in_registry=0; next }
  in_registry && /^[[:space:]]*"/ {
    line=$0
    sub(/^[[:space:]]*"/, "", line)
    split(line, parts, /\|/)
    print parts[1]
  }
' "$PUBLISH_SCRIPT" | sort -u)"

echo "Checking app help IDs vs publish REGISTRY..."
if ! diff -u <(echo "$app_ids") <(echo "$registry_ids") >/dev/null; then
  echo "ERROR: app help article set and publish registry are out of sync."
  diff -u <(echo "$app_ids") <(echo "$registry_ids") || true
  exit 1
fi

echo "Checking markdown PNG references resolve in app resources..."
if command -v rg >/dev/null 2>&1; then
  png_refs="$(rg -n --no-filename --no-line-number '!\[[^]]*\]\(([^)]+\.png)\)' "$RES_DIR"/*.md -or '$1' | sort -u || true)"
else
  # Fallback for environments where ripgrep is unavailable (e.g., fresh CI images).
  png_refs="$(
    grep -hEo '!\[[^]]*\]\(([^)]+\.png)\)' "$RES_DIR"/*.md \
      | sed -E 's#.*\(([^)]+\.png)\)#\1#' \
      | sort -u || true
  )"
fi
missing_png=0
while IFS= read -r png; do
  [[ -z "$png" ]] && continue
  if [[ ! -f "$RES_DIR/$png" ]]; then
    echo "ERROR: missing PNG referenced by markdown: $png"
    missing_png=1
  fi
done <<< "$png_refs"
if [[ "$missing_png" -ne 0 ]]; then
  exit 1
fi

echo "Help parity checks passed."
