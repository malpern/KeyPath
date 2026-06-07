#!/usr/bin/env bash

# Cross-worktree lock for scripts that mutate /Applications/KeyPath.app.
# A worktree-local build lock is not enough: another checkout can still replace
# mapped app binaries and trigger macOS CODESIGNING / Invalid Page kills.

KEYPATH_DEPLOY_LOCK_DIR="${KEYPATH_DEPLOY_LOCK_DIR:-/tmp/keypath-deploy.lock}"
KEYPATH_DEPLOY_LOCK_ACQUIRED=0

keypath_deploy_lock_pid() {
    local owner_file="$KEYPATH_DEPLOY_LOCK_DIR/owner"
    [[ -f "$owner_file" ]] || return 1
    awk -F= '/^pid=/ { print $2; exit }' "$owner_file" 2>/dev/null
}

keypath_deploy_lock_is_stale() {
    local lock_pid
    lock_pid="$(keypath_deploy_lock_pid || true)"
    [[ -n "$lock_pid" ]] || return 0
    ! kill -0 "$lock_pid" 2>/dev/null
}

keypath_acquire_deploy_lock() {
    local label="${1:-KeyPath deploy}"
    local timeout_seconds="${2:-0}"
    local start_seconds
    start_seconds="$(date +%s)"

    while ! mkdir "$KEYPATH_DEPLOY_LOCK_DIR" 2>/dev/null; do
        if keypath_deploy_lock_is_stale; then
            echo "Removing stale KeyPath deploy lock: $KEYPATH_DEPLOY_LOCK_DIR"
            rm -rf "$KEYPATH_DEPLOY_LOCK_DIR"
            continue
        fi

        local owner=""
        if [[ -f "$KEYPATH_DEPLOY_LOCK_DIR/owner" ]]; then
            owner="$(tr '\n' ' ' < "$KEYPATH_DEPLOY_LOCK_DIR/owner")"
        fi

        if [[ "$timeout_seconds" == "0" ]]; then
            echo "Another KeyPath deploy is already in progress. Skipping this deploy."
            [[ -n "$owner" ]] && echo "Lock owner: $owner"
            return 1
        fi

        local now_seconds
        now_seconds="$(date +%s)"
        if (( now_seconds - start_seconds >= timeout_seconds )); then
            echo "Timed out waiting for KeyPath deploy lock: $KEYPATH_DEPLOY_LOCK_DIR" >&2
            [[ -n "$owner" ]] && echo "Lock owner: $owner" >&2
            return 1
        fi

        sleep 1
    done

    {
        echo "pid=$$"
        echo "label=$label"
        echo "cwd=$(pwd)"
        echo "started=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$KEYPATH_DEPLOY_LOCK_DIR/owner"
    KEYPATH_DEPLOY_LOCK_ACQUIRED=1
    return 0
}

keypath_release_deploy_lock() {
    [[ "$KEYPATH_DEPLOY_LOCK_ACQUIRED" == "1" ]] || return 0
    local lock_pid
    lock_pid="$(keypath_deploy_lock_pid || true)"
    if [[ "$lock_pid" == "$$" ]]; then
        rm -rf "$KEYPATH_DEPLOY_LOCK_DIR"
    fi
    KEYPATH_DEPLOY_LOCK_ACQUIRED=0
}
