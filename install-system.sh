#!/bin/bash

# KeyPath System Installation Script
# Installs KeyPath with LaunchDaemon for system-level Kanata service
# Based on Karabiner-Elements approach

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
KANATA_CONFIG_FILE="${KANATA_CONFIG_DIR}/keypath.kbd"
KANATA_BINARY="/usr/local/bin/kanata-cmd"
KEYPATH_APP_DIR="/Applications"

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

check_kanata() {
    if [[ ! -f "$KANATA_BINARY" ]]; then
        log_error "Kanata not found at $KANATA_BINARY"
        log_error "Please compile Kanata with cmd feature first"
        exit 1
    fi
    log_success "Kanata found at $KANATA_BINARY"
}

create_config_directory() {
    log_info "Creating config directory..."
    mkdir -p "$KANATA_CONFIG_DIR"
    chown root:wheel "$KANATA_CONFIG_DIR"
    chmod 755 "$KANATA_CONFIG_DIR"
    log_success "Config directory created at $KANATA_CONFIG_DIR"
}

create_default_config() {
    log_info "Creating default Kanata configuration..."
    
    cat > "$KANATA_CONFIG_FILE" << 'EOF'
;; KeyPath System Configuration
;; This file will be updated by the KeyPath app

(defcfg
  process-unmapped-keys yes
)

(defsrc
  caps
)

(deflayer base
  esc
)
EOF
    
    chown root:wheel "$KANATA_CONFIG_FILE"
    chmod 644 "$KANATA_CONFIG_FILE"
    log_success "Default config created at $KANATA_CONFIG_FILE"
}

create_launch_daemon() {
    log_info "Creating LaunchDaemon..."
    
    cat > "$LAUNCH_DAEMON_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_DAEMON_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${KANATA_BINARY}</string>
        <string>--cfg</string>
        <string>${KANATA_CONFIG_FILE}</string>
    </array>
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/var/log/kanata.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/kanata.log</string>
    <key>ThrottleInterval</key>
    <integer>1</integer>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF
    
    chown root:wheel "$LAUNCH_DAEMON_PLIST"
    chmod 644 "$LAUNCH_DAEMON_PLIST"
    log_success "LaunchDaemon created at $LAUNCH_DAEMON_PLIST"
}

install_keypath_app() {
    if [[ -d "build/KeyPath.app" ]]; then
        log_info "Installing KeyPath app..."
        
        # Remove existing app if it exists
        if [[ -d "$KEYPATH_APP_DIR/KeyPath.app" ]]; then
            rm -rf "$KEYPATH_APP_DIR/KeyPath.app"
        fi
        
        # Copy new app
        cp -R "build/KeyPath.app" "$KEYPATH_APP_DIR/"
        
        # Fix permissions
        chown -R root:wheel "$KEYPATH_APP_DIR/KeyPath.app"
        chmod -R 755 "$KEYPATH_APP_DIR/KeyPath.app"
        
        log_success "KeyPath app installed to $KEYPATH_APP_DIR/KeyPath.app"
    else
        log_warning "KeyPath app not found. Please run ./build.sh first"
    fi
}

load_launch_daemon() {
    log_info "Loading LaunchDaemon..."
    
    # Load the daemon
    launchctl load -w "$LAUNCH_DAEMON_PLIST"
    
    # Check if it loaded successfully
    if launchctl list | grep -q "$LAUNCH_DAEMON_LABEL"; then
        log_success "LaunchDaemon loaded successfully"
    else
        log_warning "LaunchDaemon may not have loaded properly"
    fi
}

test_installation() {
    log_info "Testing installation..."
    
    # Test config file
    if "$KANATA_BINARY" --cfg "$KANATA_CONFIG_FILE" --check; then
        log_success "Kanata config is valid"
    else
        log_error "Kanata config is invalid"
        exit 1
    fi
    
    # Test service status
    if launchctl list | grep -q "$LAUNCH_DAEMON_LABEL"; then
        log_success "LaunchDaemon is loaded"
    else
        log_warning "LaunchDaemon is not loaded"
    fi
}

show_usage_info() {
    echo
    log_info "Installation completed successfully!"
    echo
    echo "Usage:"
    echo "• Start Kanata:    sudo launchctl kickstart -k system/$LAUNCH_DAEMON_LABEL"
    echo "• Stop Kanata:     sudo launchctl kill TERM system/$LAUNCH_DAEMON_LABEL"
    echo "• Check status:    sudo launchctl print system/$LAUNCH_DAEMON_LABEL"
    echo "• View logs:       tail -f /var/log/kanata.log"
    echo
    echo "KeyPath app:"
    echo "• Launch app:      open /Applications/KeyPath.app"
    echo "• The app will automatically update $KANATA_CONFIG_FILE"
    echo
    echo "IMPORTANT: Grant Accessibility permissions to KeyPath in System Preferences"
    echo "          Security & Privacy > Accessibility"
    echo
}

main() {
    echo -e "${BLUE}KeyPath System Installation${NC}"
    echo "=========================="
    echo
    
    # Check if running as root
    check_root
    
    # Check prerequisites
    check_kanata
    
    # Create configuration
    create_config_directory
    create_default_config
    
    # Create LaunchDaemon
    create_launch_daemon
    
    # Install KeyPath app
    install_keypath_app
    
    # Load the daemon
    load_launch_daemon
    
    # Test installation
    test_installation
    
    # Show usage information
    show_usage_info
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi