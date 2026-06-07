#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
source "$SCRIPT_DIR/lib/test-lanes.sh"

usage() {
    cat <<'EOF'
Usage: Scripts/test-fast.sh [area|--changed|--full|--list]

Run the smallest useful KeyPath test scope through run-tests-safe.sh.

Examples:
  ./Scripts/test-fast.sh rules
  ./Scripts/test-fast.sh config
  ./Scripts/test-fast.sh --changed
  ./Scripts/test-fast.sh --full

Areas:
  fast, cli, config, installer, packs, rules, layout, ui, tcp, integration, visual
EOF
}

area="${1:-fast}"
case "$area" in
    -h|--help)
        usage
        exit 0
        ;;
    --list)
        usage
        exit 0
        ;;
    --full)
        echo "🧪 test-fast: delegating to full safe test lane"
        KEYPATH_SNAPSHOTS=1 "$SCRIPT_DIR/run-tests-safe.sh"
        exit $?
        ;;
    --changed)
        cd "$REPO_ROOT"
        base_ref="${TEST_CHANGED_BASE:-origin/master}"
        if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
            diff_base=$(git merge-base "$base_ref" HEAD 2>/dev/null || echo "$base_ref")
        else
            diff_base="HEAD"
        fi

        changed_files=()
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            changed_files+=("$path")
        done < <(
            {
                git diff --name-only --diff-filter=ACMRT "$diff_base"...HEAD 2>/dev/null || true
                git diff --name-only --diff-filter=ACMRT 2>/dev/null || true
            } | awk 'NF' | sort -u
        )

        if [ "${#changed_files[@]}" -eq 0 ]; then
            echo "🧪 test-fast --changed: no changed files; running fast lane"
            area="fast"
        else
            lanes=()
            for path in "${changed_files[@]}"; do
                if lane=$(keypath_test_lane_reason_for_path "$path"); then
                    lanes+=("$lane")
                    echo "  $path -> $lane"
                else
                    echo "  $path -> full (no fast mapping)"
                    lanes=("full")
                    break
                fi
            done

            if printf '%s\n' "${lanes[@]}" | grep -qx full; then
                echo "🧪 test-fast --changed: falling back to full safe suite"
                KEYPATH_SNAPSHOTS=1 "$SCRIPT_DIR/run-tests-safe.sh"
                exit $?
            fi

            unique_lanes=$(printf '%s\n' "${lanes[@]}" | sort -u)
            filters=()
            while IFS= read -r lane; do
                [ -n "$lane" ] || continue
                filters+=("$(keypath_test_lane_filter "$lane")")
            done <<< "$unique_lanes"
            filter=$(keypath_join_filters "${filters[@]}")
            echo "🧪 test-fast --changed: lanes $(printf '%s' "$unique_lanes" | tr '\n' ' ')"
            echo "🎯 filter: $filter"
            TEST_FILTER="$filter" "$SCRIPT_DIR/run-tests-safe.sh"
            exit $?
        fi
        ;;
esac

if ! filter=$(keypath_test_lane_filter "$area"); then
    echo "Unknown test area: $area" >&2
    usage >&2
    exit 2
fi

echo "🧪 test-fast: area=$area"
echo "🎯 filter: $filter"
TEST_FILTER="$filter" "$SCRIPT_DIR/run-tests-safe.sh"
