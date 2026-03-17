#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_ROOT="${SCRIPT_DIR%/Scripts}"

ALLOW_COVERAGE_DROP=false

for arg in "$@"; do
    case "$arg" in
        --allow-coverage-drop)
            ALLOW_COVERAGE_DROP=true
            ;;
        *)
            echo "❌ Invalid argument: $arg"
            echo "Usage: $0 [--allow-coverage-drop]"
            exit 1
            ;;
    esac
done

cd "$REPO_ROOT"

echo "🔄 Refreshing QMK VID:PID index..."
python3 Scripts/generate_vid_pid_index.py

echo ""
echo "🔄 Generating normalized keyboard detection index..."
if [ "$ALLOW_COVERAGE_DROP" = true ]; then
    python3 Scripts/generate_keyboard_detection_index.py --allow-coverage-drop
else
    python3 Scripts/generate_keyboard_detection_index.py
fi

echo ""
echo "✅ Keyboard detection data refreshed."
