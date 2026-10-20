#!/usr/bin/env bash
# KeyPath's own release components must be Apple Silicon only. Vendored
# frameworks may contain additional architectures; they are not support claims.
set -euo pipefail

APP_PATH="${1:?Usage: verify-apple-silicon.sh /path/to/KeyPath.app}"
for relative_path in \
    "Contents/MacOS/KeyPath" \
    "Contents/MacOS/keypath-cli" \
    "Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" \
    "Contents/Library/KeyPath/kanata-simulator" \
    "Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata" \
    "Contents/PlugIns/Insights.bundle/Contents/MacOS/libKeyPathInsights"; do
    executable="$APP_PATH/$relative_path"
    if [[ ! -f "$executable" ]]; then
        echo "Missing Apple Silicon release component: $relative_path" >&2
        exit 1
    fi
    architectures=$(lipo -archs "$executable")
    if [[ "$architectures" != "arm64" ]]; then
        echo "KeyPath requires Apple Silicon only: $relative_path has architectures '$architectures' (expected arm64)." >&2
        exit 1
    fi
done
echo "Apple Silicon-only release components verified (arm64)."
