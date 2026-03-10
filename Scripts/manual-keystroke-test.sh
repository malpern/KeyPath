#!/usr/bin/env bash
# Manual keystroke fidelity test — exercises the REAL HID path through Kanata.
#
# Unlike the automated test (which uses osascript and bypasses Kanata),
# this requires you to physically type on your keyboard so Kanata actually
# processes every keystroke through its HID intercept → engine → virtual HID pipeline.
#
# The script:
#   1. Shows a reference passage in the terminal
#   2. Opens a blank Zed scratch file for you to type into
#   3. Starts CPU/memory/disk stress (configurable preset)
#   4. Optionally forces a reconnect/restart mid-typing
#   5. Monitors KeyPath log for duplicate detection and investigation session markers
#   6. When you're done, captures Zed content and diffs against reference
#   7. Writes an artifact bundle focused on suspicious additions
#
# Usage:
#   ./Scripts/manual-keystroke-test.sh [preset]
#   ./Scripts/manual-keystroke-test.sh --preset compile
#   ./Scripts/manual-keystroke-test.sh --preset high --reconnect-after 15

set -euo pipefail

PRESET="high"
RECONNECT_AFTER=0
RECONNECT_COMMAND='sudo -n launchctl kickstart -k system/com.keypath.kanata'

usage() {
    cat <<'USAGE'
Usage: ./Scripts/manual-keystroke-test.sh [preset] [options]

Presets:
  baseline   No extra load
  medium     Swift build loop + 2 CPU hogs
  high       Swift build loop + 6 CPU hogs
  compile    Repeated nontrivial Swift rebuilds (realistic compile pressure)
  vicious    Compile loop + most cores + disk I/O + memory pressure

Options:
  --preset <name>             Explicit preset selection
  --reconnect-after <secs>    Force a Kanata restart after N seconds of typing
  --reconnect-command <cmd>   Command used for reconnect forcing
  -h, --help                  Show help

Examples:
  ./Scripts/manual-keystroke-test.sh high
  ./Scripts/manual-keystroke-test.sh --preset compile
  ./Scripts/manual-keystroke-test.sh --preset high --reconnect-after 12
USAGE
}

if [[ $# -gt 0 ]] && [[ "${1:-}" != --* ]]; then
    PRESET="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)
            PRESET="${2:-}"
            shift 2
            ;;
        --reconnect-after)
            RECONNECT_AFTER="${2:-}"
            shift 2
            ;;
        --reconnect-command)
            RECONNECT_COMMAND="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_DIR="${TMPDIR:-/tmp}/keypath-manual-test-$TIMESTAMP"
mkdir -p "$TEST_DIR"

LOG_FILE="$HOME/Library/Logs/KeyPath/keypath-debug.log"
KANATA_STDOUT_LOG="/var/log/com.keypath.kanata.stdout.log"
KANATA_STDERR_LOG="/var/log/com.keypath.kanata.stderr.log"
SCRATCH_FILE="$TEST_DIR/typed-output.txt"
REFERENCE_FILE="$TEST_DIR/reference.txt"
ANALYSIS_FILE="$TEST_DIR/analysis.txt"
LOG_SLICE_FILE="$TEST_DIR/log-slice.txt"
SESSION_MARKERS_FILE="$TEST_DIR/session-markers.txt"
RECONNECT_EVENTS_FILE="$TEST_DIR/reconnect-events.txt"
UNMATCHED_AUTOREPEAT_FILE="$TEST_DIR/unmatched-autorepeat-events.txt"
MONITOR_CAPTURE_FILE="$TEST_DIR/monitored-log.txt"
KANATA_STDOUT_CAPTURE_FILE="$TEST_DIR/kanata-stdout.log"
KANATA_STDERR_CAPTURE_FILE="$TEST_DIR/kanata-stderr.log"
KANATA_OUTPUT_MARKERS_FILE="$TEST_DIR/kanata-output-markers.txt"
SUSPICIOUS_SUMMARY_FILE="$TEST_DIR/suspicious-additions-summary.txt"
REPEATED_CHAR_FILE="$TEST_DIR/repeated-char-windows.txt"
REPEATED_WORD_FILE="$TEST_DIR/repeated-word-windows.txt"
ADDITION_WINDOWS_FILE="$TEST_DIR/addition-windows.txt"
VERDICT_FILE="$TEST_DIR/verdict.txt"

