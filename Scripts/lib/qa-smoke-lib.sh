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

# Restore the user's config and VERIFY the restore actually round-tripped.
# A restore failure or manifest mismatch escalates to a non-zero exit even if
# the test assertions passed — a damaged user config must never hide behind a
# PASS (that is exactly how #881 went unnoticed on its first run).
smoke_cleanup() {
  local status=$?
  if [[ -n "$BACKUP_PATH" ]]; then
    if ! "$CLI" config restore --json --quiet "$BACKUP_PATH" --reload >/dev/null; then
      echo "ERROR: failed to restore KeyPath config from $BACKUP_PATH" >&2
      echo "ERROR: your config may be modified — inspect $CONFIG_DIR against $BACKUP_PATH" >&2
      status=70
    elif ! verify_restore_manifest; then
      status=70
    fi
  fi
  if [[ "$status" -eq 0 && -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  elif [[ -n "$TMP_DIR" ]]; then
    echo "note: leaving $TMP_DIR in place for forensics (contains the config backup)" >&2
  fi
  exit "$status"
}

# Every item in the backup must exist in the live config dir after restore.
verify_restore_manifest() {
  local missing=0 name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ ! -e "$CONFIG_DIR/$name" ]]; then
      echo "ERROR: restore manifest mismatch — '$name' in backup but missing from $CONFIG_DIR" >&2
      missing=1
    fi
  done < <(/bin/ls -A "$BACKUP_PATH" 2>/dev/null)
  return "$missing"
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
