#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)

APPLY=0
INCLUDE_CURRENT=0
INCLUDE_TMP=0

usage() {
    cat <<'EOF'
Usage: Scripts/cleanup-local-build-artifacts.sh [--apply] [--include-current] [--include-tmp-keypath]

Find generated build artifacts in local KeyPath worktrees. The default mode is
read-only and prints what would be removed.

Options:
  --apply                Remove the generated artifact directories.
  --include-current      Include the current worktree. Default: skip it.
  --include-tmp-keypath  Also scan /tmp/keypath-* directories.
  -h, --help            Show this help.

Targets removed with --apply:
  .build
  .swiftpm
  build
  dist
  test-results
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)
            APPLY=1
            ;;
        --include-current)
            INCLUDE_CURRENT=1
            ;;
        --include-tmp-keypath)
            INCLUDE_TMP=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd "$PROJECT_DIR"

current_path=$(pwd -P)
candidates_file=$(mktemp)
trap 'rm -f "$candidates_file"' EXIT

git worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }' > "$candidates_file"

if [ "$INCLUDE_TMP" -eq 1 ]; then
    find /tmp -maxdepth 1 -type d -name 'keypath-*' -print 2>/dev/null >> "$candidates_file" || true
fi

echo "KeyPath local build artifact cleanup"
if [ "$APPLY" -eq 1 ]; then
    echo "Mode: apply"
else
    echo "Mode: dry-run"
fi
echo

found=0
while IFS= read -r worktree; do
    [ -n "$worktree" ] || continue
    [ -d "$worktree" ] || continue

    worktree_path=$(cd "$worktree" >/dev/null 2>&1 && pwd -P) || continue
    if [ "$INCLUDE_CURRENT" -eq 0 ] && [ "$worktree_path" = "$current_path" ]; then
        continue
    fi

    if ! git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        continue
    fi

    for relative_path in .build .swiftpm build dist test-results; do
        target="$worktree_path/$relative_path"
        [ -d "$target" ] || continue

        found=1
        size=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
        echo "$target (${size:-unknown})"
        if [ "$APPLY" -eq 1 ]; then
            rm -rf "$target"
            echo "  removed"
        else
            echo "  would remove"
        fi
    done
done < "$candidates_file"

if [ "$found" -eq 0 ]; then
    echo "No generated artifact directories found."
fi

if [ "$APPLY" -eq 0 ]; then
    echo
    echo "Run with --apply to remove the listed directories."
fi
