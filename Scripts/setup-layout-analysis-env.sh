#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv-layout-analysis"
PYTHON_BIN="${PYTHON_BIN:-python3}"
REQUIREMENTS_FILE="$ROOT_DIR/Scripts/requirements-layout-analysis.txt"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python interpreter not found: $PYTHON_BIN" >&2
  exit 1
fi

echo "Creating analysis virtualenv at: $VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"

echo "Upgrading pip"
"$VENV_DIR/bin/python" -m pip install --upgrade pip

echo "Installing analysis dependencies from $REQUIREMENTS_FILE"
"$VENV_DIR/bin/python" -m pip install -r "$REQUIREMENTS_FILE"

echo
echo "Layout analysis environment ready."
echo "Python: $VENV_DIR/bin/python"
echo "To use it manually:"
echo "  $VENV_DIR/bin/python $ROOT_DIR/Scripts/analyze_keyboard_image.py --image /path/to/image --output /tmp/analysis.json"