if ! [[ "$RECONNECT_AFTER" =~ ^[0-9]+$ ]]; then
    echo "Error: --reconnect-after must be a non-negative integer" >&2
    exit 1
fi

if [[ ! "$PRESET" =~ ^(baseline|medium|high|compile|vicious)$ ]]; then
    echo "Error: preset must be baseline, medium, high, compile, or vicious" >&2
    exit 1
fi

# --- Reference passage ---
cat > "$REFERENCE_FILE" << 'PASSAGE'
The little kitten sat still on the tall wooden stool. It blinked sleepily, then suddenly leapt off and dashed across the room. All the coffee cups rattled as it skidded past the bookshelf.

Programming requires attention to small details. A missing semicolon, an off-by-one error, or a forgotten null check can cause hours of debugging. The best programmers are not the fastest typists but the most careful thinkers.

func processEvent(_ event: KeyEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    let mapped = keymap[event.keyCode] ?? event.keyCode
    if modifiers.contains(.shift) {
        return handleShifted(mapped, at: event.timestamp)
    }
    return handleNormal(mapped, at: event.timestamp)
}

The 15 bees buzzed happily around 33 yellow flowers. She added 2 eggs, 1.5 cups of flour, and 0.75 teaspoons of baking soda. The recipe called for 350 degrees for 25 minutes.

Success is not final, failure is not fatal: it is the courage to continue that counts. Every accomplishment starts with the decision to try. The difference between a successful person and others is not a lack of strength, not a lack of knowledge, but rather a lack of will.
PASSAGE

REFERENCE_CHARS=$(wc -c < "$REFERENCE_FILE" | tr -d ' ')
REFERENCE_WORDS=$(wc -w < "$REFERENCE_FILE" | tr -d ' ')

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       KeyPath Manual Keystroke Fidelity Test                ║"
echo "║       (exercises REAL HID path through Kanata)              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Preset: $(printf '%-49s' "$PRESET")║"
echo "║  Reference: ${REFERENCE_WORDS} words, ${REFERENCE_CHARS} chars                          ║"
echo "║  Output: $TEST_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

errors=()
if ! pgrep -iq kanata 2>/dev/null; then
    errors+=("Kanata is not running. Launch KeyPath first.")
fi
if [[ ! -f "$LOG_FILE" ]]; then
    errors+=("KeyPath log not found: $LOG_FILE")
fi

