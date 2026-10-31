#!/bin/bash
# Prints docs_only=true when every file changed since <base> is docs or resources.
# Skipping the required checks counts as passing them, so anything uncertain must
# not print true: an unreadable diff exits nonzero, and an empty one prints false.
set -euo pipefail

base="${1:-}"
if [[ -z "$base" ]]; then
  echo "::error::classify-docs-only: no base commit" >&2
  exit 1
fi

# A plain assignment, so set -e sees git's exit status.
changed=$(git diff --name-only "$base"...HEAD)

docs_only=false
[[ -n "$changed" ]] && docs_only=true
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  case "$path" in
    docs/*|*.md|.github/workflows/claude.yml|.github/workflows/claude-code-review.yml|Sources/KeyPathAppKit/Resources/*.md|Sources/KeyPathAppKit/Resources/*.css|Sources/KeyPathAppKit/Resources/*.png)
      ;;
    *)
      docs_only=false
      ;;
  esac
done <<<"$changed"

echo "docs_only=$docs_only"
