#!/bin/bash
# Verifies that the bundled SMAppService plist points at the kanata-launcher wrapper.
set -euo pipefail

TARGET=${1:-dist/KeyPath.app}

if [ -d "$TARGET" ]; then
    PLIST="$TARGET/Contents/Library/LaunchDaemons/com.keypath.kanata.plist"
elif [ -f "$TARGET" ]; then
    PLIST="$TARGET"
else
    echo "❌ Target '$TARGET' not found" >&2
    exit 1
fi
EXPECTED="Contents/Library/KeyPath/kanata-launcher"

if [ ! -f "$PLIST" ]; then
    echo "❌ Plist not found at $PLIST" >&2
    exit 1
fi

arg0=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST" 2>/dev/null || true)
if [ "$arg0" != "$EXPECTED" ]; then
    echo "❌ ProgramArguments[0] is '$arg0' (expected '$EXPECTED')." >&2
    exit 1
fi

bundle_program=$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$PLIST" 2>/dev/null || true)
if [ "$bundle_program" != "$EXPECTED" ]; then
    echo "❌ BundleProgram is '$bundle_program' (expected '$EXPECTED')." >&2
    exit 1
fi

echo "✅ Verified kanata plist uses $EXPECTED"
