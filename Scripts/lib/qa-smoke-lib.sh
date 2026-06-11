#!/usr/bin/env bash
# Shared helpers for the qa-*-smoke.sh release-readiness scripts.
#
# Usage (from a script in Scripts/):
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/qa-smoke-lib.sh"
#   smoke_init
#   ... mutate $COLLECTIONS_JSON, call apply_config / show_config, assert_* ...
#
# smoke_init backs up the user's real KeyPath config via the installed CLI and
# registers an EXIT trap that restores it (success or failure), so these
# scripts are safe to run on a real machine.

CLI="${KEYPATH_CLI:-/Applications/KeyPath.app/Contents/MacOS/keypath-cli}"
CONFIG_DIR="${KEYPATH_CONFIG_DIR:-$HOME/.config/keypath}"
COLLECTIONS_JSON="$CONFIG_DIR/RuleCollections.json"
TMP_DIR=""
BACKUP_PATH=""

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "error: required file not found: $1" >&2
    exit 1
  fi
}

smoke_cleanup() {
  local status=$?
  if [[ -n "$BACKUP_PATH" ]]; then
    "$CLI" config restore --json --quiet "$BACKUP_PATH" --reload >/dev/null || {
      echo "warning: failed to restore KeyPath config from $BACKUP_PATH" >&2
    }
  fi
  [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  exit "$status"
}

smoke_init() {
  require_file "$CLI"
  require_file "$COLLECTIONS_JSON"
  TMP_DIR="$(mktemp -d)"
  trap smoke_cleanup EXIT
  local backup_json
  backup_json="$("$CLI" config backup --json --quiet --output "$TMP_DIR/keypath-config-backup")"
  BACKUP_PATH="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["data"]["backupPath"])' <<< "$backup_json")"
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "error: $label did not contain expected snippet:" >&2
    echo "  $needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "error: $label unexpectedly contained snippet:" >&2
    echo "  $needle" >&2
    exit 1
  fi
}

# `config apply` validates the generated config with the bundled kanata before
# applying, so a successful apply doubles as a kanata syntax check.
apply_config() {
  "$CLI" config apply --json --quiet >/dev/null
}

show_config() {
  "$CLI" config show --no-json --quiet
}
