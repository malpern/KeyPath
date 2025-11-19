#!/bin/bash

# Test KeyPath installer without actually installing
# This validates the installer configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LAUNCH_DAEMON_LABEL="com.keypath.kanata"
KANATA_CONFIG_DIR="/usr/local/etc/kanata"
KANATA_CONFIG_FILE="${KANATA_CONFIG_DIR}/keypath.kbd"
KANATA_BINARY="${KANATA_BINARY_OVERRIDE:-}"

detect_kanata_binary() {
    if [[ -n "$KANATA_BINARY" && -x "$KANATA_BINARY" ]]; then
        echo "$KANATA_BINARY"
        return
    fi

    if command -v kanata >/dev/null 2>&1; then
        echo "$(command -v kanata)"
        return
    fi

    local candidates=(
        "/opt/homebrew/bin/kanata"
        "/usr/local/bin/kanata"
        "/usr/bin/kanata"
        "$PROJECT_ROOT/External/kanata/target/release/kanata"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done

    echo ""
}

KANATA_BINARY="$(detect_kanata_binary)"

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

echo -e "${BLUE}KeyPath Installation Test${NC}"
echo "========================"
echo

# Check if Kanata is installed
log_info "Checking Kanata installation..."
if [[ -n "$KANATA_BINARY" && -x "$KANATA_BINARY" ]]; then
    log_success "Kanata found at $KANATA_BINARY"
else
    log_error "Kanata binary not found."
    echo "Set KANATA_BINARY_OVERRIDE or install Kanata (e.g. brew install kanata)."
    exit 1
fi

# Check if app bundle exists
log_info "Checking KeyPath app bundle..."
if [[ -d "build/KeyPath.app" ]]; then
    log_success "KeyPath app bundle found"
else
    log_error "KeyPath app bundle not found"
    echo "Please run ./build.sh first"
    exit 1
fi

# Test the config file generation
log_info "Testing config generation..."
temp_config="/tmp/test-keypath-config.kbd"
cat > "$temp_config" << 'EOF'
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

# Validate the config
if "$KANATA_BINARY" --cfg "$temp_config" --check; then
    log_success "Config generation test passed"
else
    log_error "Config generation test failed"
    rm -f "$temp_config"
    exit 1
fi

rm -f "$temp_config"

# Check if current config directory exists
log_info "Checking current config directory..."
if [[ -d "$KANATA_CONFIG_DIR" ]]; then
    log_success "Config directory exists"
    if [[ -f "$KANATA_CONFIG_FILE" ]]; then
        log_success "Config file exists"
        # Test the current config file
        if "$KANATA_BINARY" --cfg "$KANATA_CONFIG_FILE" --check; then
            log_success "Current config is valid"
        else
            log_warning "Current config is invalid"
        fi
    else
        log_warning "Config file does not exist"
    fi
else
    log_warning "Config directory does not exist"
fi

# Check if LaunchDaemon is already installed
log_info "Checking LaunchDaemon status..."
if launchctl list | grep -q "$LAUNCH_DAEMON_LABEL"; then
    log_warning "LaunchDaemon is already loaded"
else
    log_info "LaunchDaemon is not loaded"
fi

echo
log_success "Installation test completed successfully!"
echo
echo "Ready to install KeyPath:"
echo "  sudo ./install-system.sh install"
echo
echo "To uninstall later:"
echo "  sudo ./uninstall.sh"
echo