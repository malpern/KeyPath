#!/bin/bash
set -euo pipefail

KANATA_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
KANATA_BIN="$KANATA_DIR/kanata"

# Crash loop prevention: retry counter file
RETRY_COUNT_FILE="/var/tmp/keypath-vhid-retry-count"
MAX_RETRIES=3
RETRY_RESET_SECONDS=60

# Check if VirtualHID daemon is running (required for Kanata to work)
check_vhid_daemon() {
    /usr/bin/pgrep -f "VirtualHIDDevice-Daemon" > /dev/null 2>&1
}

# Get current retry count, reset if file is stale
get_retry_count() {
    if [ ! -f "$RETRY_COUNT_FILE" ]; then
        echo 0
        return
    fi

    # Check if file is older than RETRY_RESET_SECONDS - if so, reset
    local file_age
    file_age=$(( $(date +%s) - $(stat -f%m "$RETRY_COUNT_FILE" 2>/dev/null || echo 0) ))
    if [ "$file_age" -gt "$RETRY_RESET_SECONDS" ]; then
        rm -f "$RETRY_COUNT_FILE"
        echo 0
        return
    fi

    cat "$RETRY_COUNT_FILE" 2>/dev/null || echo 0
}

# Increment and save retry count
increment_retry_count() {
    local count
    count=$(get_retry_count)
    count=$((count + 1))
    echo "$count" > "$RETRY_COUNT_FILE"
    echo "$count"
}

# Pre-flight check: ensure VirtualHID daemon is available
# If not, we increment retry counter and either wait-and-retry or give up
if ! check_vhid_daemon; then
    retry_count=$(increment_retry_count)
    /usr/bin/logger -t "kanata-launcher" "VirtualHID daemon not running (attempt $retry_count/$MAX_RETRIES)"

    if [ "$retry_count" -ge "$MAX_RETRIES" ]; then
        # Too many failures - exit cleanly to stop launchd from restarting
        # (SuccessfulExit: false in plist means exit 0 = stop restarting)
        /usr/bin/logger -t "kanata-launcher" "Max retries reached. Exiting cleanly to stop restart loop. Open KeyPath app to diagnose."
        # Write status file for KeyPath app to detect
        echo "$(date): VirtualHID daemon not available after $MAX_RETRIES attempts" > /var/tmp/keypath-startup-blocked
        exit 0
    fi

    # Wait a bit and let launchd retry (ThrottleInterval will space out attempts)
    # Exit with error so launchd knows to retry
    exit 1
fi

# VirtualHID is healthy - reset retry counter and status file
rm -f "$RETRY_COUNT_FILE" /var/tmp/keypath-startup-blocked 2>/dev/null || true

get_console_user() {
    /usr/bin/stat -f%Su /dev/console 2>/dev/null || echo root
}

get_home_for_user() {
    local user="$1"
    if [ "$user" = "root" ] || [ -z "$user" ]; then
        echo "/var/root"
        return
    fi

    local home
    home=$(/usr/bin/dscacheutil -q user -a name "$user" 2>/dev/null | awk -F': ' '/dir/{print $2; exit}')
    if [ -z "$home" ]; then
        home="/Users/$user"
    fi
    echo "$home"
}

console_user=$(get_console_user)
console_home=$(get_home_for_user "$console_user")
config_path="$console_home/.config/keypath/keypath.kbd"
config_dir=$(dirname "$config_path")
console_group=

if [ "$console_user" != "root" ] && id -gn "$console_user" >/dev/null 2>&1; then
    console_group=$(id -gn "$console_user")
    /usr/bin/install -d -m 755 -o "$console_user" -g "$console_group" "$config_dir"
else
    /usr/bin/install -d -m 755 "$config_dir"
fi
/usr/bin/touch "$config_path"
if [ "$console_user" != "root" ]; then
    /usr/sbin/chown "$console_user":"${console_group:-staff}" "$config_path" 2>/dev/null || true
fi

/usr/bin/logger -t "kanata-launcher" "Launching Kanata for user=$console_user config=$config_path"

exec "$KANATA_BIN" --cfg "$config_path" "$@"
