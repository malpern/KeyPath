#!/bin/bash
# Temporary diagnostic: does sandboxed metal work in this process context?
T=$(realpath "$(getconf DARWIN_USER_TEMP_DIR)"); C=$(realpath "$(getconf DARWIN_USER_CACHE_DIR)")
P="(version 1)(deny default)(import \"system.sb\")(allow file-read*)(allow process*)(allow mach-lookup (global-name \"com.apple.lsd.mapdb\"))(allow mach-lookup (global-name \"com.apple.mobileassetd.v2\"))(allow file-write* (subpath \"/private/tmp\") (subpath \"$T\") (subpath \"$C\"))"
echo 'kernel void k(){}' > /tmp/sbt.metal
echo "-- $1: plain"; /usr/bin/xcrun -sdk macosx metal /tmp/sbt.metal -o /tmp/sbt.lib 2>&1 | head -2; echo "rc=${PIPESTATUS[0]}"
echo "-- $1: sandboxed"; sandbox-exec -p "$P" /usr/bin/xcrun -sdk macosx metal /tmp/sbt.metal -o /tmp/sbt.lib 2>&1 | head -2; echo "rc=${PIPESTATUS[0]}"
env | grep -E '^(HOME|DEVELOPER_DIR|TMPDIR|SDKROOT|TOOLCHAINS|CLANG_|SWIFT_|XCODE|DYLD|__CF)' | sort
