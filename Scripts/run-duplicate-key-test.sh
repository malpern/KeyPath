#!/usr/bin/env bash
# Two-pronged duplicate keystroke test:
#   1. Runs the existing repro harness (monitors KeyPath notification pipeline)
#   2. Opens Zed with a scratch file, auto-types known corpus, then diffs input vs output
#
# Prerequisites: KeyPath must be running (Kanata active), Zed installed.
# Usage:
#   ./Scripts/run-duplicate-key-test.sh [--preset baseline|medium|high]

set -euo pipefail

PRESET="${1:---preset}"
PRESET_VAL="${2:-medium}"
if [[ "$PRESET" == "--preset" ]]; then
    PRESET_VAL="${PRESET_VAL}"
else
    PRESET_VAL="$PRESET"
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_DIR="${TMPDIR:-/tmp}/keypath-dup-test-$TIMESTAMP"
mkdir -p "$TEST_DIR"

SCRATCH_FILE="$TEST_DIR/typed-output.txt"
EXPECTED_FILE="$TEST_DIR/expected-input.txt"
DIFF_FILE="$TEST_DIR/diff-report.txt"
DURATION=60

# The known corpus (must match repro-duplicate-keys.sh)
CORPUS=(
    "The quick brown fox jumps over the lazy dog. "
    "func handleKeyPress(_ event: KeyEvent) -> Bool { return true } "
    "Programming is the art of telling another human what one wants the computer to do. "
    "let result = try await manager.processEvent(key: .a, modifiers: [.shift]) "
    "if context.permissions.inputMonitoring == .granted { startService() } "
    "The five boxing wizards jump quickly at dawn. "
    "guard let config = ConfigurationService.shared.load() else { return nil } "
    "Pack my box with five dozen liquor jugs. "
    "switch event.type { case .keyDown: handle(event) case .keyUp: release(event) } "
    "How vexingly quick daft zebras jump quickly over the lazy brown fox. "
)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         KeyPath Duplicate Keystroke Test Suite              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Preset: $(printf '%-49s' "$PRESET_VAL")║"
echo "║  Duration: ${DURATION}s per trial                                  ║"
echo "║  Output: $TEST_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

# --- Preflight ---
echo "Running preflight checks..."

errors=()
if ! pgrep -iq kanata 2>/dev/null; then
    errors+=("Kanata is not running. Launch KeyPath first.")
fi

if ! mdfind "kMDItemCFBundleIdentifier == 'dev.zed.Zed'" 2>/dev/null | head -1 | grep -q .; then
    errors+=("Zed not found. Install Zed or adjust this script for your editor.")
fi

