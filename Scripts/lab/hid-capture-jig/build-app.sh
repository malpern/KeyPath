#!/bin/bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_path=${KEYPATH_CAPTURE_JIG_APP:-"$HOME/.cache/keypath-hid-capture-jig/KeyPath HID Capture Jig.app"}
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/keypath-hid-jig-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT

swift build --package-path "$script_dir" --product HIDCaptureJig --jobs "${KEYPATH_CAPTURE_JIG_BUILD_JOBS:-4}"
bin_path=$(swift build --package-path "$script_dir" --show-bin-path)

mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
install -m 755 "$bin_path/HIDCaptureJig" "$app_path/Contents/MacOS/HIDCaptureJig"
install -m 644 "$script_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
xcrun swift "$script_dir/Resources/generate_jig_icon.swift" "$icon_work/JigIcon.iconset"
iconutil -c icns "$icon_work/JigIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
install -m 644 "$script_dir/../../../Sources/KeyPathApp/Resources/AppIcon.icns" \
  "$app_path/Contents/Resources/KeyPathLogo.icns"
codesign --force --sign - --timestamp=none "$app_path" >/dev/null
printf '%s\n' "$app_path"
