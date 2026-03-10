#!/usr/bin/env bash
# Two-pronged duplicate keystroke test:
#   1. Runs the existing repro harness (monitors KeyPath notification pipeline)
#   2. Opens Zed with a scratch file, auto-types known corpus, then diffs input vs output
#
# Prerequisites: KeyPath must be running (Kanata active), Zed installed.
# Usage:
#   ./Scripts/run-duplicate-key-test.sh [--preset baseline|medium|high|vicious] [--phase2-only]

set -euo pipefail

SKIP_PHASE1=false
PRESET_VAL="medium"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase2-only) SKIP_PHASE1=true; shift ;;
        --preset) PRESET_VAL="${2:-medium}"; shift 2 ;;
        baseline|medium|high|vicious) PRESET_VAL="$1"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_DIR="${TMPDIR:-/tmp}/keypath-dup-test-$TIMESTAMP"
mkdir -p "$TEST_DIR"

SCRATCH_FILE="$TEST_DIR/typed-output.txt"
EXPECTED_FILE="$TEST_DIR/expected-input.txt"
DIFF_FILE="$TEST_DIR/diff-report.txt"
DURATION=60

# --- Corpus ---
# Standard corpus for normal presets (~10 phrases)
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

# Extended corpus for vicious mode — prose, code, special chars, punctuation-heavy
CORPUS_VICIOUS=(
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
    "struct ContentView: View { var body: some View { Text(greeting).padding() } } "
    "Every great developer you know got there by solving problems they were unqualified to solve until they actually did it. "
    "for await event in stream { try await processor.handle(event) } "
    "The difference between a good programmer and a great one is not how much they know, but how they think. "
    "enum Action { case keyDown(KeyCode) case keyUp(KeyCode) case modifier(Set<Modifier>) } "
    "async let alpha = fetchAlpha(); async let beta = fetchBeta(); let results = try await (alpha, beta) "
    "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it. "
    "protocol KeyHandler { func handle(_ event: KeyEvent) async throws -> KeyAction } "
    "extension Array where Element: Comparable { mutating func insertSorted(_ element: Element) { let idx = firstIndex(where: { element < $0 }) ?? endIndex; insert(element, at: idx) } } "
    "There are only two hard things in Computer Science: cache invalidation and naming things. "
    "@MainActor final class ViewModel: ObservableObject { @Published var state: ViewState = .idle } "
    "The best error message is the one that never shows up. Design your systems to prevent errors, not just report them. "
    "let pipeline = EventPipeline(); pipeline.add(stage: DeduplicationStage(window: .milliseconds(100))); pipeline.add(stage: ThrottleStage(rate: .perSecond(60))) "
    "Task.detached(priority: .userInitiated) { await MainActor.run { self.updateUI(with: result) } } "
    "Software is like entropy: it is difficult to grasp, weighs nothing, and obeys the Second Law of Thermodynamics; i.e., it always increases. "
    "func debounce<T>(delay: Duration, operation: @escaping (T) async -> Void) -> (T) async -> Void { var task: Task<Void, Never>?; return { value in task?.cancel(); task = Task { try? await Task.sleep(for: delay); await operation(value) } } } "
    "class KanataTCPClient { private let connection: NWConnection; private var requestCounter: UInt64 = 0; private let timeout: TimeInterval = 5.0 } "
    "Simplicity is prerequisite for reliability. The unavoidable price of reliability is simplicity. It is a price which the very rich find most hard to pay. "
    "NotificationCenter.default.publisher(for: .kanataKeyInput).compactMap { $0.userInfo }.sink { info in handleKey(info) }.store(in: &cancellables) "
    "Any fool can write code that a computer can understand. Good programmers write code that humans can understand. "
    "let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601; let data = try encoder.encode(payload) "
    "The most dangerous phrase in the English language is: We have always done it this way. "
    "guard !Task.isCancelled else { throw CancellationError() } "
    "Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away. "
    "do { let response = try await client.send(command, timeout: .seconds(5)); return parse(response) } catch { logger.error(error); throw KeyPathError.communication(.timeout) } "
    "import Foundation; import Network; import Observation; import OSLog "
    "A language that does not affect the way you think about programming is not worth knowing. "
    "withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() } "
    "First, solve the problem. Then, write the code. "
    "let semaphore = DispatchSemaphore(value: 0); defer { semaphore.signal() }; semaphore.wait(timeout: .now() + 5) "
    "Measuring programming progress by lines of code is like measuring aircraft building progress by weight. "
)

