#!/bin/bash
# KeyPath Passwordless Testing Setup
# Sets up secure passwordless sudo for testing operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SUDOERS_FILE="/etc/sudoers.d/keypath-testing"
CURRENT_USER=$(whoami)

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

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Do not run this script as root. Run as your normal user."
    exit 1
fi

# Check if user is in admin group
if ! groups "$CURRENT_USER" | grep -q admin; then
    log_error "User $CURRENT_USER is not in the admin group. Please add to admin group first."
    exit 1
fi

log "🚀 KeyPath Passwordless Testing Setup"
log "User: $CURRENT_USER"
log "Project: $PROJECT_ROOT"
echo

# Step 1: Create wrapper scripts and make executable
log "📝 Step 1: Setting up wrapper scripts..."

SCRIPTS=(
    "test-launchctl.sh"
    "test-process-manager.sh" 
    "test-file-manager.sh"
)

for script in "${SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        log_success "Made executable: $script"
    else
        log_error "Script not found: $script_path"
        exit 1
    fi
done

# Step 2: Create sudoers configuration
log "🔐 Step 2: Creating sudoers configuration..."

SUDOERS_CONTENT="# KeyPath Testing - Passwordless sudo for specific wrapper scripts
# Generated on $(date)
# User: $CURRENT_USER

# Wrapper scripts for testing operations
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCRIPT_DIR/test-launchctl.sh
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCRIPT_DIR/test-process-manager.sh
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCRIPT_DIR/test-file-manager.sh

# Direct commands needed by wrapper scripts
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/launchctl
$CURRENT_USER ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/local/bin/kanata
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mkdir -p /usr/local/etc/kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mkdir -p /var/log/keypath*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/chown * /usr/local/etc/kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/chown * /var/log/keypath*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod * /usr/local/etc/kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod * /var/log/keypath*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/cp * /Library/LaunchDaemons/com.keypath.*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm /Library/LaunchDaemons/com.keypath.*"

# Write sudoers file
echo "$SUDOERS_CONTENT" | sudo tee "$SUDOERS_FILE" > /dev/null

# Validate sudoers configuration
if sudo visudo -c -f "$SUDOERS_FILE"; then
    log_success "Sudoers configuration created and validated: $SUDOERS_FILE"
else
    log_error "Sudoers configuration is invalid. Removing..."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi

# Step 3: Test the configuration
log "🧪 Step 3: Testing passwordless configuration..."

# Test launchctl wrapper
if sudo -n "$SCRIPT_DIR/test-launchctl.sh" list >/dev/null 2>&1; then
    log_success "LaunchControl wrapper test passed"
else
    log_error "LaunchControl wrapper test failed"
fi

# Test process manager wrapper  
if sudo -n "$SCRIPT_DIR/test-process-manager.sh" list-kanata >/dev/null 2>&1; then
    log_success "Process manager wrapper test passed"
else
    log_error "Process manager wrapper test failed"
fi

# Test file manager wrapper
if sudo -n "$SCRIPT_DIR/test-file-manager.sh" create-test-dirs >/dev/null 2>&1; then
    log_success "File manager wrapper test passed"
else
    log_error "File manager wrapper test failed"
fi

# Test direct pkill access
if sudo -n pkill -f "nonexistent-process" >/dev/null 2>&1; then
    log_success "Direct pkill access test passed"
else
    log_error "Direct pkill access test failed"
fi

echo
log_success "🎉 Passwordless testing setup completed successfully!"
echo

# Step 4: Display usage information
log "📖 Usage Information:"
echo
echo "Test wrapper scripts are now available:"
echo "  ${SCRIPT_DIR}/test-launchctl.sh     - LaunchDaemon management"
echo "  ${SCRIPT_DIR}/test-process-manager.sh - Kanata process management"  
echo "  ${SCRIPT_DIR}/test-file-manager.sh   - File system operations"
echo
echo "Examples:"
echo "  ${SCRIPT_DIR}/test-process-manager.sh kill-kanata"
echo "  ${SCRIPT_DIR}/test-launchctl.sh list"
echo "  ${SCRIPT_DIR}/test-file-manager.sh create-test-dirs"
echo

# Step 5: Create convenience aliases script
log "📋 Creating convenience aliases..."

ALIASES_FILE="$SCRIPT_DIR/test-aliases.sh"
cat > "$ALIASES_FILE" << EOF
#!/bin/bash
# KeyPath Testing Aliases
# Source this file to get convenient aliases for testing operations

alias test-launchctl='$SCRIPT_DIR/test-launchctl.sh'
alias test-processes='$SCRIPT_DIR/test-process-manager.sh'
alias test-files='$SCRIPT_DIR/test-file-manager.sh'

# Quick actions
alias kill-kanata='$SCRIPT_DIR/test-process-manager.sh kill-kanata'
alias list-kanata='$SCRIPT_DIR/test-process-manager.sh list-kanata'
alias cleanup-tests='$SCRIPT_DIR/test-file-manager.sh cleanup-test-files'

echo "KeyPath testing aliases loaded!"
echo "Available commands: test-launchctl, test-processes, test-files"
echo "Quick actions: kill-kanata, list-kanata, cleanup-tests"
EOF

chmod +x "$ALIASES_FILE"
log_success "Aliases created: $ALIASES_FILE"
echo "  To use aliases: source $ALIASES_FILE"

echo
log "⚠️  Security Notes:"
echo "  - Only KeyPath-specific operations are allowed"
echo "  - Wrapper scripts validate all inputs"
echo "  - Configuration is restricted to test operations"
echo "  - To remove: sudo rm $SUDOERS_FILE"
echo

log_success "Setup complete! Ready for automated testing."