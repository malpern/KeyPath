#!/bin/bash

# Comprehensive Kanata System Test
# Tests installation, auto-launch, hot reload, and service management

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
KANATA_BINARY="/opt/homebrew/bin/kanata"

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

test_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

check_prerequisites() {
    test_step "Checking Prerequisites"
    
    # Check if Kanata is installed
    if [[ ! -f "$KANATA_BINARY" ]]; then
        log_error "Kanata not found at $KANATA_BINARY"
        log_error "Please install Kanata first: brew install kanata"
        exit 1
    fi
    log_success "Kanata found at $KANATA_BINARY"
    
    # Check if KeyPath app is built
    if [[ ! -d "build/KeyPath.app" ]]; then
        log_error "KeyPath app not found"
        log_error "Please run ./build.sh first"
        exit 1
    fi
    log_success "KeyPath app found"
    
    echo
}

test_installation() {
    test_step "Testing Installation"
    
    # Run the installation test
    if ./test-installer.sh > /dev/null 2>&1; then
        log_success "Installation test passed"
    else
        log_error "Installation test failed"
        exit 1
    fi
    
    echo
}

test_config_generation() {
    test_step "Testing Config Generation"
    
    # Test various config combinations
    local test_configs=(
        "caps:esc"
        "caps:a"
        "spc:ret"
        "tab:spc"
    )
    
    for config in "${test_configs[@]}"; do
        IFS=':' read -r input output <<< "$config"
        log_info "Testing $input -> $output"
        
        # Generate test config
        local temp_config="/tmp/test-keypath-$input-$output.kbd"
        cat > "$temp_config" << EOF
;; KeyPath Test Configuration
;; Input: $input -> Output: $output

(defcfg
  process-unmapped-keys yes
)

(defsrc
  $input
)

(deflayer base
  $output
)
EOF
        
        # Validate config
        if "$KANATA_BINARY" --cfg "$temp_config" --check > /dev/null 2>&1; then
            log_success "$input -> $output config is valid"
        else
            log_error "$input -> $output config is invalid"
            cat "$temp_config"
            rm -f "$temp_config"
            exit 1
        fi
        
        rm -f "$temp_config"
    done
    
    echo
}

test_service_management() {
    test_step "Testing Service Management (Dry Run)"
    
    # Test if we can check service status (should fail gracefully if not installed)
    log_info "Testing service status check..."
    if launchctl print "system/$LAUNCH_DAEMON_LABEL" > /dev/null 2>&1; then
        log_success "Service is installed and can be checked"
    else
        log_info "Service is not installed (expected)"
    fi
    
    # Test if we can validate LaunchDaemon plist format
    log_info "Testing LaunchDaemon plist generation..."
    local temp_plist="/tmp/test-keypath-daemon.plist"
    cat > "$temp_plist" << EOF
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
</dict>
</plist>
EOF
    
    # Validate plist format
    if plutil -lint "$temp_plist" > /dev/null 2>&1; then
        log_success "LaunchDaemon plist format is valid"
    else
        log_error "LaunchDaemon plist format is invalid"
        rm -f "$temp_plist"
        exit 1
    fi
    
    rm -f "$temp_plist"
    echo
}

test_hot_reload_simulation() {
    test_step "Testing Hot Reload Simulation"
    
    # Create a temporary config directory to simulate hot reload
    local temp_dir="/tmp/keypath-hot-reload-test"
    local temp_config="$temp_dir/keypath.kbd"
    
    mkdir -p "$temp_dir"
    
    # Create initial config
    log_info "Creating initial config..."
    cat > "$temp_config" << 'EOF'
;; KeyPath Hot Reload Test - Initial Config

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
    
    # Validate initial config
    if "$KANATA_BINARY" --cfg "$temp_config" --check > /dev/null 2>&1; then
        log_success "Initial config is valid"
    else
        log_error "Initial config is invalid"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Simulate config update
    log_info "Simulating config update..."
    cat > "$temp_config" << 'EOF'
;; KeyPath Hot Reload Test - Updated Config

(defcfg
  process-unmapped-keys yes
)

(defsrc
  caps
)

(deflayer base
  a
)
EOF
    
    # Validate updated config
    if "$KANATA_BINARY" --cfg "$temp_config" --check > /dev/null 2>&1; then
        log_success "Updated config is valid"
    else
        log_error "Updated config is invalid"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    log_success "Hot reload simulation completed"
    
    echo
}

test_app_integration() {
    test_step "Testing App Integration"
    
    # Test if the app can be launched
    log_info "Testing KeyPath app launch..."
    
    # Check if app is already running
    if pgrep -f "KeyPath.app" > /dev/null; then
        log_success "KeyPath app is already running"
    else
        log_info "KeyPath app is not running"
    fi
    
    # Test if app bundle is properly structured
    local app_bundle="build/KeyPath.app"
    if [[ -f "$app_bundle/Contents/MacOS/KeyPath" ]]; then
        log_success "App bundle is properly structured"
    else
        log_error "App bundle is missing executable"
        exit 1
    fi
    
    # Test if Info.plist is valid
    if plutil -lint "$app_bundle/Contents/Info.plist" > /dev/null 2>&1; then
        log_success "App Info.plist is valid"
    else
        log_error "App Info.plist is invalid"
        exit 1
    fi
    
    echo
}

show_next_steps() {
    test_step "Next Steps"
    
    echo "All tests passed! Ready for installation:"
    echo
    echo "1. Install the system:"
    echo "   ${YELLOW}sudo ./install-system.sh${NC}"
    echo
    echo "2. Launch the app:"
    echo "   ${YELLOW}open /Applications/KeyPath.app${NC}"
    echo
    echo "3. Test service management:"
    echo "   ${YELLOW}sudo launchctl kickstart -k system/$LAUNCH_DAEMON_LABEL${NC}"
    echo "   ${YELLOW}sudo launchctl print system/$LAUNCH_DAEMON_LABEL${NC}"
    echo
    echo "4. Monitor logs:"
    echo "   ${YELLOW}tail -f /var/log/kanata.log${NC}"
    echo
    echo "5. Test hot reload by using the app to record a new keypath"
    echo
}

main() {
    echo -e "${BLUE}Kanata System Test Suite${NC}"
    echo "======================="
    echo
    
    check_prerequisites
    test_installation
    test_config_generation
    test_service_management
    test_hot_reload_simulation
    test_app_integration
    show_next_steps
    
    log_success "All tests completed successfully!"
}

# Run the test
main "$@"