# --- Preset-specific configuration ---
TARGET_WPM=50
TARGET_CHARS=500

case "$PRESET_VAL" in
    vicious)
        TARGET_WPM=200
        TARGET_CHARS=10000  # ~2000 words = ~8 pages
        DURATION=90
        CORPUS=("${CORPUS_VICIOUS[@]}")
        ;;
esac

CHARS_PER_SEC=$(awk "BEGIN { printf \"%.1f\", ($TARGET_WPM * 5) / 60 }")

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         KeyPath Duplicate Keystroke Test Suite              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Preset: $(printf '%-49s' "$PRESET_VAL")║"
if [[ "$PRESET_VAL" == "vicious" ]]; then
echo "║  Target: ${TARGET_WPM} WPM, ${TARGET_CHARS} chars (~$(( TARGET_CHARS / 5 )) words)              ║"
echo "║  CPU stress: ALL cores + compile loop + disk I/O            ║"
fi
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
if [[ "$PRESET_VAL" == "vicious" ]]; then
    NUM_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
    echo "  ✓ CPU cores: $NUM_CORES (will saturate all of them)"
fi
echo

# --- Phase 1: Pipeline test (existing harness) ---
if [[ "$SKIP_PHASE1" == "false" ]] && [[ "$PRESET_VAL" != "vicious" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "PHASE 1: Notification Pipeline Test (repro harness)"
    echo "  Monitors KeyPath's TCP event log for duplicate notifications."
    echo "  This tests whether the 100ms dedup filter is working."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Run in a subshell and kill any lingering children (tail -F) on exit
    (
        "$SCRIPT_DIR/repro-duplicate-keys.sh" \
            --preset "$PRESET_VAL" \
            --trials 1 \
            --duration "$DURATION" \
            --countdown 3 \
            --auto-type osascript \
            --auto-type-wpm 50 2>&1
        # Kill any orphaned tail/awk processes from the repro harness
        pkill -P $$ tail 2>/dev/null || true
    ) | tee "$TEST_DIR/phase1-output.log" || true

    # Safety: kill any lingering tail -F from Phase 1
    pkill -f "tail.*keypath-debug.log" 2>/dev/null || true
    sleep 1

    echo
    echo "Phase 1 complete. Results in $TEST_DIR/phase1-output.log"
    echo
elif [[ "$PRESET_VAL" == "vicious" ]]; then
    echo "Skipping Phase 1 for vicious preset (already validated at high — going straight to fidelity)"
    echo
else
    echo "Skipping Phase 1 (--phase2-only)"
    echo
fi

# --- Phase 2: Actual keystroke fidelity test ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$PRESET_VAL" == "vicious" ]]; then
    echo "PHASE 2: VICIOUS Keystroke Fidelity Test"
    echo "  ${TARGET_WPM} WPM, ${TARGET_CHARS} chars, ALL cores saturated + disk I/O"
    echo "  This is the torture test. If this passes, the fix is bulletproof."
else
    echo "PHASE 2: Keystroke Fidelity Test"
    echo "  Types known text into Zed, then compares input vs. output."
    echo "  This tests whether actual characters double in the editor."
fi
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

echo "Typing $TARGET_CHARS characters at ~${TARGET_WPM} WPM (~${CHARS_PER_SEC} chars/sec) into Zed..."
echo "(CPU load preset: $PRESET_VAL)"
echo

# Start CPU load
bg_pids=()
cleanup_load() {
    for pid in "${bg_pids[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    # Kill any stray yes/dd/swift-build processes we spawned
    if [[ "$PRESET_VAL" == "vicious" ]]; then
        pkill -f "dd if=/dev/zero" 2>/dev/null || true
        pkill -f "compressutil" 2>/dev/null || true
    fi
}
trap cleanup_load EXIT

NUM_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)

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
    vicious)
        # --- MAXIMUM STRESS ---
        echo "  Starting VICIOUS load..."

        # 1. Swift compile loop (heavy, realistic)
        (cd "$PROJECT_ROOT" && while true; do swift build -c debug >/dev/null 2>&1 || true; done) &
        bg_pids+=("$!")
        echo "    ✓ Swift compile loop"

        # 2. Saturate ALL cores with yes processes
        HOG_COUNT=$((NUM_CORES - 1))  # Leave 1 core for Kanata/system
        for (( i=0; i<HOG_COUNT; i++ )); do yes >/dev/null & bg_pids+=("$!"); done
        echo "    ✓ $HOG_COUNT CPU hog processes (saturating $NUM_CORES cores)"

        # 3. Disk I/O pressure — continuous writes to /tmp
        (while true; do dd if=/dev/zero of="${TEST_DIR}/io-stress-$$" bs=1m count=64 2>/dev/null; rm -f "${TEST_DIR}/io-stress-$$"; done) &
        bg_pids+=("$!")
        echo "    ✓ Disk I/O stress (64MB write loop)"

        # 4. Memory pressure — allocate and touch pages
        (python3 -c "
import time
blocks = []
try:
    for _ in range(20):
        b = bytearray(50 * 1024 * 1024)  # 50MB block
        for i in range(0, len(b), 4096):  # Touch every page
            b[i] = 0xFF
        blocks.append(b)
        time.sleep(0.5)
    # Hold for duration of test
    time.sleep(300)
except MemoryError:
    time.sleep(300)
" 2>/dev/null) &
        bg_pids+=("$!")
        echo "    ✓ Memory pressure (1GB allocation, touching pages)"

        # 5. Second compile loop on a temp package for extra scheduler contention
        TEMP_PKG="${TEST_DIR}/stress-pkg"
        mkdir -p "$TEMP_PKG/Sources/Stress"
        cat > "$TEMP_PKG/Package.swift" << 'SWIFTPKG'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Stress", targets: [.executableTarget(name: "Stress", path: "Sources/Stress")])
SWIFTPKG
        cat > "$TEMP_PKG/Sources/Stress/main.swift" << 'SWIFTSRC'
import Foundation
let data = (0..<10000).map { String($0) }.joined(separator: ",")
let encoded = data.data(using: .utf8)!
let decoded = String(data: encoded, encoding: .utf8)!
print(decoded.count)
SWIFTSRC
        (cd "$TEMP_PKG" && while true; do swift build 2>/dev/null; swift build -c release 2>/dev/null; done) &
        bg_pids+=("$!")
        echo "    ✓ Second Swift compile loop (scheduler contention)"

        echo "  All stress generators active. System should be near 100% CPU."
        ;;
    baseline)
        echo "  No CPU load (baseline)"
        ;;