if [[ ${#errors[@]} -gt 0 ]]; then
    echo
    echo "PREFLIGHT FAILED:"
    for e in "${errors[@]}"; do
        echo "  ✗ $e"
    done
    exit 1
fi

echo "  ✓ Kanata running (PID $(pgrep -i kanata | head -1))"
echo "  ✓ Zed installed"
echo "  ✓ KeyPath log exists"
echo

# --- Phase 1: Pipeline test (existing harness) ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 1: Notification Pipeline Test (repro harness)"
echo "  Monitors KeyPath's TCP event log for duplicate notifications."
echo "  This tests whether the 100ms dedup filter is working."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

"$SCRIPT_DIR/repro-duplicate-keys.sh" \
    --preset "$PRESET_VAL" \
    --trials 1 \
    --duration "$DURATION" \
    --countdown 3 \
    --auto-type osascript \
    --auto-type-wpm 50 2>&1 | tee "$TEST_DIR/phase1-output.log"

echo
echo "Phase 1 complete. Results in $TEST_DIR/phase1-output.log"
echo

# --- Phase 2: Actual keystroke fidelity test ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 2: Keystroke Fidelity Test"
echo "  Types known text into Zed, then compares input vs. output."
echo "  This tests whether actual characters double in the editor."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Create the scratch file and open in Zed
touch "$SCRATCH_FILE"
echo "Opening scratch file in Zed: $SCRATCH_FILE"
open -a "Zed" "$SCRATCH_FILE" &
sleep 3  # Give Zed time to open and focus

# Build expected output
> "$EXPECTED_FILE"
corpus_idx=0
corpus_len=${#CORPUS[@]}
typed_chars=0
# Type ~500 chars worth (about 100 words at 5 chars/word)
target_chars=500

echo "Typing $target_chars characters of known corpus into Zed..."
echo "(CPU load preset: $PRESET_VAL)"
echo

# Start CPU load if not baseline
bg_pids=()
cleanup_load() {
    for pid in "${bg_pids[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup_load EXIT

case "$PRESET_VAL" in
    medium)
        (cd "$PROJECT_ROOT" && while true; do swift build -c debug >/dev/null 2>&1 || true; done) &
        bg_pids+=("$!")
        yes >/dev/null & bg_pids+=("$!")
        yes >/dev/null & bg_pids+=("$!")
        echo "  CPU load started (medium: compile loop + 2 hogs)"
        ;;
    high)
        (cd "$PROJECT_ROOT" && while true; do swift build -c debug >/dev/null 2>&1 || true; done) &
        bg_pids+=("$!")
        for i in {1..6}; do yes >/dev/null & bg_pids+=("$!"); done
        echo "  CPU load started (high: compile loop + 6 hogs)"
        ;;
    baseline)
        echo "  No CPU load (baseline)"
        ;;
esac

sleep 2  # Let load ramp up

# Activate Zed window
osascript -e 'tell application "Zed" to activate' 2>/dev/null || true
sleep 1

# Type corpus via osascript, building expected output simultaneously
while [[ $typed_chars -lt $target_chars ]]; do
    phrase="${CORPUS[$corpus_idx]}"
    printf "%s" "$phrase" >> "$EXPECTED_FILE"

    # osascript keystroke - type the phrase
    osascript -e "tell application \"System Events\" to keystroke \"$phrase\"" 2>/dev/null || true

    typed_chars=$((typed_chars + ${#phrase}))
    corpus_idx=$(( (corpus_idx + 1) % corpus_len ))

    # Pace at ~50 WPM: 250 chars/min = ~4.2 chars/sec
    char_count=${#phrase}
    pause=$(awk "BEGIN { printf \"%.2f\", $char_count / 4.2 }")
    sleep "$pause"
done

echo
echo "Typing complete. Waiting 3s for Zed to flush..."
sleep 3

# Stop CPU load
cleanup_load
trap - EXIT

# Save Zed content via cmd+A, cmd+C, then pbpaste
osascript -e 'tell application "Zed" to activate' 2>/dev/null || true
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "a" using command down' 2>/dev/null || true
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "c" using command down' 2>/dev/null || true
sleep 0.5
ACTUAL_OUTPUT=$(pbpaste 2>/dev/null || echo "")

echo "$ACTUAL_OUTPUT" > "$TEST_DIR/actual-output.txt"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 2 RESULTS: Keystroke Fidelity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

expected_len=$(wc -c < "$EXPECTED_FILE" | tr -d ' ')
actual_len=$(echo -n "$ACTUAL_OUTPUT" | wc -c | tr -d ' ')

echo "  Expected chars: $expected_len"
echo "  Actual chars:   $actual_len"
echo "  Difference:     $((actual_len - expected_len)) chars"
echo

if [[ "$actual_len" -gt "$expected_len" ]]; then
    extra=$((actual_len - expected_len))
    pct=$(awk "BEGIN { printf \"%.1f\", ($extra / $expected_len) * 100 }")
    echo "  ⚠️  EXTRA CHARACTERS DETECTED: $extra extra chars ($pct% inflation)"
    echo "     This suggests Kanata is emitting duplicate HID events under load."
    echo
elif [[ "$actual_len" -lt "$expected_len" ]]; then
    missing=$((expected_len - actual_len))
    echo "  ⚠️  MISSING CHARACTERS: $missing chars dropped"
    echo "     This suggests keystroke events were lost under load."
    echo
else
    echo "  ✓  Character counts match exactly."
    echo
fi

# Generate diff
diff <(cat "$EXPECTED_FILE") <(echo "$ACTUAL_OUTPUT") > "$DIFF_FILE" 2>&1 || true

if [[ -s "$DIFF_FILE" ]]; then
    echo "  Differences found (first 30 lines):"
    head -30 "$DIFF_FILE" | sed 's/^/    /'
else
    echo "  ✓  Output matches expected input exactly. No duplicates detected."
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OVERALL ASSESSMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

phase1_alerts=0
phase1_alert_file=$(find "${TMPDIR:-/tmp}" -name "alerts.log" -newer "$TEST_DIR" -maxdepth 2 2>/dev/null | head -1)
if [[ -n "$phase1_alert_file" ]] && [[ -s "$phase1_alert_file" ]]; then
    phase1_alerts=$(wc -l < "$phase1_alert_file" | tr -d ' ')
fi

echo "  Pipeline duplicates (Phase 1): $phase1_alerts"
echo "  Character inflation (Phase 2): $((actual_len - expected_len))"
echo

if [[ "$phase1_alerts" -eq 0 ]] && [[ "$actual_len" -eq "$expected_len" ]]; then
    echo "  ✅ PASS: No duplicates detected at preset=$PRESET_VAL"
    echo "     The 100ms dedup filter appears effective and Kanata is not"
    echo "     emitting duplicate HID events at this load level."
elif [[ "$phase1_alerts" -eq 0 ]] && [[ "$actual_len" -gt "$expected_len" ]]; then
    echo "  🔴 FAIL: Pipeline clean but characters duplicated in editor!"
    echo "     The dedup fix is working at the UI layer, but Kanata is"
    echo "     emitting duplicate HID events to the OS. This is a deeper"
    echo "     issue — likely scheduling starvation or tap-hold timer drift."
    echo "     Root cause is in Kanata, not KeyPath."
elif [[ "$phase1_alerts" -gt 0 ]] && [[ "$actual_len" -gt "$expected_len" ]]; then
    echo "  🔴 FAIL: Duplicates at both layers."
    echo "     Both the notification pipeline AND actual keystrokes show"
    echo "     duplicates. The problem is systemic."
else
    echo "  ⚠️  MIXED: Pipeline showed $phase1_alerts alerts but character"
    echo "     counts are close. Review the diff for details."
fi

echo
echo "Full results: $TEST_DIR/"
echo "  phase1-output.log  — repro harness output"
echo "  expected-input.txt — what was sent"
echo "  actual-output.txt  — what appeared in Zed"
echo "  diff-report.txt    — character-level diff"
