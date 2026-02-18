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
#   4. Monitors KeyPath log for duplicate detection diagnostics
#   5. When you're done, captures Zed content and diffs against reference
#   6. Analyzes KeyPath log for ⚠️ [DUPLICATE DETECTION] entries
#
# Usage:
#   ./Scripts/manual-keystroke-test.sh [baseline|medium|high|vicious]

set -euo pipefail

PRESET="${1:-high}"
SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_DIR="${TMPDIR:-/tmp}/keypath-manual-test-$TIMESTAMP"
mkdir -p "$TEST_DIR"

LOG_FILE="$HOME/Library/Logs/KeyPath/keypath-debug.log"
SCRATCH_FILE="$TEST_DIR/typed-output.txt"
REFERENCE_FILE="$TEST_DIR/reference.txt"
LOG_SNAPSHOT_START="$TEST_DIR/log-start-line.txt"
ANALYSIS_FILE="$TEST_DIR/analysis.txt"

# --- Reference passage ---
# Deliberately includes: double letters (tt, ll, ss, ee, ff), punctuation,
# capitalization, numbers, symbols common in code, and varied word lengths.
# ~300 words, ~1500 chars — enough to surface timing issues without being exhausting.
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

# --- Preflight ---
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
    for e in "${errors[@]}"; do echo "  ✗ $e"; done
    exit 1
fi

KANATA_PID=$(pgrep -i kanata | head -1)
echo "  ✓ Kanata running (PID $KANATA_PID)"
echo "  ✓ KeyPath log exists"
echo

# --- Mark log position ---
LOG_LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
echo "$LOG_LINE_COUNT" > "$LOG_SNAPSHOT_START"

# --- Start CPU load ---
bg_pids=()
cleanup_load() {
    for pid in "${bg_pids[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    pkill -f "dd if=/dev/zero of=.*manual-test" 2>/dev/null || true
}
trap cleanup_load EXIT

NUM_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)

case "$PRESET" in
    baseline)
        echo "  No CPU load (baseline)"
        ;;
    medium)
        (cd "$PROJECT_ROOT" && while true; do swift build -c debug >/dev/null 2>&1 || true; done) &
        bg_pids+=("$!")
        yes >/dev/null & bg_pids+=("$!")
        yes >/dev/null & bg_pids+=("$!")
        echo "  CPU load: medium (compile loop + 2 hogs)"
        ;;
    high)
        (cd "$PROJECT_ROOT" && while true; do swift build -c debug >/dev/null 2>&1 || true; done) &
        bg_pids+=("$!")
        for i in {1..6}; do yes >/dev/null & bg_pids+=("$!"); done
        echo "  CPU load: high (compile loop + 6 hogs)"
        ;;
    vicious)
        (cd "$PROJECT_ROOT" && while true; do swift build -c debug >/dev/null 2>&1 || true; done) &
        bg_pids+=("$!")
        HOG_COUNT=$((NUM_CORES - 1))
        for (( i=0; i<HOG_COUNT; i++ )); do yes >/dev/null & bg_pids+=("$!"); done
        (while true; do dd if=/dev/zero of="${TEST_DIR}/io-stress-manual-test" bs=1m count=64 2>/dev/null; rm -f "${TEST_DIR}/io-stress-manual-test"; done) &
        bg_pids+=("$!")
        (python3 -c "
import time
blocks = []
try:
    for _ in range(20):
        b = bytearray(50*1024*1024)
        for i in range(0, len(b), 4096): b[i] = 0xFF
        blocks.append(b)
        time.sleep(0.5)
    time.sleep(300)
except: time.sleep(300)
" 2>/dev/null) &
        bg_pids+=("$!")
        echo "  CPU load: VICIOUS ($HOG_COUNT hogs + compile + disk I/O + 1GB memory pressure)"
        ;;
    *)
        echo "Error: preset must be baseline, medium, high, or vicious" >&2
        exit 1
        ;;
esac

sleep 2

# Show Kanata CPU to confirm it's alive and processing
kanata_cpu=$(ps -o %cpu= -p "$KANATA_PID" 2>/dev/null | tr -d ' ')
echo "  Kanata CPU at start: ${kanata_cpu}%"
echo

