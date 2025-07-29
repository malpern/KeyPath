#!/bin/bash

# KeyPath Uninstall Script
# Removes KeyPath and the Kanata LaunchDaemon

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LAUNCH_DAEMON_LABEL="com.keypath.kanata"
LAUNCH_DAEMON_PLIST="/Library/LaunchDaemons/${LAUNCH_DAEMON_LABEL}.plist"
KANATA_CONFIG_DIR="/usr/local/etc/kanata"
KEYPATH_APP_DIR="/Applications/KeyPath.app"

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
    log_info "Stopping and unloading LaunchDaemon..."
    
    # Stop the daemon if it's running
    if launchctl list | grep -q "$LAUNCH_DAEMON_LABEL"; then
        launchctl kill TERM "system/$LAUNCH_DAEMON_LABEL" 2>/dev/null || true
        sleep 2
        launchctl unload "$LAUNCH_DAEMON_PLIST" 2>/dev/null || true
        log_success "LaunchDaemon stopped and unloaded"
    else
        log_info "LaunchDaemon was not running"
    fi
}

remove_launch_daemon() {
    log_info "Removing LaunchDaemon plist..."
    
    if [[ -f "$LAUNCH_DAEMON_PLIST" ]]; then
        rm -f "$LAUNCH_DAEMON_PLIST"
        log_success "LaunchDaemon plist removed"
    else
        log_info "LaunchDaemon plist not found"
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
}

main() {
    echo -e "${BLUE}KeyPath Uninstaller${NC}"
    echo "=================="
    echo
    
    # Check if running as root
    check_root
    
    # Confirm uninstall
    echo -e "${YELLOW}This will completely remove KeyPath and all its components.${NC}"
    echo -n "Are you sure you want to continue? (y/N): "
    read -r response
    
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
    
    # Remove KeyPath app
    remove_keypath_app
    
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