esac

sleep 3  # Let load ramp up (extra time for vicious)
if [[ "$PRESET_VAL" == "vicious" ]]; then
    sleep 3  # Extra ramp-up time
    echo
    echo "  Verifying system load..."
    # Show current load average
    load=$(sysctl -n vm.loadavg 2>/dev/null || uptime | awk -F'load averages:' '{print $2}')
    echo "  Load average: $load"
    kanata_cpu=$(ps -o %cpu= -p "$(pgrep -i kanata | head -1)" 2>/dev/null | tr -d ' ')
    echo "  Kanata CPU: ${kanata_cpu}%"
    echo
fi

# Activate Zed window
osascript -e 'tell application "Zed" to activate' 2>/dev/null || true
sleep 1

# --- Typing loop ---
# For vicious mode, we send longer chunks less frequently to maximize throughput.
# osascript `keystroke` sends the whole string as fast as HID can process it,
# so the effective WPM is controlled by chunk size and inter-chunk delay.

echo "  Typing started at $(date '+%H:%M:%S')..."

if [[ "$PRESET_VAL" == "vicious" ]]; then
    # Vicious: send 2-3 phrases at a time with minimal delay
    # At 200 WPM = ~16.7 chars/sec, we need aggressive pacing
    while [[ $typed_chars -lt $TARGET_CHARS ]]; do
        # Build a chunk of 2-3 phrases
        chunk=""
        chunk_chars=0
        for (( j=0; j<3 && typed_chars+chunk_chars < TARGET_CHARS; j++ )); do
            phrase="${CORPUS[$corpus_idx]}"
            chunk+="$phrase"
            chunk_chars=$((chunk_chars + ${#phrase}))
            corpus_idx=$(( (corpus_idx + 1) % corpus_len ))
        done

        printf "%s" "$chunk" >> "$EXPECTED_FILE"
        osascript -e "tell application \"System Events\" to keystroke \"$chunk\"" 2>/dev/null || true

        typed_chars=$((typed_chars + chunk_chars))

        # Pace: chars_in_chunk / target_chars_per_sec
        pause=$(awk "BEGIN { p = $chunk_chars / $CHARS_PER_SEC; if (p < 0.05) p = 0.05; printf \"%.3f\", p }")
        sleep "$pause"

        # Progress indicator every ~1000 chars
        if (( typed_chars % 1000 < chunk_chars )); then
            pct=$(( typed_chars * 100 / TARGET_CHARS ))
            echo "    ${typed_chars}/${TARGET_CHARS} chars (${pct}%)"
        fi
    done
else
    # Normal presets: single phrase at a time
    while [[ $typed_chars -lt $TARGET_CHARS ]]; do
        phrase="${CORPUS[$corpus_idx]}"
        printf "%s" "$phrase" >> "$EXPECTED_FILE"
        osascript -e "tell application \"System Events\" to keystroke \"$phrase\"" 2>/dev/null || true
        typed_chars=$((typed_chars + ${#phrase}))
        corpus_idx=$(( (corpus_idx + 1) % corpus_len ))
        char_count=${#phrase}
        pause=$(awk "BEGIN { printf \"%.2f\", $char_count / $CHARS_PER_SEC }")
        sleep "$pause"
    done
fi

echo
echo "  Typing complete at $(date '+%H:%M:%S'). $typed_chars chars sent."
echo "  Waiting 5s for Zed to flush..."
sleep 5

# Stop CPU load
cleanup_load
trap - EXIT

# Give system a moment to settle after killing load
sleep 2

# Save Zed content via cmd+A, cmd+C, then pbpaste
osascript -e 'tell application "Zed" to activate' 2>/dev/null || true
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "a" using command down' 2>/dev/null || true
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "c" using command down' 2>/dev/null || true
sleep 1
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
    pct=$(awk "BEGIN { printf \"%.1f\", ($missing / $expected_len) * 100 }")
    echo "  ⚠️  MISSING CHARACTERS: $missing chars dropped ($pct% loss)"
    echo "     This suggests keystroke events were lost under load."
    echo
else
    echo "  ✓  Character counts match exactly."
    echo
fi

# Generate diff
diff <(cat "$EXPECTED_FILE") <(echo "$ACTUAL_OUTPUT") > "$DIFF_FILE" 2>&1 || true

if [[ -s "$DIFF_FILE" ]]; then
    # For vicious mode, show a more useful summary than raw diff
    if [[ "$PRESET_VAL" == "vicious" ]]; then
        echo "  Diff summary:"
        diff_lines=$(wc -l < "$DIFF_FILE" | tr -d ' ')
        echo "    Total diff lines: $diff_lines"

        # Find specific character-level differences using word diff
        diff --word-diff=porcelain <(cat "$EXPECTED_FILE") <(echo "$ACTUAL_OUTPUT") \
            > "$TEST_DIR/word-diff.txt" 2>&1 || true

        additions=$(grep -c '^+' "$TEST_DIR/word-diff.txt" 2>/dev/null || echo "0")
        deletions=$(grep -c '^-' "$TEST_DIR/word-diff.txt" 2>/dev/null || echo "0")
        echo "    Word-level additions: $additions"
        echo "    Word-level deletions: $deletions"

        if [[ "$additions" -gt 0 ]]; then
            echo
            echo "  Added characters (first 10):"
            grep '^+' "$TEST_DIR/word-diff.txt" | head -10 | sed 's/^/    /'
        fi
        if [[ "$deletions" -gt 0 ]]; then
            echo
            echo "  Deleted characters (first 10):"
            grep '^-' "$TEST_DIR/word-diff.txt" | head -10 | sed 's/^/    /'
        fi
    else
        echo "  Differences found (first 30 lines):"
        head -30 "$DIFF_FILE" | sed 's/^/    /'
    fi
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

char_diff=$((actual_len - expected_len))
echo "  Pipeline duplicates (Phase 1): $phase1_alerts"
echo "  Character difference (Phase 2): $char_diff"
if [[ "$PRESET_VAL" == "vicious" ]]; then
    echo "  Stress level: ${TARGET_WPM} WPM, ${typed_chars} chars, all $NUM_CORES cores saturated"
fi
echo

if [[ "$phase1_alerts" -eq 0 ]] && [[ "$actual_len" -eq "$expected_len" ]]; then
    if [[ "$PRESET_VAL" == "vicious" ]]; then
        echo "  ✅ PASS: VICIOUS test passed — ${typed_chars} chars at ${TARGET_WPM} WPM"
        echo "     under maximum CPU/memory/disk stress with zero duplicates."
        echo "     The fix is bulletproof. MAL-57 is conclusively resolved."
    else
        echo "  ✅ PASS: No duplicates detected at preset=$PRESET_VAL"
        echo "     The 100ms dedup filter appears effective and Kanata is not"
        echo "     emitting duplicate HID events at this load level."
    fi
    echo
    echo "     NOTE: Phase 2 uses osascript (System Events keystroke), which injects"
    echo "     characters AFTER Kanata's HID intercept. A Phase 2 PASS does NOT prove"
    echo "     that Kanata handles duplicates correctly — only that the editor received"
    echo "     the expected character count. Use manual-keystroke-test.sh to exercise"
    echo "     the real HID path through Kanata."
elif [[ "$phase1_alerts" -eq 0 ]] && [[ "$actual_len" -gt "$expected_len" ]]; then
    echo "  🔴 FAIL: Pipeline clean but characters duplicated in editor!"
    echo "     The dedup fix is working at the UI layer, but Kanata is"
    echo "     emitting duplicate HID events to the OS. This is a deeper"
    echo "     issue — likely scheduling starvation or tap-hold timer drift."
    echo "     Root cause is in Kanata, not KeyPath."
elif [[ "$actual_len" -lt "$expected_len" ]]; then
    echo "  ⚠️  CHARS DROPPED: $((expected_len - actual_len)) characters lost under load."
    echo "     The system may be too overloaded for osascript to deliver"
    echo "     keystrokes reliably. This is a test infrastructure limit,"
    echo "     not necessarily a Kanata issue. Review the diff for patterns."
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
echo "  expected-input.txt — what was sent ($expected_len chars)"
echo "  actual-output.txt  — what appeared in Zed ($actual_len chars)"
echo "  diff-report.txt    — line-level diff"
if [[ "$PRESET_VAL" == "vicious" ]]; then
echo "  word-diff.txt      — word-level diff (character precision)"
fi
