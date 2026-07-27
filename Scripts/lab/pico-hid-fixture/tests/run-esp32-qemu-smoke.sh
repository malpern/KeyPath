#!/bin/bash
set -euo pipefail

fixture_root=$(cd "$(dirname "$0")/.." && pwd)
target="$fixture_root/targets/waveshare-esp32-s3-touch-lcd-1.69"
idf_path=${IDF_PATH:-"$HOME/.cache/keypath-esp32/esp-idf"}
build_dir=${KEYPATH_ESP32_QEMU_BUILD_DIR:-"${TMPDIR:-/tmp}/keypath-esp32-qemu-smoke-build"}
qemu_defaults="$target/sdkconfig.qemu.defaults"
defaults_stamp="$build_dir/.keypath-qemu-defaults.sha256"

if [[ ! -f "$idf_path/export.sh" ]]; then
    echo "ESP-IDF was not found at $idf_path" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$idf_path/export.sh" >/dev/null
export KEYPATH_WIFI_SSID_1=fixture-qemu-primary
export KEYPATH_WIFI_PASSWORD_1=fixture-qemu-placeholder
export KEYPATH_WIFI_SSID_2=fixture-qemu-fallback-one
export KEYPATH_WIFI_PASSWORD_2=fixture-qemu-placeholder
export KEYPATH_WIFI_SSID_3=fixture-qemu-fallback-two
export KEYPATH_WIFI_PASSWORD_3=fixture-qemu-placeholder
export KEYPATH_FIXTURE_TOKEN=fixture-qemu-token-placeholder
export KEYPATH_QEMU_SMOKE=1

defaults_hash=$(shasum -a 256 "$qemu_defaults" | awk '{print $1}')
stored_hash=$(cat "$defaults_stamp" 2>/dev/null || true)
if [[ ! -f "$build_dir/sdkconfig" || "$stored_hash" != "$defaults_hash" ]]; then
    rm -f "$build_dir/sdkconfig"
    idf.py -C "$target" -B "$build_dir" \
        -D "SDKCONFIG=$build_dir/sdkconfig" \
        -D "SDKCONFIG_DEFAULTS=$qemu_defaults" \
        reconfigure build >/dev/null
    printf '%s\n' "$defaults_hash" >"$defaults_stamp"
else
    idf.py -C "$target" -B "$build_dir" build >/dev/null
fi

log_file=$(mktemp "${TMPDIR:-/tmp}/keypath-qemu-smoke.XXXXXX")
qemu_pid=
cleanup() {
    if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
        child_pids=$(pgrep -P "$qemu_pid" 2>/dev/null || true)
        [[ -z "$child_pids" ]] || kill $child_pids 2>/dev/null || true
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    rm -f "$log_file"
}
trap cleanup EXIT INT TERM

idf.py -C "$target" -B "$build_dir" qemu >"$log_file" 2>&1 &
qemu_pid=$!
for _ in $(seq 1 120); do
    if grep -q "KEYPATH_QEMU_SMOKE_PASS" "$log_file"; then
        echo "ESP32-S3 QEMU smoke test passed"
        exit 0
    fi
    if grep -q "KEYPATH_QEMU_SMOKE_FAIL" "$log_file"; then
        cat "$log_file" >&2
        exit 1
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        cat "$log_file" >&2
        exit 1
    fi
    sleep 0.25
done

cat "$log_file" >&2
echo "Timed out waiting for the ESP32-S3 QEMU smoke marker" >&2
exit 1
