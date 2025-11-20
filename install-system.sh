#!/bin/bash

# KeyPath system installer wrapper
# Uses the Swift-based CLI to run InstallerEngine intents.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BUILD_CONFIG="${KEYPATH_BUILD_CONFIG:-release}"
COMMAND="${1:-install}"

shift || true

function usage() {
    cat <<'EOF'
Usage: ./install-system.sh <command> [options]

Commands:
  install           Install KeyPath services (default)
  repair            Attempt to repair unhealthy services
  uninstall         Remove services (pass --delete-config to remove user config)
  status            Show current system status
  inspect           Inspect state without making changes
  help              Show CLI help

Examples:
  sudo ./install-system.sh install
  ./install-system.sh status
  ./install-system.sh uninstall --delete-config
EOF
}

case "$COMMAND" in
    install|repair|uninstall|status|inspect|help|--help|-h)
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac

echo "🔨 Building KeyPath CLI (configuration: $BUILD_CONFIG)..."
cd "$PROJECT_ROOT"
swift build --configuration "$BUILD_CONFIG" --product KeyPathCLI > /dev/null
BIN_DIR="$(swift build --configuration "$BUILD_CONFIG" --product KeyPathCLI --show-bin-path)"
CLI_BIN="$BIN_DIR/KeyPathCLI"

if [[ ! -x "$CLI_BIN" ]]; then
    echo "Failed to locate KeyPath CLI binary at $CLI_BIN"
    exit 1
fi

echo "🚀 Running KeyPath CLI: $COMMAND $*"
"$CLI_BIN" "$COMMAND" "$@"
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ KeyPath CLI command completed successfully."
else
    echo "❌ KeyPath CLI command failed with exit code $EXIT_CODE."
fi

exit $EXIT_CODE

