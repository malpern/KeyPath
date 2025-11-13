#!/bin/bash
set -euo pipefail

KANATA_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
KANATA_BIN="$KANATA_DIR/kanata"

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
