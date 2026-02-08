#!/bin/bash

# KeyPath Uninstall Script
# Removes KeyPath and the Kanata LaunchDaemon

set -e

ASSUME_YES=0
DELETE_CONFIG=0

print_usage() {
    cat <<'EOF'
Usage: uninstall.sh [--assume-yes] [--delete-config]

Options:
  --assume-yes, --yes, -y   Skip the interactive confirmation prompt.
  --delete-config           Delete user configuration at ~/.config/keypath
  -h, --help                Show this help message.

You must run this script with sudo/root privileges.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --assume-yes|--yes|-y)
            ASSUME_YES=1
            shift
            ;;
        --delete-config)
            DELETE_CONFIG=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

if [[ "${KEYPATH_UNINSTALL_ASSUME_YES:-0}" == "1" ]]; then
    ASSUME_YES=1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LAUNCH_DAEMON_LABEL="com.keypath.kanata"
LAUNCH_DAEMON_PLIST="/Library/LaunchDaemons/${LAUNCH_DAEMON_LABEL}.plist"
VHID_DAEMON_LABEL="com.keypath.karabiner-vhiddaemon"
VHID_DAEMON_PLIST="/Library/LaunchDaemons/${VHID_DAEMON_LABEL}.plist"
VHID_MANAGER_LABEL="com.keypath.karabiner-vhidmanager"
VHID_MANAGER_PLIST="/Library/LaunchDaemons/${VHID_MANAGER_LABEL}.plist"
KANATA_CONFIG_DIR="/usr/local/etc/kanata"
KEYPATH_APP_DIR="/Applications/KeyPath.app"

TARGET_USER="${SUDO_USER:-$(stat -f %Su /dev/console 2>/dev/null || whoami)}"
TARGET_HOME=""
if [[ -n "$TARGET_USER" ]]; then
    TARGET_HOME=$(eval echo "~$TARGET_USER" 2>/dev/null || echo "")
fi

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

stop_and_unload_daemon() {
    log_info "Stopping and unloading LaunchDaemons..."

    # Stop kanata daemon if it's running
    if launchctl list | grep -q "$LAUNCH_DAEMON_LABEL"; then
        launchctl kill TERM "system/$LAUNCH_DAEMON_LABEL" 2>/dev/null || true
        sleep 2
        launchctl bootout "system/$LAUNCH_DAEMON_LABEL" 2>/dev/null || true
        log_success "Kanata LaunchDaemon stopped and unloaded"
    else
        log_info "Kanata LaunchDaemon was not running"
    fi

    # Stop VirtualHID daemon
    if launchctl list | grep -q "$VHID_DAEMON_LABEL"; then
        launchctl kill TERM "system/$VHID_DAEMON_LABEL" 2>/dev/null || true
        launchctl bootout "system/$VHID_DAEMON_LABEL" 2>/dev/null || true
        log_success "VirtualHID daemon stopped and unloaded"
    fi

    # Stop VirtualHID manager
    if launchctl list | grep -q "$VHID_MANAGER_LABEL"; then
        launchctl kill TERM "system/$VHID_MANAGER_LABEL" 2>/dev/null || true
        launchctl bootout "system/$VHID_MANAGER_LABEL" 2>/dev/null || true
        log_success "VirtualHID manager stopped and unloaded"
    fi

    # Legacy log rotation daemon cleanup
    launchctl bootout system/com.keypath.logrotate 2>/dev/null || true
}

remove_launch_daemon() {
    log_info "Removing LaunchDaemon plists..."
    
    if [[ -f "$LAUNCH_DAEMON_PLIST" ]]; then
        rm -f "$LAUNCH_DAEMON_PLIST"
        log_success "Kanata LaunchDaemon plist removed"
    else
        log_info "Kanata LaunchDaemon plist not found"
    fi
    
    if [[ -f "$VHID_DAEMON_PLIST" ]]; then
        rm -f "$VHID_DAEMON_PLIST"
        log_success "VirtualHID daemon plist removed"
    fi
    
    if [[ -f "$VHID_MANAGER_PLIST" ]]; then
        rm -f "$VHID_MANAGER_PLIST"
        log_success "VirtualHID manager plist removed"
    fi
}

remove_config_directory() {
    log_info "Removing config directory..."
    
    if [[ -d "$KANATA_CONFIG_DIR" ]]; then
        rm -rf "$KANATA_CONFIG_DIR"
        log_success "Config directory removed"
    else
        log_info "Config directory not found"
    fi
}