if [[ ${#errors[@]} -gt 0 ]]; then
    echo "PREFLIGHT FAILED:"
    for e in "${errors[@]}"; do
        echo "  ✗ $e"
    done
    exit 1
fi

KANATA_PID=$(pgrep -i kanata | head -1)
echo "  ✓ Kanata running (PID $KANATA_PID)"
echo "  ✓ KeyPath log exists"
echo "  ✓ Investigation markers default to debug mode; set KEYPATH_DUPLICATE_INVESTIGATION=0 to suppress"
echo

bg_pids=()
cleanup_load() {
    for pid in "${bg_pids[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    pkill -f "dd if=/dev/zero of=.*manual-test" 2>/dev/null || true
}
trap cleanup_load EXIT

start_compile_loop() {
    (
        cd "$PROJECT_ROOT"
        while true; do
            swift build -c debug >/dev/null 2>&1 || true
        done
    ) &
    bg_pids+=("$!")
}

start_realistic_compile_loop() {
    (
        cd "$PROJECT_ROOT"
        while true; do
            swift package clean >/dev/null 2>&1 || true
            swift build -c debug --build-tests >/dev/null 2>&1 || true
        done
    ) &
    bg_pids+=("$!")
}

start_cpu_hogs() {
    local count=$1
    local i
    for (( i=0; i<count; i++ )); do
        yes >/dev/null &
        bg_pids+=("$!")
    done
}

NUM_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)

case "$PRESET" in
    baseline)
        echo "  No CPU load (baseline)"
        ;;
    medium)
        start_compile_loop
        start_cpu_hogs 2
        echo "  CPU load: medium (compile loop + 2 hogs)"
        ;;
    high)
        start_compile_loop
        start_cpu_hogs 6
        echo "  CPU load: high (compile loop + 6 hogs)"
        ;;
    compile)
        start_realistic_compile_loop
        echo "  CPU load: compile (repeated clean + build-tests rebuilds, no synthetic hogs)"
        ;;
    vicious)
        start_compile_loop
        HOG_COUNT=$((NUM_CORES - 1))
        start_cpu_hogs "$HOG_COUNT"
        (while true; do dd if=/dev/zero of="${TEST_DIR}/io-stress-manual-test" bs=1m count=64 2>/dev/null; rm -f "${TEST_DIR}/io-stress-manual-test"; done) &
        bg_pids+=("$!")
        (python3 -c "
import time
blocks = []
try:
    for _ in range(20):
        b = bytearray(50*1024*1024)
        for i in range(0, len(b), 4096):
            b[i] = 0xFF
        blocks.append(b)
        time.sleep(0.5)
    time.sleep(300)
except Exception:
    time.sleep(300)
" 2>/dev/null) &
        bg_pids+=("$!")
        echo "  CPU load: vicious ($HOG_COUNT hogs + compile + disk I/O + 1GB memory pressure)"
        ;;
esac

if [[ "$RECONNECT_AFTER" -gt 0 ]]; then
    echo "  Reconnect forcing: after ${RECONNECT_AFTER}s using: $RECONNECT_COMMAND"
    (
        sleep "$RECONNECT_AFTER"
        {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] reconnect-trigger scheduled_after=${RECONNECT_AFTER}s"
            if eval "$RECONNECT_COMMAND"; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] reconnect-trigger result=success"
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] reconnect-trigger result=failure command=$RECONNECT_COMMAND"
            fi
        } >> "$RECONNECT_EVENTS_FILE" 2>&1
    ) &
    bg_pids+=("$!")
fi

sleep 2

kanata_cpu=$(ps -o %cpu= -p "$KANATA_PID" 2>/dev/null | tr -d ' ')
echo "  Kanata CPU at start: ${kanata_cpu}%"
echo

echo "  Starting log monitor (duplicate detection + investigation markers will appear here)..."
echo "  (ignoring: backspace, arrows, modifiers, space, enter, tab, esc)"
(
    tail -n 0 -F "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        printf '%s\n' "$line" >> "$MONITOR_CAPTURE_FILE"
        if echo "$line" | grep -q "DUPLICATE DETECTION"; then
            echo "  🔴 $line"
        elif echo "$line" | grep -q "Skipping duplicate"; then
            if echo "$line" | grep -qiE "duplicate: (backspace|delete|left|right|up|down|home|end|pageup|pagedown|leftshift|rightshift|leftctrl|rightctrl|leftalt|rightalt|leftmeta|rightmeta|tab|escape|caps|numlock|space|enter|return) "; then
                :
            else
                echo "  🟡 $line"
            fi
        elif echo "$line" | grep -q "\[INVESTIGATION\]"; then
            echo "  🔵 $line"
        fi
    done
) &
MONITOR_PID=$!
bg_pids+=("$MONITOR_PID")

touch "$SCRATCH_FILE"
open -a "Zed" "$SCRATCH_FILE" &
sleep 2

clear

echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║   TYPE THIS TEXT INTO ZED (the blank file that just opened)║"
echo "║   Typos are fine — added characters are the main signal.   ║"
echo "║   CPU stress is running in the background.                 ║"
if [[ "$RECONNECT_AFTER" -gt 0 ]]; then
    echo "║   Kanata will be restarted mid-run after ${RECONNECT_AFTER}s.           ║"
