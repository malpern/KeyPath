#!/bin/bash
# KeyPath Test Process Manager
# Provides passwordless access to process management operations for testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [test-process-manager] $1" >&2
}

# Find Kanata binary
find_kanata_binary() {
    if [ -x "/opt/homebrew/bin/kanata" ]; then
        echo "/opt/homebrew/bin/kanata"
    elif [ -x "/usr/local/bin/kanata" ]; then
        echo "/usr/local/bin/kanata"
    else
        log "ERROR: Kanata binary not found. Install with: brew install kanata"
        exit 1
    fi
}

# Validate config file
validate_config() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        log "ERROR: Config file not found: $config_file"
        exit 1
    fi
    
    # Basic validation - check if it's a Kanata config
    if ! grep -q "defcfg\|defsrc\|deflayer" "$config_file"; then
        log "WARNING: Config file may not be a valid Kanata configuration: $config_file"
    fi
}

case "$1" in
    "kill-kanata")
        log "Killing all Kanata processes"
        KILLED_COUNT=$(sudo pkill -f kanata -c 2>/dev/null || echo "0")
        if [ "$KILLED_COUNT" -gt 0 ]; then
            log "Killed $KILLED_COUNT Kanata process(es)"
            # Wait for processes to fully terminate
            sleep 1
        else
            log "No Kanata processes were running"
        fi
        ;;
        
    "kill-kanata-by-config")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 kill-kanata-by-config <config-file-path>"
            exit 1
        fi
        CONFIG_FILE="$2"
        log "Killing Kanata processes using config: $CONFIG_FILE"
        KILLED_COUNT=$(sudo pkill -f "$CONFIG_FILE" -c 2>/dev/null || echo "0")
        if [ "$KILLED_COUNT" -gt 0 ]; then
            log "Killed $KILLED_COUNT Kanata process(es) using $CONFIG_FILE"
            sleep 1
        else
            log "No Kanata processes found using config: $CONFIG_FILE"
        fi
        ;;
        
    "start-kanata")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 start-kanata <config-file>"
            exit 1
        fi
        CONFIG_FILE="$2"
        validate_config "$CONFIG_FILE"
        
        KANATA_BIN=$(find_kanata_binary)
        log "Starting Kanata with config: $CONFIG_FILE"
        log "Using binary: $KANATA_BIN"
        
        # Start Kanata in background
        sudo "$KANATA_BIN" --cfg "$CONFIG_FILE" &
        KANATA_PID=$!
        log "Started Kanata with PID: $KANATA_PID"
        
        # Give it a moment to start
        sleep 2
        
        # Verify it's still running
        if kill -0 "$KANATA_PID" 2>/dev/null; then
            log "Kanata is running successfully with PID: $KANATA_PID"
        else
            log "WARNING: Kanata may have failed to start"
            exit 1
        fi
        ;;
        
    "start-kanata-daemon")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 start-kanata-daemon <config-file>"
            exit 1
        fi
        CONFIG_FILE="$2"
        validate_config "$CONFIG_FILE"
        
        KANATA_BIN=$(find_kanata_binary)
        log "Starting Kanata as daemon with config: $CONFIG_FILE"
        
        # Start as daemon (detached)
        nohup sudo "$KANATA_BIN" --cfg "$CONFIG_FILE" > /var/log/keypath/kanata-test.log 2>&1 &
        KANATA_PID=$!
        disown
        
        log "Started Kanata daemon with PID: $KANATA_PID"
        log "Logs available at: /var/log/keypath/kanata-test.log"
        ;;
        
    "check-kanata")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 check-kanata <config-file>"
            exit 1
        fi
        CONFIG_FILE="$2"
        validate_config "$CONFIG_FILE"
        
        KANATA_BIN=$(find_kanata_binary)
        log "Validating Kanata config: $CONFIG_FILE"
        
        if sudo "$KANATA_BIN" --cfg "$CONFIG_FILE" --check; then
            log "Config validation successful: $CONFIG_FILE"
        else
            log "ERROR: Config validation failed: $CONFIG_FILE"
            exit 1
        fi
        ;;
        
    "list-kanata")
        log "Listing all Kanata processes"
        if pgrep -f kanata > /dev/null; then
            echo "Active Kanata processes:"
            ps aux | grep -E "(PID|kanata)" | grep -v grep
            echo ""
            echo "Process tree:"
            pstree -p $(pgrep -f kanata | head -1) 2>/dev/null || echo "pstree not available"
        else
            log "No Kanata processes currently running"
        fi
        ;;
        
    "cleanup-all")
        log "Performing complete Kanata cleanup"
        
        # Kill all processes
        KILLED_COUNT=$(sudo pkill -f kanata -c 2>/dev/null || echo "0")
        if [ "$KILLED_COUNT" -gt 0 ]; then
            log "Killed $KILLED_COUNT Kanata process(es)"
        fi
        
        # Wait for cleanup
        sleep 2
        
        # Verify cleanup
        if pgrep -f kanata > /dev/null; then
            log "WARNING: Some Kanata processes may still be running"
            ps aux | grep kanata | grep -v grep
        else
            log "All Kanata processes cleaned up successfully"
        fi
        ;;
        
    *)
        echo "KeyPath Test Process Manager"
        echo "Usage: $0 {kill-kanata|start-kanata|check-kanata|list-kanata|cleanup-all} [options]"
        echo ""
        echo "Commands:"
        echo "  kill-kanata                    Kill all Kanata processes"
        echo "  kill-kanata-by-config <file>   Kill Kanata processes using specific config"
        echo "  start-kanata <config-file>     Start Kanata with specified config"
        echo "  start-kanata-daemon <config>   Start Kanata as background daemon"
        echo "  check-kanata <config-file>     Validate Kanata configuration"
        echo "  list-kanata                    List all running Kanata processes"
        echo "  cleanup-all                    Kill all Kanata processes and verify cleanup"
        echo ""
        echo "Examples:"
        echo "  $0 start-kanata /tmp/test-config.kbd"
        echo "  $0 check-kanata ~/Library/Application\\ Support/KeyPath/keypath.kbd"
        echo "  $0 cleanup-all"
        exit 1
        ;;
esac