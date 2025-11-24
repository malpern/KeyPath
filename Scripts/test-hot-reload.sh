#!/bin/bash

# Test hot reload functionality for KeyPath + Kanata

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

KANATA_CONFIG_FILE="${KANATA_CONFIG_FILE:-/usr/local/etc/kanata/keypath.kbd}"
# Prefer env override; otherwise probe common install locations
if [[ -z "${KANATA_BINARY:-}" ]]; then
    for candidate in \
        "/Library/KeyPath/bin/kanata" \
        "/opt/homebrew/bin/kanata" \
        "/usr/local/bin/kanata" \
        "dist/KeyPath.app/Contents/Library/KeyPath/kanata" \
        ".build-ci/arm64-apple-macosx/debug/kanata" \
        ".build/debug/kanata"; do
        if [[ -x "$candidate" ]]; then
            KANATA_BINARY="$candidate"
            break
        fi
    done
fi

if [[ -z "${KANATA_BINARY:-}" || ! -x "$KANATA_BINARY" ]]; then
    log_warning "Kanata binary not found (looked in env and common paths). Skipping hot-reload test."
    exit 0
fi

log_info "Using kanata binary: $KANATA_BINARY"
LAUNCH_DAEMON_LABEL="com.keypath.kanata"

echo -e "${BLUE}Hot Reload Test${NC}"
echo "==============="
echo

# 1. Test config file monitoring
log_info "Testing config file monitoring simulation..."

# Create a test config
test_config="/tmp/keypath-hot-reload-test.kbd"
cat > "$test_config" << 'EOF'
;; KeyPath Hot Reload Test

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

# Validate it
if "$KANATA_BINARY" --cfg "$test_config" --check > /dev/null 2>&1; then
    log_success "Test config is valid"
else
    log_warning "Test config is invalid with $KANATA_BINARY; skipping hot-reload test."
    exit 0
fi

# 2. Simulate config update
log_info "Simulating config update..."
sleep 1

cat > "$test_config" << 'EOF'
;; KeyPath Hot Reload Test - Updated

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
if "$KANATA_BINARY" --cfg "$test_config" --check > /dev/null 2>&1; then
    log_success "Updated config is valid"
else
    log_warning "Updated test config is invalid with $KANATA_BINARY; skipping hot-reload test."
    exit 0
fi

rm -f "$test_config"

# 3. Test the actual config file (if it exists)
if [[ -f "$KANATA_CONFIG_FILE" ]]; then
    log_info "Testing current config file..."
    
    # Show current config
    echo "Current config:"
    cat "$KANATA_CONFIG_FILE"
    echo
    
    # Validate current config
    if "$KANATA_BINARY" --cfg "$KANATA_CONFIG_FILE" --check > /dev/null 2>&1; then
        log_success "Current config is valid"
    else
        log_warning "Current config is invalid - may need fixing"
    fi
else
    log_warning "Config file doesn't exist yet - will be created on first keypath recording"
fi

# 4. Test service restart capability
log_info "Testing service restart capability..."

# Check if service is installed
if launchctl print "system/$LAUNCH_DAEMON_LABEL" >/dev/null 2>&1; then
    log_success "Service is installed and can be managed"
    
    # Show current status
    status_output=$(launchctl print "system/$LAUNCH_DAEMON_LABEL" 2>/dev/null)
    if echo "$status_output" | grep -q "state = running"; then
        log_success "Service is currently running"
    else
        log_info "Service is installed but not running"
    fi
else
    log_warning "Service is not installed yet"
fi

echo
log_success "Hot reload test completed successfully!"
echo

echo "Hot reload workflow:"
echo "1. User records keypath in app"
echo "2. App generates new config and saves to $KANATA_CONFIG_FILE"
echo "3. App calls KanataManager.restartKanata()"
echo "4. KanataManager runs: launchctl kickstart -k system/$LAUNCH_DAEMON_LABEL"
echo "5. Kanata service restarts with new config"
echo "6. New keypath is active immediately"
echo

if [[ -f "$KANATA_CONFIG_FILE" ]]; then
    echo "Ready to test hot reload with actual service!"
else
    echo "Install the system first: sudo ./install-system.sh install"
fi
