#!/bin/bash
# KeyPath Test LaunchControl Wrapper
# Provides passwordless access to launchctl operations for testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [test-launchctl] $1" >&2
}

# Validate service name to prevent abuse
validate_service_name() {
    local service="$1"
    if [[ ! "$service" =~ ^com\.keypath\.(kanata|test) ]]; then
        log "ERROR: Invalid service name. Only com.keypath.* services allowed: $service"
        exit 1
    fi
}

case "$1" in
    "load")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 load <plist-path>"
            exit 1
        fi
        PLIST_PATH="$2"
        if [ ! -f "$PLIST_PATH" ]; then
            log "ERROR: LaunchDaemon plist not found: $PLIST_PATH"
            exit 1
        fi
        log "Loading LaunchDaemon: $PLIST_PATH"
        sudo launchctl load "$PLIST_PATH"
        log "Successfully loaded: $PLIST_PATH"
        ;;
        
    "unload")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 unload <plist-path-or-service-name>"
            exit 1
        fi
        SERVICE="$2"
        if [[ "$SERVICE" == *.plist ]]; then
            log "Unloading LaunchDaemon: $SERVICE"
            sudo launchctl unload "$SERVICE" 2>/dev/null || true
        else
            validate_service_name "$SERVICE"
            log "Unloading service: $SERVICE"
            sudo launchctl unload -w "/Library/LaunchDaemons/${SERVICE}.plist" 2>/dev/null || true
        fi
        log "Successfully unloaded: $SERVICE"
        ;;
        
    "kickstart")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 kickstart <service-name>"
            exit 1
        fi
        SERVICE="$2"
        validate_service_name "$SERVICE"
        log "Kickstarting service: $SERVICE"
        sudo launchctl kickstart -k "system/$SERVICE" 2>/dev/null || true
        log "Successfully kickstarted: $SERVICE"
        ;;
        
    "kill")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 kill <service-name>"
            exit 1
        fi
        SERVICE="$2"
        validate_service_name "$SERVICE"
        log "Killing service: $SERVICE"
        sudo launchctl kill TERM "system/$SERVICE" 2>/dev/null || true
        log "Kill signal sent to: $SERVICE"
        ;;
        
    "print")
        if [ -z "$2" ]; then
            log "ERROR: Usage: $0 print <service-name>"
            exit 1
        fi
        SERVICE="$2"
        validate_service_name "$SERVICE"
        log "Getting info for service: $SERVICE"
        sudo launchctl print "system/$SERVICE"
        ;;
        
    "list")
        log "Listing KeyPath services"
        sudo launchctl list | grep -E "(com\.keypath|PID.*Label)" || echo "No KeyPath services found"
        ;;
        
    *)
        echo "KeyPath Test LaunchControl Wrapper"
        echo "Usage: $0 {load|unload|kickstart|kill|print|list} [options]"
        echo ""
        echo "Commands:"
        echo "  load <plist-path>        Load a LaunchDaemon from plist file"
        echo "  unload <plist-or-name>   Unload a LaunchDaemon"
        echo "  kickstart <service-name> Restart a service"
        echo "  kill <service-name>      Send TERM signal to service"
        echo "  print <service-name>     Show service information"
        echo "  list                     List all KeyPath services"
        echo ""
        echo "Note: Only com.keypath.* services are allowed for security"
        exit 1
        ;;
esac