else
    echo "║   No forced reconnect is scheduled for this run.           ║"
fi
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo
echo "───────────────── START TYPING THIS ─────────────────"
echo
cat "$REFERENCE_FILE"
echo
echo "───────────────── STOP TYPING HERE ──────────────────"
echo
echo "  Any 🔴 duplicate alerts or 🔵 investigation markers from Kanata will appear below:"
echo
echo "  ─── live alerts ───"
echo

read -r -p ">>> Done typing? Press ENTER to analyze results... "

TYPING_END=$(date '+%H:%M:%S')
echo
echo "  Capturing results at $TYPING_END..."

osascript -e 'tell application "Zed" to activate' 2>/dev/null || true
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "a" using command down' 2>/dev/null || true
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "c" using command down' 2>/dev/null || true
sleep 1
ACTUAL_OUTPUT=$(pbpaste 2>/dev/null || echo "")
echo "$ACTUAL_OUTPUT" > "$TEST_DIR/actual-output.txt"

cleanup_load
trap - EXIT
kill "$MONITOR_PID" 2>/dev/null || true
pkill -f "tail.*keypath-debug.log" 2>/dev/null || true
sleep 1

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cp "$MONITOR_CAPTURE_FILE" "$LOG_SLICE_FILE" 2>/dev/null || : > "$LOG_SLICE_FILE"
cp "$KANATA_STDOUT_LOG" "$KANATA_STDOUT_CAPTURE_FILE" 2>/dev/null || : > "$KANATA_STDOUT_CAPTURE_FILE"
cp "$KANATA_STDERR_LOG" "$KANATA_STDERR_CAPTURE_FILE" 2>/dev/null || : > "$KANATA_STDERR_CAPTURE_FILE"

KEY_EVENT_COUNT=$(grep -c "KeyInput:" "$LOG_SLICE_FILE" 2>/dev/null || echo "0"); KEY_EVENT_COUNT=$(echo "$KEY_EVENT_COUNT" | tr -d '[:space:]')
LAYER_EVENT_COUNT=$(grep -c "CurrentLayerName" "$LOG_SLICE_FILE" 2>/dev/null || echo "0"); LAYER_EVENT_COUNT=$(echo "$LAYER_EVENT_COUNT" | tr -d '[:space:]')
grep "\[INVESTIGATION\]" "$LOG_SLICE_FILE" > "$SESSION_MARKERS_FILE" 2>/dev/null || true
grep "AutorepeatMismatch" "$LOG_SLICE_FILE" > "$UNMATCHED_AUTOREPEAT_FILE" 2>/dev/null || true
grep "KEYPATH_INVESTIGATION\|OutputTransition" "$KANATA_STDOUT_CAPTURE_FILE" "$KANATA_STDERR_CAPTURE_FILE" > "$KANATA_OUTPUT_MARKERS_FILE" 2>/dev/null || true

echo
echo "  HID Path Validation:"
if [[ "$KEY_EVENT_COUNT" -gt 0 ]]; then
    echo "    ✓ Kanata processed $KEY_EVENT_COUNT key events (HID path confirmed)"
else
    echo "    ✗ Kanata saw 0 key events — HID path NOT exercised!"
    echo "      This test is INVALID. Were you typing on the physical keyboard?"
fi
echo "    Layer events: $LAYER_EVENT_COUNT"

IGNORED_KEYS_PATTERN="(backspace|delete|left|right|up|down|home|end|pageup|pagedown|leftshift|rightshift|leftctrl|rightctrl|leftalt|rightalt|leftmeta|rightmeta|tab|escape|caps|numlock|space|enter|return)"
grep "DUPLICATE DETECTION" "$LOG_SLICE_FILE" | grep -ivE "Key '$IGNORED_KEYS_PATTERN'" > "$TEST_DIR/dup-alerts-text.txt" 2>/dev/null || true
grep "Skipping duplicate" "$LOG_SLICE_FILE" | grep -ivE "duplicate: $IGNORED_KEYS_PATTERN " > "$TEST_DIR/dedup-skips-text.txt" 2>/dev/null || true
grep "DUPLICATE DETECTION" "$LOG_SLICE_FILE" | grep -iE "Key '$IGNORED_KEYS_PATTERN'" > "$TEST_DIR/dup-alerts-ignored.txt" 2>/dev/null || true
grep "Skipping duplicate" "$LOG_SLICE_FILE" | grep -iE "duplicate: $IGNORED_KEYS_PATTERN " > "$TEST_DIR/dedup-skips-ignored.txt" 2>/dev/null || true

