#!/bin/bash
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source "$repo_root/Scripts/lib/xcode.sh"
keypath_use_stable_xcode
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/keypath-caps-lease.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
swiftc -module-cache-path "$tmp_dir/module-cache" -emit-library -emit-module -module-name KeyPathCore \
    "$repo_root/Sources/KeyPathCore/SessionRuntime/SessionCapsMappingPolicy.swift" \
    -emit-module-path "$tmp_dir/KeyPathCore.swiftmodule" -o "$tmp_dir/libKeyPathCore.dylib"
swiftc -module-cache-path "$tmp_dir/module-cache" -I "$tmp_dir" -L "$tmp_dir" -lKeyPathCore -Xlinker -rpath -Xlinker "$tmp_dir" \
    "$repo_root/Sources/KeyPathAppKit/Services/SessionRuntime/SessionCapsMappingLease.swift" \
    "$repo_root/Sources/KeyPathAppKit/Services/SessionRuntime/SessionCapsHIDUtilTransport.swift" \
    "$repo_root/Tests/Experiments/SessionCapsMappingLeaseRunner.swift" \
    -o "$tmp_dir/caps-lease-runner"
"$tmp_dir/caps-lease-runner"
