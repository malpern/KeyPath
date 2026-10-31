#!/bin/bash
# Prints docs_only=true when every file changed since <base> is docs or resources.
# Anything uncertain must not print true: an unreadable diff exits nonzero, and an
# empty one prints false. guides/ is not listed: tests read those files.
set -euo pipefail

base="${1:-}"
if [[ -z "$base" ]]; then
  echo "::error::classify-docs-only: no base commit" >&2
  exit 1
fi

# A plain assignment, so set -e sees git's exit status. --no-renames lists both
# sides of a move, so moving code into docs/ doesn't read as docs-only.
changed=$(git diff --no-renames --name-only "$base"...HEAD)

is_docs() {
  local path=$1
  case "$path" in
    docs/*|.github/workflows/claude.yml|.github/workflows/claude-code-review.yml) return 0 ;;
    */*) ;;
    *.md) return 0 ;;
  esac
  # Direct children only: a case pattern's * also matches /.
  [[ "$(dirname "$path")" == Sources/KeyPathAppKit/Resources ]] || return 1
  case "$path" in
    *.md|*.css|*.png) return 0 ;;
  esac
  return 1
}

docs_only=false
[[ -n "$changed" ]] && docs_only=true
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  is_docs "$path" || docs_only=false
done <<<"$changed"

echo "docs_only=$docs_only"