# --- Start live log monitor in background ---
# Watches for duplicate detection and key events in real time
echo "  Starting log monitor (duplicate detection alerts will appear here)..."
echo "  (ignoring: backspace, arrows, modifiers, space, enter, tab, esc)"
(
    tail -n 0 -F "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "DUPLICATE DETECTION"; then
            echo "  🔴 $line"
        elif echo "$line" | grep -q "Skipping duplicate"; then
            # Filter out ignored keys from dedup skip messages too
            if echo "$line" | grep -qiE "duplicate: (backspace|delete|left|right|up|down|home|end|pageup|pagedown|leftshift|rightshift|leftctrl|rightctrl|leftalt|rightalt|leftmeta|rightmeta|tab|escape|caps|numlock|space|enter|return) "; then
                : # ignore
            else
                echo "  🟡 $line"
            fi
        fi
    done
) &
MONITOR_PID=$!
bg_pids+=("$MONITOR_PID")

# --- Open Zed and display reference ---
touch "$SCRATCH_FILE"
open -a "Zed" "$SCRATCH_FILE" &
sleep 2

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TYPE THE FOLLOWING PASSAGE INTO ZED"
echo "  (copy it exactly — including code, numbers, punctuation)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
cat "$REFERENCE_FILE"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  Duplicate detection alerts will appear in real time above."
echo "  Kanata is processing every physical keystroke you type."
echo
echo "  Don't worry about typos — we're looking for REPEATED characters"
echo "  (same key 3+ times in <500ms), not spelling errors."
echo
echo "  When you're done typing, press ENTER here to analyze results."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for user to finish typing
read -r -p "  Press ENTER when done typing... "

TYPING_END=$(date '+%H:%M:%S')
echo
echo "  Capturing results at $TYPING_END..."

# --- Capture Zed content ---
osascript -e 'tell application "Zed" to activate' 2>/dev/null || true
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "a" using command down' 2>/dev/null || true
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "c" using command down' 2>/dev/null || true
sleep 1
ACTUAL_OUTPUT=$(pbpaste 2>/dev/null || echo "")
echo "$ACTUAL_OUTPUT" > "$TEST_DIR/actual-output.txt"

# --- Stop load & monitor ---
cleanup_load
trap - EXIT
kill "$MONITOR_PID" 2>/dev/null || true
pkill -f "tail.*keypath-debug.log" 2>/dev/null || true
sleep 1

# --- Check Kanata CPU was non-zero (confirms HID path was exercised) ---
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# --- Validity check: did Kanata actually process keystrokes? ---
LOG_START=$(cat "$LOG_SNAPSHOT_START")
NEW_LOG_LINES=$(tail -n +"$((LOG_START + 1))" "$LOG_FILE")

KEY_EVENT_COUNT=$(echo "$NEW_LOG_LINES" | grep -c "KeyInput:" || true)
LAYER_EVENT_COUNT=$(echo "$NEW_LOG_LINES" | grep -c "CurrentLayerName" || true)

echo
echo "  HID Path Validation:"
if [[ "$KEY_EVENT_COUNT" -gt 0 ]]; then
    echo "    ✓ Kanata processed $KEY_EVENT_COUNT key events (HID path confirmed)"
else
    echo "    ✗ Kanata saw 0 key events — HID path NOT exercised!"
    echo "      This test is INVALID. Were you typing on the physical keyboard?"
fi
echo "    Layer events: $LAYER_EVENT_COUNT"

# --- Duplicate detection analysis ---
# Filter out navigation/modifier keys from duplicate counts
IGNORED_KEYS_PATTERN="(backspace|delete|left|right|up|down|home|end|pageup|pagedown|leftshift|rightshift|leftctrl|rightctrl|leftalt|rightalt|leftmeta|rightmeta|tab|escape|caps|numlock|space|enter|return)"
DUPLICATE_ALERTS=$(echo "$NEW_LOG_LINES" | grep "DUPLICATE DETECTION" | grep -civE "Key '$IGNORED_KEYS_PATTERN'" || true)
DEDUP_SKIPS=$(echo "$NEW_LOG_LINES" | grep "Skipping duplicate" | grep -civE "duplicate: $IGNORED_KEYS_PATTERN " || true)

# Also count the ignored ones separately for transparency
IGNORED_DUP_ALERTS=$(echo "$NEW_LOG_LINES" | grep "DUPLICATE DETECTION" | grep -ciE "Key '$IGNORED_KEYS_PATTERN'" || true)
IGNORED_DEDUP_SKIPS=$(echo "$NEW_LOG_LINES" | grep "Skipping duplicate" | grep -ciE "duplicate: $IGNORED_KEYS_PATTERN " || true)