remove_system_kanata() {
    log_info "Removing system-installed kanata binary..."
    
    if [[ -f "/Library/KeyPath/bin/kanata" ]]; then
        rm -f "/Library/KeyPath/bin/kanata"
        # Remove directory if empty
        rmdir "/Library/KeyPath/bin" 2>/dev/null || true
        rmdir "/Library/KeyPath" 2>/dev/null || true
        log_success "System kanata binary removed"
    else
        log_info "System kanata binary not found"
    fi
}

remove_keypath_app() {
    log_info "Removing KeyPath app..."
    
    if [[ -d "$KEYPATH_APP_DIR" ]]; then
        rm -rf "$KEYPATH_APP_DIR"
        log_success "KeyPath app removed"
    else
        log_info "KeyPath app not found"
    fi
}

remove_log_files() {
    log_info "Removing log files..."

    if [[ -f "/var/log/kanata.log" ]]; then
        rm -f "/var/log/kanata.log"
        log_success "Log files removed"
    else
        log_info "Log files not found"
    fi

    # Remove newsyslog config
    if [[ -f "/etc/newsyslog.d/com.keypath.conf" ]]; then
        rm -f "/etc/newsyslog.d/com.keypath.conf"
        log_success "Newsyslog config removed"
    fi

    # Remove legacy log rotation script
    if [[ -f "/usr/local/bin/keypath-logrotate.sh" ]]; then
        rm -f "/usr/local/bin/keypath-logrotate.sh"
        log_success "Legacy log rotation script removed"
    fi

    # Remove legacy log rotation plist
    if [[ -f "/Library/LaunchDaemons/com.keypath.logrotate.plist" ]]; then
        rm -f "/Library/LaunchDaemons/com.keypath.logrotate.plist"
        log_success "Legacy log rotation plist removed"
    fi
}

remove_user_data() {
    if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
        log_warning "Could not determine user home directory; skipping user data cleanup"
        return
    fi

    log_info "Removing user-specific data for $TARGET_USER ($TARGET_HOME)..."

    local protected_config="$TARGET_HOME/.config/keypath"
    if [[ "$DELETE_CONFIG" -eq 1 ]]; then
        if [[ -e "$protected_config" ]]; then
            rm -rf "$protected_config"
            log_success "Removed user configuration at $protected_config"
        else
            log_info "No user configuration found at $protected_config"
        fi
    else
        if [[ -e "$protected_config" ]]; then
            log_info "Preserving user configuration at $protected_config"
        else
            log_info "No user configuration found to preserve (expected path: $protected_config)"
        fi
    fi

    local user_paths=(
        "$TARGET_HOME/Library/Application Support/KeyPath"
        "$TARGET_HOME/Library/Logs/KeyPath"
    )

    for path in "${user_paths[@]}"; do
        if [[ -e "$path" ]]; then
            rm -rf "$path"
            log_success "Removed $path"
        else
            log_info "$path not found"
        fi
    done

    local prefs_dir="$TARGET_HOME/Library/Preferences"
    if [[ -d "$prefs_dir" ]]; then
        if compgen -G "$prefs_dir/com.keypath*.plist" > /dev/null; then
            rm -f "$prefs_dir"/com.keypath*.plist
            log_success "Removed KeyPath preference plists"
        else
            log_info "No KeyPath preference plists found"
        fi
    fi
}

main() {
    echo -e "${BLUE}KeyPath Uninstaller${NC}"
    echo "=================="
    echo
    
    # Check if running as root
    check_root
    
    # Confirm uninstall
    echo -e "${YELLOW}This will completely remove KeyPath and all its components.${NC}"

    local response
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        log_info "Assume-yes flag detected; skipping interactive confirmation"
        response="y"
    else
        echo -n "Are you sure you want to continue? (y/N): "
        read -r response
    fi
    
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
        log_info "Uninstall cancelled"
        exit 0
    fi
    
    echo
    
    # Stop and unload daemon
    stop_and_unload_daemon
    
    # Remove LaunchDaemon
    remove_launch_daemon
    
    # Remove config directory
    remove_config_directory
    
    # Remove system-installed kanata
    remove_system_kanata
    
    # Remove KeyPath app
    remove_keypath_app

    # Remove user-specific data (config, support files)
    remove_user_data

    # Remove log files
    remove_log_files
    
    echo
    log_success "KeyPath has been completely uninstalled!"
    echo
    echo "Note: Kanata itself was not removed. If you no longer need it:"
    echo "  brew uninstall kanata"
    echo
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
