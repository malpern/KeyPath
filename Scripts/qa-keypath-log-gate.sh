#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/KeyPath.app}"
CLI="${KEYPATH_CLI:-$APP_PATH/Contents/MacOS/keypath-cli}"
LOG_LINES="${KEYPATH_QA_LOG_LINES:-500}"
LOG_LAST="${KEYPATH_QA_LOG_LAST:-20m}"
SINCE_EPOCH="${KEYPATH_QA_SINCE_EPOCH:-}"
OUTPUT_DIR="${KEYPATH_QA_LOG_OUTPUT_DIR:-}"

TMP_DIR="$(mktemp -d)"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$TMP_DIR/logs"
fi
mkdir -p "$OUTPUT_DIR"

cleanup() {
  local status=$?
  if [[ "${KEYPATH_QA_KEEP_LOGS:-0}" == "1" || "$status" != "0" ]]; then
    echo "Keeping captured logs in $OUTPUT_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

capture_file_tail() {
  local source_path="$1"
  local output_name="$2"
  local destination="$OUTPUT_DIR/$output_name"

  if [[ -r "$source_path" ]]; then
    tail -n "$LOG_LINES" "$source_path" >"$destination"
  else
    : >"$destination"
    echo "# Missing or unreadable: $source_path" >>"$destination"
  fi
}

capture_command() {
  local output_name="$1"
  shift
  local destination="$OUTPUT_DIR/$output_name"

  if "$@" >"$destination" 2>&1; then
    return 0
  fi
  echo "# Command failed: $*" >>"$destination"
}

capture_file_tail "$HOME/Library/Logs/KeyPath/keypath-debug.log" "keypath-debug.log"
capture_file_tail "/var/log/com.keypath.kanata.stdout.log" "kanata-stdout.log"
capture_file_tail "/var/log/com.keypath.kanata.stderr.log" "kanata-stderr.log"

if [[ -x "$CLI" ]]; then
  capture_command "keypath-cli-service-logs.log" "$CLI" service logs --lines "$LOG_LINES" --no-json --quiet
else
  echo "# Bundled CLI missing or not executable: $CLI" >"$OUTPUT_DIR/keypath-cli-service-logs.log"
fi

log show \
  --last "$LOG_LAST" \
  --style compact \
  --predicate 'subsystem CONTAINS[c] "com.keypath" OR process == "KeyPath" OR process == "keypath-cli" OR process CONTAINS[c] "kanata"' \
  >"$OUTPUT_DIR/unified.log" 2>"$OUTPUT_DIR/unified-log-errors.log" || true

python3 - "$OUTPUT_DIR" "$SINCE_EPOCH" <<'PY'
import datetime as dt
import pathlib
import re
import sys

output_dir = pathlib.Path(sys.argv[1])
since_epoch = sys.argv[2].strip()
since = None
if since_epoch:
    try:
        since = dt.datetime.fromtimestamp(float(since_epoch))
    except ValueError:
        print(f"error: invalid KEYPATH_QA_SINCE_EPOCH={since_epoch!r}", file=sys.stderr)
        sys.exit(2)

high_signal_patterns = [
    ("config validation failure", re.compile(r"config(uration)? validation (failed|failure)|validation failed", re.I)),
    ("kanata parse/check error", re.compile(r"\[ERROR\]|parse error|kanata.*(parse|check).*fail|unknown key|invalid.*def(src|layer|alias|chords?)", re.I)),
    ("stale daemon diagnosis", re.compile(r"stale.*daemon|daemon.*stale|SMAppService.*enabled.*(cannot|can't|failed).*run", re.I)),
    ("helper routing failure", re.compile(r"helper.*(routing|route|xpc|ipc).*(fail|error|unreachable|reject|fallback)|helper.*fallback", re.I)),
    ("reload failure", re.compile(r"reload (failed|failure)|reload.*timed out|config was written but kanata reload failed", re.I)),
    ("watchdog or timeout", re.compile(r"watchdog.*(fired|expired|failed|failure|timeout)|timed out|timeout waiting|readiness timeout", re.I)),
    ("crash loop", re.compile(r"crash loop|crashloop|exited abnormally|uncaught exception|fatal error", re.I)),
    ("overlay label error", re.compile(r"overlay.*(label|keycap|mapping).*(failed|error|unknown|missing)|failed.*overlay.*label", re.I)),
]

# Keep allowlists narrow and documented. These are expected during ordinary
# startup or when a newer validation request supersedes an older one.
allowlist = [
    ("validation debounce cancellation", re.compile(r"Validation cancelled \(task superseded\)", re.I)),
    ("empty optional store", re.compile(r"File does not exist, returning \[\]", re.I)),
    ("optional log absence", re.compile(r"No log entries found|Missing or unreadable:", re.I)),
    ("log command capture failure", re.compile(r"Command failed: .* service logs", re.I)),
]

timestamp_pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]")
time_only_pattern = re.compile(r"^(\d{2}:\d{2}:\d{2})(?:\.\d+)?\s")

def line_is_after_since(line: str, source_name: str) -> bool:
    if since is None:
        return True
    match = timestamp_pattern.match(line)
    if match:
        try:
            return dt.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S.%f") >= since
        except ValueError:
            return True

    match = time_only_pattern.match(line)
    if match:
        try:
            line_time = dt.datetime.strptime(match.group(1), "%H:%M:%S").time()
            line_datetime = dt.datetime.combine(since.date(), line_time)
            if line_datetime > dt.datetime.now() + dt.timedelta(minutes=5):
                return False
            return line_datetime >= since.replace(microsecond=0)
        except ValueError:
            return True

    if source_name == "unified.log":
        return True
    return False

findings = []
for path in sorted(output_dir.glob("*.log")):
    if path.name == "unified-log-errors.log":
        continue
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError as error:
        findings.append(("log read failure", path.name, f"could not read log: {error}"))
        continue

    for line in lines:
        if not line.strip() or not line_is_after_since(line, path.name):
            continue
        if any(pattern.search(line) for _, pattern in allowlist):
            continue
        for label, pattern in high_signal_patterns:
            if pattern.search(line):
                findings.append((label, path.name, line.strip()))
                break

if findings:
    print("KeyPath release QA log gate failed.")
    print(f"Captured logs: {output_dir}")
    for label, source, line in findings[:80]:
        print(f"- [{label}] {source}: {line}")
    if len(findings) > 80:
        print(f"... {len(findings) - 80} additional finding(s) omitted")
    sys.exit(1)

print("KeyPath release QA log gate passed.")
print(f"Captured logs: {output_dir}")
PY