DUPLICATE_ALERTS=$(wc -l < "$TEST_DIR/dup-alerts-text.txt" | tr -d ' ')
DEDUP_SKIPS=$(wc -l < "$TEST_DIR/dedup-skips-text.txt" | tr -d ' ')
IGNORED_DUP_ALERTS=$(wc -l < "$TEST_DIR/dup-alerts-ignored.txt" | tr -d ' ')
IGNORED_DEDUP_SKIPS=$(wc -l < "$TEST_DIR/dedup-skips-ignored.txt" | tr -d ' ')
SESSION_MARKER_COUNT=$(wc -l < "$SESSION_MARKERS_FILE" | tr -d ' ')
UNMATCHED_AUTOREPEATS=$(wc -l < "$UNMATCHED_AUTOREPEAT_FILE" | tr -d ' ')
KANATA_OUTPUT_MARKERS=$(wc -l < "$KANATA_OUTPUT_MARKERS_FILE" | tr -d ' ')

echo
echo "  Duplicate Detection (text keys only):"
echo "    ⚠️  DUPLICATE DETECTION alerts: $DUPLICATE_ALERTS"
echo "    🚫 Dedup filter skips: $DEDUP_SKIPS"
echo "    🔵 Investigation markers: $SESSION_MARKER_COUNT"
echo "    🔁 Unmatched autorepeats: $UNMATCHED_AUTOREPEATS"
echo "    🧪 Kanata output markers: $KANATA_OUTPUT_MARKERS"
echo "    (ignored nav/modifier repeats: $IGNORED_DUP_ALERTS alerts, $IGNORED_DEDUP_SKIPS skips)"

expected_len=$REFERENCE_CHARS
actual_len=$(echo -n "$ACTUAL_OUTPUT" | wc -c | tr -d ' ')

echo
echo "  Character Comparison:"
echo "    Reference: $expected_len chars"
echo "    Typed:     $actual_len chars"
echo "    Difference: $((actual_len - expected_len)) chars"

diff "$REFERENCE_FILE" "$TEST_DIR/actual-output.txt" > "$TEST_DIR/diff-report.txt" 2>&1 || true
diff --word-diff=porcelain "$REFERENCE_FILE" "$TEST_DIR/actual-output.txt" > "$TEST_DIR/word-diff.txt" 2>&1 || true

additions=$(grep -c '^+' "$TEST_DIR/word-diff.txt" 2>/dev/null || true); additions=${additions:-0}; additions=$(echo "$additions" | tr -d '[:space:]')
deletions=$(grep -c '^-' "$TEST_DIR/word-diff.txt" 2>/dev/null || true); deletions=${deletions:-0}; deletions=$(echo "$deletions" | tr -d '[:space:]')

python3 - "$REFERENCE_FILE" "$TEST_DIR/actual-output.txt" "$SUSPICIOUS_SUMMARY_FILE" "$REPEATED_CHAR_FILE" "$REPEATED_WORD_FILE" "$ADDITION_WINDOWS_FILE" <<'PY'
from pathlib import Path
import difflib
import re
import sys

reference = Path(sys.argv[1]).read_text()
actual = Path(sys.argv[2]).read_text()
summary_path = Path(sys.argv[3])
char_path = Path(sys.argv[4])
word_path = Path(sys.argv[5])
addition_path = Path(sys.argv[6])

matcher = difflib.SequenceMatcher(a=reference, b=actual)
addition_windows = []
char_windows = []

