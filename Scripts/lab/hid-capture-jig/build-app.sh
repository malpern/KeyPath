#!/bin/bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_path=${KEYPATH_CAPTURE_JIG_APP:-"$HOME/.cache/keypath-hid-capture-jig/KeyPath HID Capture Jig.app"}
source_stamp="$app_path/Contents/Resources/source.sha256"
source_hash=$(
    {
        find "$script_dir/Sources" "$script_dir/Resources" -type f -print
        printf '%s\n' "$script_dir/Package.swift"
    } | LC_ALL=C sort | while IFS= read -r source; do
        shasum -a 256 "$source"
    done | shasum -a 256 | awk '{print $1}'
)

if [[ ${KEYPATH_CAPTURE_JIG_FORCE_BUILD:-0} != 1 &&
      -x "$app_path/Contents/MacOS/HIDCaptureJig" &&
      -f "$source_stamp" &&
      $(<"$source_stamp") == "$source_hash" ]]; then
    printf '%s\n' "$app_path"
    exit 0
fi
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/keypath-hid-jig-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT

swift build --package-path "$script_dir" --product HIDCaptureJig --jobs "${KEYPATH_CAPTURE_JIG_BUILD_JOBS:-4}"
bin_path=$(swift build --package-path "$script_dir" --show-bin-path)

mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
# Keep incremental app builds from retaining resources removed from the bundle.
rm -f "$app_path/Contents/Resources/KeyPathLogo.icns"
install -m 755 "$bin_path/HIDCaptureJig" "$app_path/Contents/MacOS/HIDCaptureJig"
install -m 644 "$script_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
xcrun swift "$script_dir/Resources/generate_jig_icon.swift" "$icon_work/JigIcon.iconset"
iconutil -c icns "$icon_work/JigIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
printf '%s\n' "$source_hash" >"$source_stamp"
codesign --force --sign - --timestamp=none "$app_path" >/dev/null
printf '%s\n' "$app_path"
