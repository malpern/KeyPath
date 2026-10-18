#!/bin/bash
# Package an already signed app for private testing. No build, deploy or publication.
set -euo pipefail
if [[ $# != 2 ]]; then
    echo "Usage: $0 /path/to/KeyPath.app /path/to/KeyPath.dmg" >&2
    exit 2
fi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUTPUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
[[ -d "$APP" && $(basename "$APP") == KeyPath.app ]] || { echo 'Expected KeyPath.app' >&2; exit 2; }
[[ ! -e "$OUTPUT" ]] || { echo 'Output already exists; choose a new filename.' >&2; exit 2; }
DMGBUILD=${DMGBUILD_BIN:-dmgbuild}
command -v "$DMGBUILD" >/dev/null || { echo 'Install dmgbuild in a virtual environment and set DMGBUILD_BIN.' >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$APP"
export DMG_APP_PATH="$APP" DMG_DIR="$SCRIPT_DIR/../dev-tools/dmg"
# Finder needs logical image dimensions; @2x in a PNG filename is insufficient.
# Preserve every pixel and declare the 1320x800 artwork as 660x400 points.
BACKGROUND_DIR=$(mktemp -d)
VERIFY_MOUNT="$BACKGROUND_DIR/verify"
VERIFY_MOUNTED=0
cleanup() {
    if [[ "$VERIFY_MOUNTED" == 1 ]]; then
        /usr/bin/hdiutil detach "$VERIFY_MOUNT" >/dev/null || return
    fi
    rm -rf "$BACKGROUND_DIR"
}
trap cleanup EXIT
/usr/bin/sips -s format tiff -s dpiWidth 144 -s dpiHeight 144 \
    "$DMG_DIR/dmg-background-light@2x.png" --out "$BACKGROUND_DIR/background.tiff" >/dev/null
export DMG_BACKGROUND="$BACKGROUND_DIR/background.tiff"
"$DMGBUILD" -s "$DMG_DIR/dmgbuild-settings.py" KeyPath "$OUTPUT"
/usr/bin/hdiutil verify "$OUTPUT"
# Verify the actual packaged bundle: layout tools can add Finder metadata
# after the source signature check above.
mkdir "$VERIFY_MOUNT"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$VERIFY_MOUNT" "$OUTPUT" >/dev/null
VERIFY_MOUNTED=1
/usr/bin/codesign --verify --deep --strict "$VERIFY_MOUNT/KeyPath.app"
/usr/bin/hdiutil detach "$VERIFY_MOUNT" >/dev/null
VERIFY_MOUNTED=0
echo "Created private test image: $OUTPUT"
echo 'Sign and notarize this image before distribution. The contained app is unchanged.'