for tag, i1, i2, j1, j2 in matcher.get_opcodes():
    if tag not in {"insert", "replace"}:
        continue
    ref_segment = reference[i1:i2]
    actual_segment = actual[j1:j2]
    if len(actual_segment) <= len(ref_segment):
        continue
    added = actual_segment[len(ref_segment):] if tag == "replace" and actual_segment.startswith(ref_segment) else actual_segment
    if not added:
        continue
    before = actual[max(0, j1 - 20):j1].replace("\n", "\\n")
    after = actual[j2:min(len(actual), j2 + 20)].replace("\n", "\\n")
    added_display = added.replace("\n", "\\n")
    addition_windows.append(
        f"tag={tag} actual_range={j1}:{j2} added={added_display!r} before={before!r} after={after!r}"
    )
    prev_char = actual[j1 - 1] if j1 > 0 else ""
    repeated_boundary = bool(added) and prev_char == added[0]
    repeated_internal = any(added[idx] == added[idx - 1] for idx in range(1, len(added)))
    if repeated_boundary or repeated_internal:
        char_windows.append(
            f"actual_range={j1}:{j2} added={added_display!r} repeated_boundary={repeated_boundary} repeated_internal={repeated_internal} before={before!r} after={after!r}"
        )

repeated_words = []
for match in re.finditer(r"\b([A-Za-z]+)\b(?:\s+)\b(\1)\b", actual, flags=re.IGNORECASE):
    start, end = match.span()
    context = actual[max(0, start - 25):min(len(actual), end + 25)].replace("\n", "\\n")
    repeated_words.append(f"actual_range={start}:{end} word={match.group(1)!r} context={context!r}")

summary_lines = [
    f"addition_windows={len(addition_windows)}",
    f"suspicious_repeated_char_windows={len(char_windows)}",
    f"suspicious_repeated_word_windows={len(repeated_words)}",
]

summary_path.write_text("\n".join(summary_lines) + "\n")
char_path.write_text("\n".join(char_windows) + ("\n" if char_windows else ""))
word_path.write_text("\n".join(repeated_words) + ("\n" if repeated_words else ""))
addition_path.write_text("\n".join(addition_windows) + ("\n" if addition_windows else ""))
PY

SUSPICIOUS_CHAR_WINDOWS=$(wc -l < "$REPEATED_CHAR_FILE" | tr -d ' ')
SUSPICIOUS_WORD_WINDOWS=$(wc -l < "$REPEATED_WORD_FILE" | tr -d ' ')
ADDITION_WINDOWS=$(wc -l < "$ADDITION_WINDOWS_FILE" | tr -d ' ')
SUSPICIOUS_ADDITIONS=$((SUSPICIOUS_CHAR_WINDOWS + SUSPICIOUS_WORD_WINDOWS))

echo
echo "  Word-Level Diff:"
echo "    Additions (potential duplicates): $additions"
echo "    Deletions (potential drops): $deletions"
echo "    Addition windows: $ADDITION_WINDOWS"
echo "    Suspicious repeated-char windows: $SUSPICIOUS_CHAR_WINDOWS"
echo "    Suspicious repeated-word windows: $SUSPICIOUS_WORD_WINDOWS"

if [[ "$ADDITION_WINDOWS" -gt 0 ]]; then
    echo
    echo "  Suspicious addition windows (first 10):"
    head -10 "$ADDITION_WINDOWS_FILE" | sed 's/^/    /'
fi

