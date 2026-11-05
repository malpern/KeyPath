#!/bin/bash
# Generate Metadata.appintents for the hand-assembled KeyPath.app.
#
# macOS finds an app's App Intents (Shortcuts, Siri, Spotlight) through
# Contents/Resources/Metadata.appintents. Xcode writes it with
# appintentsmetadataprocessor; SwiftPM does not, so build-and-sign.sh calls
# this script after `swift build`. See
# docs/bugs/2026-11-04-app-intents-metadata-missing.md.
#
# Usage: generate-app-intents-metadata.sh <output-resources-dir> [Release|Debug]
#
# The processor reads the Swift compiler's const values (*.swiftconstvalues),
# which SwiftPM's Swift Build system writes next to the objects. The
# deprecated native build system does not, and this script then fails rather
# than ship an app without intents.
#
# Environment:
#   KEYPATH_APP_INTENTS_ARCH  architecture to read (default: arm64)
#   KEYPATH_SCRATCH_DIR   SwiftPM scratch path (default: <repo>/.build).
#                         build-and-sign.sh derives it from --show-bin-path.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)

OUTPUT_DIR="${1:?usage: $0 <output-resources-dir> [Release|Debug]}"
CONFIG="${2:-Release}"
SCRATCH_DIR="${KEYPATH_SCRATCH_DIR:-$REPO_DIR/.build}"

# The module that defines the intents. What must come out the other end is
# read from its sources (see check-app-intents-metadata.py), so a new intent
# cannot be dropped silently.
MODULE=KeyPathAppKit
SOURCE_DIR="$REPO_DIR/Sources/$MODULE"
# build-and-sign.sh builds arm64 only; override for another architecture.
ARCH="${KEYPATH_APP_INTENTS_ARCH:-arm64}"

fail() {
    echo "❌ App Intents metadata: $*" >&2
    exit 1
}

PROCESSOR=$(xcrun -f appintentsmetadataprocessor 2>/dev/null) \
    || fail "appintentsmetadataprocessor not found in the selected Xcode"
DEVELOPER_DIR_RESOLVED="${DEVELOPER_DIR:-$(xcode-select -p)}"
TOOLCHAIN_DIR="$DEVELOPER_DIR_RESOLVED/Toolchains/XcodeDefault.xctoolchain"
SDK_ROOT=$(xcrun --sdk macosx --show-sdk-path)
XCODE_BUILD=$(xcodebuild -version | awk '/Build version/ {print $3}')
INFO_PLIST="$REPO_DIR/Sources/KeyPathApp/Info.plist"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
DEPLOYMENT_TARGET=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST")

OBJ_DIR="$SCRATCH_DIR/out/Intermediates.noindex/KeyPath.build/$CONFIG/$MODULE-t.build/Objects-normal/$ARCH"
[ -d "$OBJ_DIR" ] || fail "no $CONFIG $ARCH Swift Build intermediates at $OBJ_DIR (a --build-system native build, a different --arch, or a different scratch path?)"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR:?}"' EXIT

find "$SOURCE_DIR" -name '*.swift' | sort > "$WORK_DIR/sources.txt"

# Const values come in two layouts. A whole-module build (release) writes one
# <module>-primary.swiftconstvalues; an incremental build (debug) writes one
# per source file. Use per-file values only for current sources, so a file
# left behind by a deleted source cannot resurrect an intent, and when both
# layouts are present use whichever was written last.
: > "$WORK_DIR/per-file.txt"
while IFS= read -r source; do
    candidate="$OBJ_DIR/$(basename "$source" .swift).swiftconstvalues"
    if [ -f "$candidate" ]; then
        echo "$candidate" >> "$WORK_DIR/per-file.txt"
    fi
done < "$WORK_DIR/sources.txt"
WHOLE_MODULE="$OBJ_DIR/$MODULE-primary.swiftconstvalues"

newest_mtime() { # newest mtime among the files listed in $1, 0 if none
    local newest=0 mtime
    while IFS= read -r f; do
        mtime=$(stat -f %m "$f")
        [ "$mtime" -gt "$newest" ] && newest=$mtime
    done < "$1"
    echo "$newest"
}

if [ -f "$WHOLE_MODULE" ] \
    && [ "$(stat -f %m "$WHOLE_MODULE")" -ge "$(newest_mtime "$WORK_DIR/per-file.txt")" ]; then
    echo "$WHOLE_MODULE" > "$WORK_DIR/constvals.txt"
else
    cp "$WORK_DIR/per-file.txt" "$WORK_DIR/constvals.txt"
fi
[ -s "$WORK_DIR/constvals.txt" ] || fail "no .swiftconstvalues for $MODULE in $OBJ_DIR"

# Fresh output, so a failed run cannot leave an old bundle behind.
rm -rf "${OUTPUT_DIR:?}/Metadata.appintents"
mkdir -p "$OUTPUT_DIR"

"$PROCESSOR" \
    --output "$OUTPUT_DIR" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name "$MODULE" \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_BUILD" \
    --platform-family macOS \
    --deployment-target "$DEPLOYMENT_TARGET" \
    --target-triple "$ARCH-apple-macos$DEPLOYMENT_TARGET" \
    --bundle-identifier "$BUNDLE_ID" \
    --source-file-list "$WORK_DIR/sources.txt" \
    --swift-const-vals-list "$WORK_DIR/constvals.txt" \
    --compile-time-extraction \
    > "$WORK_DIR/processor.log" 2>&1 \
    || { cat "$WORK_DIR/processor.log" >&2; fail "appintentsmetadataprocessor failed"; }

ACTIONS_DATA="$OUTPUT_DIR/Metadata.appintents/extract.actionsdata"
[ -f "$ACTIONS_DATA" ] || { cat "$WORK_DIR/processor.log" >&2; fail "processor wrote no $ACTIONS_DATA"; }

# A processor that saw no conformances may still write a bundle, so check
# that every intent, entity, enum and the shortcuts provider made it in.
python3 "$SCRIPT_DIR/check-app-intents-metadata.py" "$ACTIONS_DATA" "$SOURCE_DIR" \
    || fail "$ACTIONS_DATA does not match the App Intents types in $SOURCE_DIR"

echo "✅ App Intents metadata written to $OUTPUT_DIR/Metadata.appintents"
