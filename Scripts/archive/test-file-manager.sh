#!/bin/bash
# KeyPath Test File Manager
# Provides passwordless access to file system operations for testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [test-file-manager] $1" >&2
}

# Validate path is within allowed testing directories
validate_path() {
    local path="$1"
    local allowed_paths=(
        "/usr/local/etc/kanata"
        "/var/log/keypath"
        "/Library/LaunchDaemons/com.keypath"
        "/tmp/keypath"
        "$PROJECT_ROOT"
    )
    
    local path_allowed=false
    for allowed in "${allowed_paths[@]}"; do
        if [[ "$path" == "$allowed"* ]]; then
            path_allowed=true
            break
        fi
    done
    
    if [ "$path_allowed" = false ]; then
        log "ERROR: Path not allowed for testing operations: $path"
        log "Allowed paths: ${allowed_paths[*]}"
        exit 1
    fi
}

case "$1" in
    "create-test-dirs")
        log "Creating test directories"
        
        # Kanata config directories
        sudo mkdir -p /usr/local/etc/kanata/test
        sudo chown -R $(whoami):staff /usr/local/etc/kanata/test
        sudo chmod -R 755 /usr/local/etc/kanata/test
        log "Created: /usr/local/etc/kanata/test"
        
        # Log directories
        sudo mkdir -p /var/log/keypath/test
        sudo chown -R $(whoami):staff /var/log/keypath/test
        sudo chmod -R 755 /var/log/keypath/test
        log "Created: /var/log/keypath/test"
        
        # Temp directories
        mkdir -p /tmp/keypath-test
        chmod 755 /tmp/keypath-test
        log "Created: /tmp/keypath-test"
        
        log "All test directories created successfully"
        ;;
        
    "install-test-daemon")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 install-test-daemon <plist-file>"
            exit 1
        fi
        
        PLIST_FILE="$2"
        if [ ! -f "$PLIST_FILE" ]; then
            log "ERROR: Plist file not found: $PLIST_FILE"
            exit 1
        fi
        
        # Extract service name from plist
        SERVICE_NAME=$(basename "$PLIST_FILE" .plist)
        TARGET_PATH="/Library/LaunchDaemons/$SERVICE_NAME.plist"
        
        validate_path "$TARGET_PATH"
        
        log "Installing test daemon: $SERVICE_NAME"
        sudo cp "$PLIST_FILE" "$TARGET_PATH"
        sudo chown root:wheel "$TARGET_PATH"
        sudo chmod 644 "$TARGET_PATH"
        log "Installed: $TARGET_PATH"
        ;;
        
    "remove-test-daemon")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 remove-test-daemon <service-name>"
            exit 1
        fi
        
        SERVICE_NAME="$2"
        PLIST_PATH="/Library/LaunchDaemons/$SERVICE_NAME.plist"
        
        validate_path "$PLIST_PATH"
        
        log "Removing test daemon: $SERVICE_NAME"
        if [ -f "$PLIST_PATH" ]; then
            # Unload first if loaded
            sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
            # Remove file
            sudo rm "$PLIST_PATH"
            log "Removed: $PLIST_PATH"
        else
            log "Daemon not found: $PLIST_PATH"
        fi
        ;;
        
    "backup-config")
        if [ -z "$2" ] || [ -z "$3" ]; then
            log "ERROR: Usage: $0 backup-config <source-config> <backup-name>"
            exit 1
        fi
        
        SOURCE_CONFIG="$2"
        BACKUP_NAME="$3"
        BACKUP_DIR="/tmp/keypath-test/backups"
        
        if [ ! -f "$SOURCE_CONFIG" ]; then
            log "ERROR: Source config not found: $SOURCE_CONFIG"
            exit 1
        fi
        
        mkdir -p "$BACKUP_DIR"
        BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME-$(date +%Y%m%d-%H%M%S).kbd"
        
        cp "$SOURCE_CONFIG" "$BACKUP_PATH"
        log "Config backed up to: $BACKUP_PATH"
        echo "$BACKUP_PATH"
        ;;
        
    "restore-config")
        if [ -z "$2" ] || [ -z "$3" ]; then
            log "ERROR: Usage: $0 restore-config <backup-file> <target-config>"
            exit 1
        fi
        
        BACKUP_FILE="$2"
        TARGET_CONFIG="$3"
        
        if [ ! -f "$BACKUP_FILE" ]; then
            log "ERROR: Backup file not found: $BACKUP_FILE"
            exit 1
        fi
        
        validate_path "$TARGET_CONFIG"
        
        # Create backup of current config if it exists
        if [ -f "$TARGET_CONFIG" ]; then
            CURRENT_BACKUP="${TARGET_CONFIG}.pre-restore-$(date +%Y%m%d-%H%M%S)"
            cp "$TARGET_CONFIG" "$CURRENT_BACKUP"
            log "Current config backed up to: $CURRENT_BACKUP"
        fi
        
        cp "$BACKUP_FILE" "$TARGET_CONFIG"
        log "Config restored from: $BACKUP_FILE to $TARGET_CONFIG"
        ;;
        
    "create-test-config")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 create-test-config <output-file> [mapping]"
            exit 1
        fi
        
        OUTPUT_FILE="$2"
        MAPPING="${3:-caps->esc}"
        
        log "Creating test config: $OUTPUT_FILE with mapping: $MAPPING"
        
        # Parse mapping (simple format: key1->key2)
        if [[ "$MAPPING" =~ ^([^-]+)-\>([^-]+)$ ]]; then
            INPUT_KEY="${BASH_REMATCH[1]}"
            OUTPUT_KEY="${BASH_REMATCH[2]}"
        else
            log "ERROR: Invalid mapping format. Use: key1->key2"
            exit 1
        fi
        
        cat > "$OUTPUT_FILE" << EOF