{
    echo "Manual Keystroke Test Analysis"
    echo "Date: $(date)"
    echo "Preset: $PRESET"
    echo "Reconnect after: $RECONNECT_AFTER"
    echo "Reconnect command: $RECONNECT_COMMAND"
    echo "Kanata PID: $KANATA_PID"
    echo "Key events processed by Kanata: $KEY_EVENT_COUNT"
    echo "Layer events: $LAYER_EVENT_COUNT"
    echo "Duplicate detection alerts: $DUPLICATE_ALERTS"
    echo "Dedup filter skips: $DEDUP_SKIPS"
    echo "Investigation markers: $SESSION_MARKER_COUNT"
    echo "Unmatched autorepeats: $UNMATCHED_AUTOREPEATS"
    echo "Kanata output markers: $KANATA_OUTPUT_MARKERS"
    echo "Reference chars: $expected_len"
    echo "Actual chars: $actual_len"
    echo "Difference: $((actual_len - expected_len))"
    echo "Word additions: $additions"
    echo "Word deletions: $deletions"
    echo "Addition windows: $ADDITION_WINDOWS"
    echo "Suspicious repeated-char windows: $SUSPICIOUS_CHAR_WINDOWS"
    echo "Suspicious repeated-word windows: $SUSPICIOUS_WORD_WINDOWS"
} > "$ANALYSIS_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VERDICT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VERDICT_TEXT=""
if [[ "$KEY_EVENT_COUNT" -eq 0 ]]; then
    VERDICT_TEXT="INVALID TEST — Kanata did not process any key events. Ensure you're typing on the physical keyboard, not pasting."
    echo "  ❌ $VERDICT_TEXT"
elif [[ "$DUPLICATE_ALERTS" -gt 0 ]]; then
    VERDICT_TEXT="DUPLICATES DETECTED — $DUPLICATE_ALERTS consecutive-key alerts under preset=$PRESET."
    echo "  🔴 $VERDICT_TEXT"
elif [[ "$SUSPICIOUS_ADDITIONS" -gt 0 ]]; then
    VERDICT_TEXT="SUSPICIOUS ADDITIONS — repeated-character or repeated-word windows were found in actual output."
    echo "  🔴 $VERDICT_TEXT"
elif [[ "$UNMATCHED_AUTOREPEATS" -gt 0 ]]; then
    VERDICT_TEXT="SYSTEM AUTOREPEAT MISMATCH — macOS autorepeat events occurred without matching Kanata repeat events."
    echo "  🔴 $VERDICT_TEXT"
elif [[ "$ADDITION_WINDOWS" -gt 0 ]]; then
    VERDICT_TEXT="ADDITIONS OBSERVED — output contains inserted text that needs review even without obvious repeated-char signatures."
    echo "  🟡 $VERDICT_TEXT"
elif [[ "$DEDUP_SKIPS" -gt 0 ]]; then
    VERDICT_TEXT="DEDUP FILTER ACTIVE — duplicates were observed and filtered before reaching the view."
    echo "  🟡 $VERDICT_TEXT"
elif [[ "$actual_len" -eq "$expected_len" ]] && [[ "$additions" -eq 0 ]]; then
    VERDICT_TEXT="PASS — no added text, no duplicate alerts, and HID path confirmed under preset=$PRESET."
    echo "  ✅ $VERDICT_TEXT"
else
    VERDICT_TEXT="INCONCLUSIVE — no suspicious additions, but the diff still needs human review for omissions vs typos."
    echo "  ⚠️  $VERDICT_TEXT"
fi

printf '%s\n' "$VERDICT_TEXT" > "$VERDICT_FILE"

echo
echo "Full results: $TEST_DIR/"
echo "  reference.txt                   — what you should have typed"
echo "  actual-output.txt               — what appeared in Zed"
echo "  diff-report.txt                 — line-level diff"
echo "  word-diff.txt                   — word-level diff"
echo "  log-slice.txt                   — KeyPath log slice from this run"
echo "  session-markers.txt             — investigation session/reconnect markers"
echo "  unmatched-autorepeat-events.txt — macOS autorepeat without matching Kanata repeat"
echo "  reconnect-events.txt            — reconnect trigger log (if enabled)"
echo "  addition-windows.txt            — inserted-text windows from diff analysis"
echo "  repeated-char-windows.txt       — suspicious repeated-character windows"
echo "  repeated-word-windows.txt       — suspicious repeated-word windows"
echo "  suspicious-additions-summary.txt — counts for suspicious additions"
echo "  analysis.txt                    — machine-readable summary"
echo "  verdict.txt                     — one-line verdict"
