#!/bin/bash

# Shared helper: inject the main app's version into an embedded Info.plist.
# Keeps KanataEngine.app in sync with the parent app across both build scripts.
#
# Usage:
#   source Scripts/lib/plist-version.sh
#   inject_kanata_engine_version "$SOURCE_INFO_PLIST_DIR" "$TARGET_INFO_PLIST"
#
# Parameters:
#   $1 - Directory containing the source Info.plist (without .plist extension),
#        suitable for `defaults read`.
#   $2 - Path to the target Info.plist to update via PlistBuddy.

inject_kanata_engine_version() {
    local source_plist="$1"
    local target_plist="$2"

    local ver
    local build
    ver=$(defaults read "$source_plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
    build=$(defaults read "$source_plist" CFBundleVersion 2>/dev/null || echo "1")

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString \"$ver\"" "$target_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion \"$build\"" "$target_plist"
}
