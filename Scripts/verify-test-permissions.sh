#!/bin/bash
# KeyPath Test Permissions Verifier
# Verifies all required permissions are in place for automated testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}"
}

# Track overall success
OVERALL_SUCCESS=true

log "🔍 KeyPath Test Permissions Verification"
echo

# 1. Check sudoers configuration
log "Checking sudoers configuration..."
SUDOERS_FILE="/etc/sudoers.d/keypath-testing"

if [ -f "$SUDOERS_FILE" ]; then
    if sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
        log_success "Sudoers configuration is valid"
    else
        log_error "Sudoers configuration is invalid"
        OVERALL_SUCCESS=false
    fi
else
    log_error "Sudoers configuration not found: $SUDOERS_FILE"
    log "  Run: ./scripts/setup-passwordless-testing.sh"
    OVERALL_SUCCESS=false
fi

# 2. Test passwordless sudo access
log "Testing passwordless sudo access..."

# Test pkill
if sudo -n pkill -f "nonexistent-test-process" >/dev/null 2>&1; then
    log_success "pkill access works"
else
    log_error "pkill access failed - check sudoers configuration"
    OVERALL_SUCCESS=false
fi

# Test launchctl
if sudo -n launchctl list >/dev/null 2>&1; then
    log_success "launchctl access works"
else
    log_error "launchctl access failed - check sudoers configuration"
    OVERALL_SUCCESS=false
fi

# Test wrapper scripts
log "Testing wrapper scripts..."

WRAPPER_SCRIPTS=(
    "test-launchctl.sh"
    "test-process-manager.sh"
    "test-file-manager.sh"
)

for script in "${WRAPPER_SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        if sudo -n "$script_path" >/dev/null 2>&1; then
            log_success "$script is executable and accessible"
        else
            log_warning "$script exists but may have permission issues"
        fi
    else
        log_error "$script not found or not executable"
        OVERALL_SUCCESS=false
    fi
done

# 3. Check Kanata binary
log "Checking Kanata binary..."

KANATA_PATHS=(
    "/opt/homebrew/bin/kanata"
    "/usr/local/bin/kanata"
)

KANATA_FOUND=false
for kanata_path in "${KANATA_PATHS[@]}"; do
    if [ -x "$kanata_path" ]; then
        log_success "Kanata binary found: $kanata_path"
        KANATA_FOUND=true
        
        # Test version
        if "$kanata_path" --version >/dev/null 2>&1; then
            VERSION=$("$kanata_path" --version 2>&1 | head -1)
            log_success "Kanata version: $VERSION"
        else
            log_warning "Kanata binary exists but version check failed"
        fi
        break
    fi
done

if [ "$KANATA_FOUND" = false ]; then
    log_error "Kanata binary not found. Install with: brew install kanata"
    OVERALL_SUCCESS=false
fi

# 4. Check macOS permissions
log "Checking macOS system permissions..."

# Function to check if a binary has a specific permission
check_tcc_permission() {
    local binary_path="$1"
    local permission_type="$2"
    local service_name=""
    
    case "$permission_type" in
        "accessibility")
            service_name="kTCCServiceAccessibility"
            ;;
        "input_monitoring")
            service_name="kTCCServiceListenEvent"
            ;;
        *)
            log_error "Unknown permission type: $permission_type"
            return 1
            ;;
    esac
    
    # Query TCC database (this is a simplified check)
    if sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT service FROM access WHERE service='$service_name' AND client='$binary_path' AND allowed=1;" 2>/dev/null | grep -q "$service_name"; then
        return 0
    else
        return 1
    fi
}

# Check permissions for common test runners
TEST_BINARIES=(
    "/Applications/Xcode.app/Contents/MacOS/Xcode"
    "/Applications/Terminal.app/Contents/MacOS/Terminal"
    "/usr/bin/swift"
)

log "Checking accessibility permissions..."
ACCESSIBILITY_OK=false
for binary in "${TEST_BINARIES[@]}"; do
    if [ -f "$binary" ]; then
        # Use a different approach - check if we can use accessibility features
        if osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
            log_success "Accessibility permission appears to be granted"
            ACCESSIBILITY_OK=true
            break
        fi
    fi
done

if [ "$ACCESSIBILITY_OK" = false ]; then
    log_warning "Accessibility permission may not be granted"
    log "  Grant in: System Settings > Privacy & Security > Accessibility"
    log "  Add: Terminal.app, Xcode.app, or your test runner"
fi

# Check Input Monitoring permission for Kanata
log "Checking Input Monitoring permissions..."
INPUT_MONITORING_OK=false

# Simple test - try to access input devices (this may not work in all environments)
if [ "$KANATA_FOUND" = true ]; then
    # Create a minimal test config
    TEST_CONFIG="/tmp/keypath-permission-test.kbd"
    cat > "$TEST_CONFIG" << EOF
(defcfg
  process-unmapped-keys no
  danger-enable-cmd yes
)
(defsrc caps)
(deflayer base esc)
EOF
    
    # Test if Kanata can validate the config (this requires some permissions)
    for kanata_path in "${KANATA_PATHS[@]}"; do
        if [ -x "$kanata_path" ]; then
            if sudo -n "$kanata_path" --cfg "$TEST_CONFIG" --check >/dev/null 2>&1; then
                log_success "Kanata can validate configs (basic permissions OK)"
                INPUT_MONITORING_OK=true
            else
                log_warning "Kanata config validation failed - may need Input Monitoring permission"
                log "  Grant in: System Settings > Privacy & Security > Input Monitoring"
                log "  Add: $kanata_path"
            fi
            break
        fi
    done
    
    # Cleanup
    rm -f "$TEST_CONFIG"
fi

# 5. Check test directories
log "Checking test directories..."

TEST_DIRS=(
    "/usr/local/etc/kanata"
    "/var/log/keypath"
    "/tmp/keypath-test"
)

for dir in "${TEST_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        if [ -w "$dir" ]; then
            log_success "Test directory writable: $dir"
        else
            log_warning "Test directory not writable: $dir"
            log "  Run: ./scripts/test-file-manager.sh create-test-dirs"
        fi
    else
        log_warning "Test directory missing: $dir"
        log "  Run: ./scripts/test-file-manager.sh create-test-dirs"
    fi
done

# 6. Final summary
echo
log "📋 Permission Verification Summary:"

if [ "$OVERALL_SUCCESS" = true ]; then
    log_success "🎉 All critical permissions are configured correctly!"
    log_success "Ready for automated testing"
    echo
    log "Next steps:"
    log "  1. Run tests: swift test"
    log "  2. Use wrapper scripts: ./scripts/test-*.sh"
    log "  3. Set up CI/CD with these permissions"
    exit 0
else
    log_error "❌ Some permissions are missing or misconfigured"
    echo
    log "Required actions:"
    log "  1. Run: ./scripts/setup-passwordless-testing.sh"
    log "  2. Grant macOS permissions in System Settings > Privacy & Security:"
    log "     - Accessibility: Add Terminal.app, Xcode.app"
    log "     - Input Monitoring: Add Kanata binary, Terminal.app"
    log "  3. Run this verification script again"
    exit 1
fi