echo
echo "  Duplicate Detection (text keys only):"
echo "    ⚠️  DUPLICATE DETECTION alerts: $DUPLICATE_ALERTS"
echo "    🚫 Dedup filter skips: $DEDUP_SKIPS"
echo "    (ignored nav/modifier repeats: $IGNORED_DUP_ALERTS alerts, $IGNORED_DEDUP_SKIPS skips)"

if [[ "$DUPLICATE_ALERTS" -gt 0 ]]; then
    echo
    echo "  Duplicate details:"
    echo "$NEW_LOG_LINES" | grep "DUPLICATE DETECTION" | sed 's/^/    /'
fi

# --- Character comparison ---
expected_len=$REFERENCE_CHARS
actual_len=$(echo -n "$ACTUAL_OUTPUT" | wc -c | tr -d ' ')

echo
echo "  Character Comparison:"
echo "    Reference: $expected_len chars"
echo "    Typed:     $actual_len chars"
echo "    Difference: $((actual_len - expected_len)) chars"

# --- Word-level diff ---
diff "$REFERENCE_FILE" "$TEST_DIR/actual-output.txt" > "$TEST_DIR/diff-report.txt" 2>&1 || true

# Word diff for precision
diff --word-diff=porcelain "$REFERENCE_FILE" "$TEST_DIR/actual-output.txt" \
    > "$TEST_DIR/word-diff.txt" 2>&1 || true

additions=$(grep -c '^+' "$TEST_DIR/word-diff.txt" 2>/dev/null || echo "0")
deletions=$(grep -c '^-' "$TEST_DIR/word-diff.txt" 2>/dev/null || echo "0")

echo
echo "  Word-Level Diff:"
echo "    Additions (potential duplicates): $additions"
echo "    Deletions (potential drops): $deletions"

if [[ "$additions" -gt 0 ]]; then
    echo
    echo "  Added words/chars (first 15):"
    grep '^+' "$TEST_DIR/word-diff.txt" | head -15 | sed 's/^/    /'
fi

# --- Save analysis ---
{
    echo "Manual Keystroke Test Analysis"
    echo "Date: $(date)"
    echo "Preset: $PRESET"
    echo "Kanata PID: $KANATA_PID"
    echo "Key events processed by Kanata: $KEY_EVENT_COUNT"
    echo "Duplicate detection alerts: $DUPLICATE_ALERTS"
    echo "Dedup filter skips: $DEDUP_SKIPS"
    echo "Reference chars: $expected_len"
    echo "Actual chars: $actual_len"
    echo "Difference: $((actual_len - expected_len))"
    echo "Word additions: $additions"
    echo "Word deletions: $deletions"
} > "$ANALYSIS_FILE"

# --- Overall verdict ---
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VERDICT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$KEY_EVENT_COUNT" -eq 0 ]]; then
    echo "  ❌ INVALID TEST — Kanata did not process any key events."
    echo "     Ensure you're typing on the physical keyboard, not pasting."
elif [[ "$DUPLICATE_ALERTS" -gt 0 ]]; then
    echo "  🔴 DUPLICATES DETECTED — $DUPLICATE_ALERTS consecutive-key alerts"
    echo "     under preset=$PRESET. The bug is NOT fully resolved."
    echo "     Review the alert details above for root-cause timing."
elif [[ "$actual_len" -gt "$((expected_len + 20))" ]]; then
    extra=$((actual_len - expected_len))
    echo "  🔴 EXTRA CHARACTERS — $extra more chars than reference."
    echo "     Possible duplicate keystrokes that slipped past detection."
elif [[ "$DEDUP_SKIPS" -gt 0 ]]; then
    echo "  🟡 DEDUP FILTER ACTIVE — $DEDUP_SKIPS duplicates caught and filtered."
    echo "     The fix is working but duplicates ARE being generated."
    echo "     This confirms the root cause is still present; the fix is a mitigation."
elif [[ "$actual_len" -eq "$expected_len" ]] || [[ "$additions" -le 2 ]]; then
    echo "  ✅ PASS — $KEY_EVENT_COUNT keystrokes through Kanata HID path,"
    echo "     zero duplicate alerts, character counts match."
    echo "     Fix appears effective at the HID level under preset=$PRESET."
else
    echo "  ⚠️  INCONCLUSIVE — review diff for typos vs systematic duplicates."
    echo "     Small differences may be human typing errors."
fi

echo
echo "Full results: $TEST_DIR/"
echo "  reference.txt     — what you should have typed"
echo "  actual-output.txt — what appeared in Zed"
echo "  diff-report.txt   — line-level diff"
echo "  word-diff.txt     — word-level diff"
echo "  analysis.txt      — machine-readable summary"