;; Generated test configuration by KeyPath
;; Input: $INPUT_KEY -> Output: $OUTPUT_KEY
;; 
;; SAFETY FEATURES:
;; - process-unmapped-keys no: Only process explicitly mapped keys
;; - danger-enable-cmd yes: Enable CMD key remapping (required for macOS)

(defcfg
  process-unmapped-keys no
  danger-enable-cmd yes
)

(defsrc
  $INPUT_KEY
)

(deflayer base
  $OUTPUT_KEY
)
EOF
        
        log "Test config created: $OUTPUT_FILE"
        ;;
        
    "cleanup-test-files")
        log "Cleaning up test files and directories"
        
        # Remove test directories
        if [ -d "/tmp/keypath-test" ]; then
            rm -rf /tmp/keypath-test
            log "Removed: /tmp/keypath-test"
        fi
        
        # Clean test configs
        find /usr/local/etc/kanata/test -name "*.kbd" -delete 2>/dev/null || true
        log "Cleaned test configs from: /usr/local/etc/kanata/test"
        
        # Clean test logs
        find /var/log/keypath/test -name "*.log" -delete 2>/dev/null || true
        log "Cleaned test logs from: /var/log/keypath/test"
        
        # Remove test daemons
        for daemon in /Library/LaunchDaemons/com.keypath.*.test.plist; do
            if [ -f "$daemon" ]; then
                SERVICE_NAME=$(basename "$daemon" .plist)
                sudo launchctl unload "$daemon" 2>/dev/null || true
                sudo rm "$daemon"
                log "Removed test daemon: $SERVICE_NAME"
            fi
        done
        
        log "Test file cleanup completed"
        ;;
        
    *)
        echo "KeyPath Test File Manager"
        echo "Usage: $0 {create-test-dirs|install-test-daemon|remove-test-daemon|backup-config|restore-config|create-test-config|cleanup-test-files} [options]"
        echo ""
        echo "Commands:"
        echo "  create-test-dirs                     Create all necessary test directories"
        echo "  install-test-daemon <plist-file>     Install a test LaunchDaemon"
        echo "  remove-test-daemon <service-name>    Remove a test LaunchDaemon"
        echo "  backup-config <source> <name>        Backup a configuration file"
        echo "  restore-config <backup> <target>     Restore a configuration from backup"
        echo "  create-test-config <file> [mapping]  Create a test Kanata config"
        echo "  cleanup-test-files                   Remove all test files and directories"
        echo ""
        echo "Examples:"
        echo "  $0 create-test-dirs"
        echo "  $0 create-test-config /tmp/test.kbd caps->esc"
        echo "  $0 backup-config ~/config.kbd test-backup"
        echo "  $0 cleanup-test-files"
        exit 1
        ;;
esac