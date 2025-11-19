#!/bin/bash
# Install KeyPath using the CLI
# This script builds KeyPath and runs the CLI to perform installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"
"$PROJECT_ROOT/install-system.sh" "${1:-install}" "${@:2}"
