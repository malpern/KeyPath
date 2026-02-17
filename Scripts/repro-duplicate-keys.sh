#!/usr/bin/env bash
# Reproduce accidental duplicate key presses under controlled CPU load.
# Monitors KeyPath log in real time and alerts on N+ consecutive same-key presses,
# excluding navigation and other likely intentional keys by default.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)

LOG_FILE="${LOG_FILE:-$HOME/Library/Logs/KeyPath/keypath-debug.log}"
TRIALS=3
DURATION=90
THRESHOLD=3
PRESET="medium"
COUNTDOWN=5
AUTO_TYPE=""
AUTO_TYPE_WPM=60

# Default ignored keys (includes navigation and common non-text controls).
IGNORE_KEYS="backspace,left,right,up,down,home,end,pageup,pagedown,leftmeta,rightmeta,leftctrl,rightctrl,leftalt,rightalt,leftshift,rightshift,tab,escape,caps,numlock"

# Corpus for automated typing — realistic mix of prose and code.
AUTO_TYPE_CORPUS=(
    "The quick brown fox jumps over the lazy dog. "
    "func handleKeyPress(_ event: KeyEvent) -> Bool { return true } "
    "Programming is the art of telling another human what one wants the computer to do. "
    "let result = try await manager.processEvent(key: .a, modifiers: [.shift]) "
    "if context.permissions.inputMonitoring == .granted { startService() } "
    "The five boxing wizards jump quickly at dawn. "
    "guard let config = ConfigurationService.shared.load() else { return nil } "
    "Pack my box with five dozen liquor jugs. "
    "switch event.type { case .keyDown: handle(event) case .keyUp: release(event) } "
    "How vexingly quick daft zebras jump over the lazy brown fox. "
)

usage() {
    cat <<USAGE
Usage: ./Scripts/repro-duplicate-keys.sh [options]

Options:
  --preset <baseline|medium|high>   Load profile (default: medium)
  --trials <n>                      Number of trials (default: 3)
  --duration <seconds>              Seconds per trial (default: 90)
  --threshold <n>                   Consecutive key threshold (default: 3)
  --ignore-keys <csv>               Comma-separated ignore key list
  --log-file <path>                 KeyPath log path (default: ~/Library/Logs/KeyPath/keypath-debug.log)
  --countdown <seconds>             Countdown before each trial (default: 5)
  --auto-type <osascript|peekaboo>  Generate keystrokes automatically (deterministic)
  --auto-type-wpm <n>               Words per minute for auto-type (default: 60)
  -h, --help                        Show help

Examples:
  ./Scripts/repro-duplicate-keys.sh
  ./Scripts/repro-duplicate-keys.sh --preset high --trials 5 --duration 120
  ./Scripts/repro-duplicate-keys.sh --auto-type osascript --preset high
  ./Scripts/repro-duplicate-keys.sh --ignore-keys "backspace,left,right,up,down"
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)
            PRESET="${2:-}"
            shift 2
            ;;
        --trials)
            TRIALS="${2:-}"
            shift 2
            ;;
        --duration)
            DURATION="${2:-}"
            shift 2
            ;;
        --threshold)
            THRESHOLD="${2:-}"
            shift 2
            ;;
        --ignore-keys)
            IGNORE_KEYS="${2:-}"
            shift 2
            ;;
        --log-file)
            LOG_FILE="${2:-}"
            shift 2
            ;;
        --countdown)
            COUNTDOWN="${2:-}"
            shift 2
            ;;
        --auto-type)
            AUTO_TYPE="${2:-}"
            shift 2
            ;;
        --auto-type-wpm)
            AUTO_TYPE_WPM="${2:-}"
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

# --- Preflight checks ---

preflight_errors=()

# 1. Kanata must be running.
if ! pgrep -iq kanata 2>/dev/null; then
    preflight_errors+=("Kanata is not running. Start KeyPath and ensure the Kanata service is active.")
fi

# 2. Log file must exist (Kanata writes key events here).
if [[ ! -f "$LOG_FILE" ]]; then
    preflight_errors+=("Log file not found: $LOG_FILE
   Kanata may not have started yet, or the log path is wrong (override with --log-file).")
fi

# 3. Accessibility permission required for auto-type via osascript.
if [[ "${AUTO_TYPE:-}" == "osascript" ]]; then
    # Probe by sending a no-op keystroke; System Events will fail if Accessibility is denied.
    if ! osascript -e 'tell application "System Events" to keystroke ""' 2>/dev/null; then
        preflight_errors+=("Accessibility permission denied for auto-type.
   Grant access in System Settings > Privacy & Security > Accessibility for Terminal (or your terminal app).")
    fi
fi

if [[ ${#preflight_errors[@]} -gt 0 ]]; then
    echo "Preflight failed — cannot start repro harness:" >&2
    echo >&2
    for i in "${!preflight_errors[@]}"; do
        echo "  $((i+1)). ${preflight_errors[$i]}" >&2
        echo >&2
    done
    exit 1
fi

case "$PRESET" in
    baseline|medium|high)
        ;;
    *)
        echo "Error: --preset must be baseline, medium, or high" >&2
        exit 1
        ;;
esac

if ! [[ "$TRIALS" =~ ^[0-9]+$ && "$TRIALS" -ge 1 ]]; then
    echo "Error: --trials must be a positive integer" >&2
    exit 1
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ && "$DURATION" -ge 1 ]]; then
    echo "Error: --duration must be a positive integer" >&2
    exit 1
fi

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ && "$THRESHOLD" -ge 2 ]]; then
    echo "Error: --threshold must be an integer >= 2" >&2
    exit 1
fi

if ! [[ "$COUNTDOWN" =~ ^[0-9]+$ && "$COUNTDOWN" -ge 0 ]]; then
    echo "Error: --countdown must be a non-negative integer" >&2
    exit 1
fi

if [[ -n "$AUTO_TYPE" ]]; then
    case "$AUTO_TYPE" in
        osascript)
            ;;
        peekaboo)
            if ! command -v peekaboo &>/dev/null; then
                echo "Error: peekaboo not found. Install with: brew install steipete/tap/peekaboo" >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: --auto-type must be osascript or peekaboo" >&2
            exit 1
            ;;
    esac
fi

if ! [[ "$AUTO_TYPE_WPM" =~ ^[0-9]+$ && "$AUTO_TYPE_WPM" -ge 1 ]]; then
    echo "Error: --auto-type-wpm must be a positive integer" >&2
    exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${TMPDIR:-/tmp}/keypath-duplicate-repro-$timestamp"
mkdir -p "$OUT_DIR"
ALERTS_FILE="$OUT_DIR/alerts.log"
EVENTS_FILE="$OUT_DIR/events.log"
SUMMARY_FILE="$OUT_DIR/summary.txt"
CPU_FILE="$OUT_DIR/cpu.log"
KANATA_FILE="$OUT_DIR/kanata-metrics.log"
ANALYSIS_FILE="$OUT_DIR/analysis-report.txt"

bg_pids=()

cleanup() {
    for pid in "${bg_pids[@]:-}"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done
}
trap cleanup EXIT INT TERM

start_compile_loop() {
    (
        cd "$PROJECT_ROOT"
        while true; do
            swift build -c debug >/dev/null 2>&1 || true
        done
    ) &
    bg_pids+=("$!")
}

start_cpu_hogs() {
    local hog_count=$1
    local i
    for (( i=0; i<hog_count; i++ )); do
        yes >/dev/null &
        bg_pids+=("$!")
    done
}

start_stress() {
    case "$PRESET" in
        baseline)
            ;;
        medium)
            start_compile_loop
            start_cpu_hogs 2
            ;;
        high)
            start_compile_loop
            start_cpu_hogs 6
            ;;
    esac
}

stop_stress() {
    local pid
    for pid in "${bg_pids[@]:-}"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done
    bg_pids=()
}

# --- Automated typing ---

auto_type_osascript() {
    local duration=$1
    local delay_per_char
    # WPM -> delay: average word = 5 chars, so chars/sec = WPM * 5 / 60
    delay_per_char=$(awk "BEGIN { printf \"%.4f\", 60.0 / ($AUTO_TYPE_WPM * 5) }")
    local end_time=$(( $(date +%s) + duration ))
    local corpus_idx=0
    local corpus_len=${#AUTO_TYPE_CORPUS[@]}

    while [[ $(date +%s) -lt $end_time ]]; do
        local text="${AUTO_TYPE_CORPUS[$corpus_idx]}"
        osascript -e "tell application \"System Events\" to keystroke \"$text\"" 2>/dev/null || true
        # Pace to approximate the target WPM
        local char_count=${#text}
        local pause
        pause=$(awk "BEGIN { printf \"%.2f\", $char_count * $delay_per_char }")
        sleep "$pause"
        corpus_idx=$(( (corpus_idx + 1) % corpus_len ))
    done
}

auto_type_peekaboo() {
    local duration=$1
    local end_time=$(( $(date +%s) + duration ))
    local corpus_idx=0
    local corpus_len=${#AUTO_TYPE_CORPUS[@]}

    while [[ $(date +%s) -lt $end_time ]]; do
        local text="${AUTO_TYPE_CORPUS[$corpus_idx]}"
        peekaboo type "$text" --wpm "$AUTO_TYPE_WPM" 2>/dev/null || true
        corpus_idx=$(( (corpus_idx + 1) % corpus_len ))
    done
}

start_auto_type() {
    local duration=$1
    case "$AUTO_TYPE" in
        osascript)
            auto_type_osascript "$duration" &
            bg_pids+=("$!")
            ;;
        peekaboo)
            auto_type_peekaboo "$duration" &
            bg_pids+=("$!")
            ;;
    esac
}

# --- Kanata process metrics sampler ---

start_kanata_metrics() {
    (
        echo "timestamp|epoch_ms|pid|%cpu|%mem|rss_kb|vsz_kb|threads|state|pri" >> "$KANATA_FILE"
        while true; do
            ts=$(date '+%Y-%m-%d %H:%M:%S')
            epoch_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
            # Find kanata process(es) — match the daemon binary.
            # macOS ps doesn't support nlwp; get thread count from /proc or ps -M.
            pids=$(pgrep -i kanata 2>/dev/null) || true
            if [[ -n "$pids" ]]; then
                while IFS= read -r kpid; do
                    metrics=$(ps -o pid=,%cpu=,%mem=,rss=,vsz=,state=,pri= -p "$kpid" 2>/dev/null) || true
                    # Thread count: count lines from ps -M minus the header
                    threads=$(ps -M -p "$kpid" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ') || threads="?"
                    if [[ -n "$metrics" ]]; then
                        echo "$ts|$epoch_ms|$metrics|threads=$threads" >> "$KANATA_FILE"
                    fi
                done <<< "$pids"
            else
                echo "$ts|$epoch_ms|NO_KANATA_PROCESS" >> "$KANATA_FILE"
            fi
            sleep 1
        done
    ) &
    kanata_metrics_pid=$!
    bg_pids+=("$kanata_metrics_pid")
}

echo "KeyPath duplicate-key repro harness"
echo "  log file:      $LOG_FILE"
echo "  preset:        $PRESET"
echo "  trials:        $TRIALS"
echo "  duration:      ${DURATION}s"
echo "  threshold:     $THRESHOLD"
echo "  ignore keys:   $IGNORE_KEYS"
echo "  auto-type:     ${AUTO_TYPE:-manual}"
if [[ -n "$AUTO_TYPE" ]]; then
echo "  auto-type wpm: $AUTO_TYPE_WPM"
fi
echo "  output dir:    $OUT_DIR"
echo

echo "Start time: $(date)" > "$SUMMARY_FILE"
echo "Preset: $PRESET" >> "$SUMMARY_FILE"
echo "Trials: $TRIALS" >> "$SUMMARY_FILE"
echo "Duration: ${DURATION}s" >> "$SUMMARY_FILE"
echo "Threshold: $THRESHOLD" >> "$SUMMARY_FILE"
echo "Ignore keys: $IGNORE_KEYS" >> "$SUMMARY_FILE"
echo "Auto-type: ${AUTO_TYPE:-manual}" >> "$SUMMARY_FILE"
if [[ -n "$AUTO_TYPE" ]]; then
echo "Auto-type WPM: $AUTO_TYPE_WPM" >> "$SUMMARY_FILE"
fi
echo >> "$SUMMARY_FILE"

# Real-time event stream and duplicate detector.
# Each event line includes a high-resolution receive timestamp (ms precision)
# and the delta from the previous event on the same key, which is critical for
# distinguishing debounce issues (<5ms) from scheduling starvation (10-100ms+).
(
    tail -n 0 -F "$LOG_FILE" |
    awk -v threshold="$THRESHOLD" -v ignore_csv="$IGNORE_KEYS" -v events_out="$EVENTS_FILE" -v alerts_out="$ALERTS_FILE" '
        BEGIN {
            split(ignore_csv, raw, ",")
            for (i in raw) {
                gsub(/^ +| +$/, "", raw[i])
                ignore[raw[i]] = 1
            }
            # Use gettimeofday via strftime where available; fall back to log timestamp.
            ms_cmd = "python3 -c \"import time; print(int(time.time()*1000))\" 2>/dev/null"
        }

        /KeyInput: .* press/ {
            log_ts = substr($0, 2, 19)
            line = $0
            sub(/^.*KeyInput: /, "", line)
            sub(/ press.*$/, "", line)
            key = line

            # High-res receive timestamp (ms since epoch).
            ms_cmd | getline now_ms
            close(ms_cmd)
            now_ms = now_ms + 0

            # Delta from previous event on the SAME key.
            if (key in last_ms) {
                delta = now_ms - last_ms[key]
            } else {
                delta = -1
            }
            last_ms[key] = now_ms

            printf "%s|%s|%d|%d\n", log_ts, key, now_ms, delta >> events_out
            fflush(events_out)

            if (ignore[key]) next

            if (key == prev_key) {
                run += 1
                run_deltas = run_deltas "," delta
            } else {
                prev_key = key
                run = 1
                run_start = log_ts
                run_start_ms = now_ms
                run_deltas = ""
            }

            if (run == threshold) {
                span_ms = now_ms - run_start_ms
                msg = sprintf("ALERT|%s|key=%s|run=%d|start=%s|span_ms=%d|deltas_ms=%s", log_ts, key, run, run_start, span_ms, run_deltas)
                print msg
                print msg >> alerts_out
                fflush(alerts_out)
            }
        }
    '
) &
monitor_pid=$!
bg_pids+=("$monitor_pid")

# CPU sampler for correlation.
(
    while true; do
        date '+%Y-%m-%d %H:%M:%S' >> "$CPU_FILE"
        top -l 1 -n 0 -s 0 | head -n 12 >> "$CPU_FILE" 2>/dev/null || true
        echo >> "$CPU_FILE"
        sleep 1
    done
) &
cpu_pid=$!
bg_pids+=("$cpu_pid")

# Kanata process metrics sampler.
start_kanata_metrics

if [[ -n "$AUTO_TYPE" ]]; then
    echo "Detector running. Auto-typing via $AUTO_TYPE at ${AUTO_TYPE_WPM} WPM."
    echo "Ensure a text editor is focused to receive keystrokes."
else
    echo "Detector running. Start typing when trials begin."
    echo "Tip: use normal prose, then your typical coding flow."
fi
echo

for (( trial=1; trial<=TRIALS; trial++ )); do
    echo "=== Trial $trial/$TRIALS ==="
    echo "Trial $trial start: $(date)" | tee -a "$SUMMARY_FILE"

    if [[ "$COUNTDOWN" -gt 0 ]]; then
        echo "Starting in ${COUNTDOWN}s..."
        sleep "$COUNTDOWN"
    fi

    before_alerts=0
    if [[ -f "$ALERTS_FILE" ]]; then
        before_alerts=$(wc -l < "$ALERTS_FILE")
    fi

    start_stress
    if [[ -n "$AUTO_TYPE" ]]; then
        start_auto_type "$DURATION"
        echo "Load active ($PRESET). Auto-typing for ${DURATION}s..."
    else
        echo "Load active ($PRESET). Type continuously for ${DURATION}s..."
    fi
    sleep "$DURATION"
    stop_stress

    after_alerts=0
    if [[ -f "$ALERTS_FILE" ]]; then
        after_alerts=$(wc -l < "$ALERTS_FILE")
    fi

    trial_alerts=$((after_alerts - before_alerts))
    echo "Trial $trial alerts: $trial_alerts" | tee -a "$SUMMARY_FILE"
    echo >> "$SUMMARY_FILE"

    if [[ "$trial" -lt "$TRIALS" ]]; then
        echo "Cooldown 10s..."
        sleep 10
    fi
done

stop_stress
cleanup
trap - EXIT INT TERM

total_alerts=0
if [[ -f "$ALERTS_FILE" ]]; then
    total_alerts=$(wc -l < "$ALERTS_FILE")
fi

echo "End time: $(date)" >> "$SUMMARY_FILE"
echo "Total alerts: $total_alerts" >> "$SUMMARY_FILE"

echo
echo "Generating analysis report..."

# --- Analysis report ---
# Cross-correlates alerts, events, Kanata metrics, and CPU data to produce
# a structured report suitable for root-cause diagnosis.

generate_analysis() {
    local report="$ANALYSIS_FILE"

    cat > "$report" <<HEADER
================================================================================
  KeyPath Duplicate-Key Analysis Report
  Generated: $(date)
  Preset: $PRESET | Trials: $TRIALS | Duration: ${DURATION}s | Threshold: $THRESHOLD
  Auto-type: ${AUTO_TYPE:-manual}${AUTO_TYPE:+ at ${AUTO_TYPE_WPM} WPM}
================================================================================

HEADER

    # --- Section 1: Alert summary ---
    {
        echo "1. ALERT SUMMARY"
        echo "   ─────────────"
        if [[ ! -f "$ALERTS_FILE" ]] || [[ ! -s "$ALERTS_FILE" ]]; then
            echo "   No duplicate-key alerts detected."
            echo
        else
            local alert_count
            alert_count=$(wc -l < "$ALERTS_FILE" | tr -d ' ')
            echo "   Total alerts: $alert_count"
            echo
        fi
    } >> "$report"

    # --- Section 2: Per-key breakdown ---
    {
        echo "2. PER-KEY BREAKDOWN"
        echo "   ─────────────────"
        if [[ -f "$ALERTS_FILE" ]] && [[ -s "$ALERTS_FILE" ]]; then
            echo "   Key          | Alerts | Interpretation"
            echo "   -------------|--------|---------------"
            # Extract key= field, count occurrences, sort descending.
            sed 's/.*key=\([^|]*\).*/\1/' "$ALERTS_FILE" \
                | sort | uniq -c | sort -rn \
                | while read -r count key; do
                    if [[ "$count" -ge 5 ]]; then
                        interp="FREQUENT — likely systemic"
                    elif [[ "$count" -ge 2 ]]; then
                        interp="moderate"
                    else
                        interp="rare — may be intentional"
                    fi
                    printf "   %-13s| %-7s| %s\n" "$key" "$count" "$interp"
                done
            echo
            # Check if all keys affected equally vs specific keys.
            local unique_keys
            unique_keys=$(sed 's/.*key=\([^|]*\).*/\1/' "$ALERTS_FILE" | sort -u | wc -l | tr -d ' ')
            if [[ "$unique_keys" -le 2 ]]; then
                echo "   Observation: Only $unique_keys key(s) affected — suggests key-specific"
                echo "   tap-hold or config issue, not a systemic scheduling problem."
            else
                echo "   Observation: $unique_keys different keys affected — suggests systemic"
                echo "   issue (scheduling starvation or event pipeline delay)."
            fi
        else
            echo "   No alerts to analyze."
        fi
        echo
    } >> "$report"

    # --- Section 3: Inter-event timing analysis (the critical diagnostic) ---
    {
        echo "3. INTER-EVENT TIMING (duplicate gaps)"
        echo "   ────────────────────────────────────"
        if [[ -f "$ALERTS_FILE" ]] && [[ -s "$ALERTS_FILE" ]]; then
            # Extract deltas_ms from alerts and flatten.
            local all_deltas
            all_deltas=$(sed 's/.*deltas_ms=\([^|]*\).*/\1/' "$ALERTS_FILE" \
                | tr ',' '\n' | grep -v '^$' | sort -n)

            if [[ -n "$all_deltas" ]]; then
                local delta_count min_d max_d median_d
                delta_count=$(echo "$all_deltas" | wc -l | tr -d ' ')
                min_d=$(echo "$all_deltas" | head -1)
                max_d=$(echo "$all_deltas" | tail -1)
                median_d=$(echo "$all_deltas" | awk -v n="$delta_count" 'NR==int(n/2)+1{print}')

                echo "   Duplicate event gaps (ms between repeated same-key presses):"
                echo "   Count: $delta_count  Min: ${min_d}ms  Median: ${median_d}ms  Max: ${max_d}ms"
                echo

                # Bucket analysis for root-cause classification.
                local sub5 sub20 sub100 over100
                sub5=$(echo "$all_deltas" | awk '$1 >= 0 && $1 < 5' | wc -l | tr -d ' ')
                sub20=$(echo "$all_deltas" | awk '$1 >= 5 && $1 < 20' | wc -l | tr -d ' ')
                sub100=$(echo "$all_deltas" | awk '$1 >= 20 && $1 < 100' | wc -l | tr -d ' ')
                over100=$(echo "$all_deltas" | awk '$1 >= 100' | wc -l | tr -d ' ')

                echo "   Gap distribution:"
                echo "     <5ms:     $sub5   (hardware bounce / driver debounce failure)"
                echo "     5-20ms:   $sub20   (event pipeline stutter)"
                echo "     20-100ms: $sub100   (Kanata scheduling starvation)"
                echo "     >100ms:   $over100   (tap-hold timer drift or user double-tap)"
                echo

                # Verdict.
                echo "   ROOT CAUSE INDICATORS:"
                if [[ "$sub5" -gt "$sub20" && "$sub5" -gt "$sub100" ]]; then
                    echo "   >>> Majority <5ms: Points to INPUT-LEVEL issue."
                    echo "       Kanata may be receiving pre-duplicated events from the HID driver."
                    echo "       Investigate: IOHIDDevice debounce settings, keyboard firmware."
                elif [[ "$sub100" -gt "$sub5" && "$sub100" -gt "$sub20" ]]; then
                    echo "   >>> Majority 20-100ms: Points to SCHEDULING STARVATION."
                    echo "       Kanata's process is being deprioritized under CPU load, causing"
                    echo "       its event loop to batch-process queued events as rapid repeats."
                    echo "       Investigate: Kanata process priority (nice/renice), real-time"
                    echo "       scheduling, or moving key processing to a higher-priority thread."
                elif [[ "$over100" -gt "$sub5" && "$over100" -gt "$sub100" ]]; then
                    echo "   >>> Majority >100ms: Points to TAP-HOLD TIMER DRIFT."
                    echo "       Kanata's internal timers are misbehaving when the process is"
                    echo "       delayed, causing held keys to be misinterpreted as taps."
                    echo "       Investigate: tap-hold timeout values in keypath.kbd config,"
                    echo "       or use eager-tap / waiting-tap-timeout to reduce sensitivity."
                elif [[ "$sub20" -gt "$sub5" && "$sub20" -gt "$sub100" ]]; then
                    echo "   >>> Majority 5-20ms: Points to EVENT PIPELINE STUTTER."
                    echo "       Brief stalls in the event processing chain (TCP relay,"
                    echo "       log flushing, or SwiftUI observer updates) are causing"
                    echo "       event bunching. Investigate: async event forwarding, TCP"
                    echo "       socket buffering, or log I/O blocking the event thread."
                else
                    echo "   >>> Mixed distribution: No single dominant cause."
                    echo "       Multiple factors may be contributing. Review the raw deltas"
                    echo "       and Kanata metrics for temporal correlation."
                fi
            else
                echo "   No inter-event delta data available."
            fi
        else
            echo "   No alerts — no timing data to analyze."
        fi
        echo
    } >> "$report"

    # --- Section 4: Kanata process health during alerts ---
    {
        echo "4. KANATA PROCESS HEALTH"
        echo "   ─────────────────────"
        if [[ -f "$KANATA_FILE" ]] && [[ -s "$KANATA_FILE" ]]; then
            local kanata_missing
            kanata_missing=$(grep -c "NO_KANATA_PROCESS" "$KANATA_FILE" 2>/dev/null || echo "0")
            local kanata_total
            kanata_total=$(wc -l < "$KANATA_FILE" | tr -d ' ')
            kanata_total=$((kanata_total - 1)) # subtract header

            if [[ "$kanata_missing" -gt 0 ]]; then
                echo "   WARNING: Kanata process was absent for $kanata_missing/${kanata_total} samples."
                echo
            fi

            # Extract CPU% values (skip header and NO_KANATA lines).
            local cpu_vals
            cpu_vals=$(grep -v "NO_KANATA\|timestamp\|^$" "$KANATA_FILE" 2>/dev/null \
                | awk -F'|' '{
                    # The metrics field contains space-separated ps output.
                    # CPU% is the second field in the ps output.
                    split($3, parts, " +")
                    for (i in parts) {
                        if (parts[i] ~ /^[0-9]+\.?[0-9]*$/) { print parts[i]; break }
                    }
                }' 2>/dev/null) || true

            if [[ -n "$cpu_vals" ]]; then
                echo "$cpu_vals" | awk '
                    { sum += $1; count++; vals[count] = $1; if ($1 > max) max = $1 }
                    END {
                        if (count == 0) { print "   No CPU data available."; exit }
                        avg = sum / count
                        # Sort for median/p95
                        asort(vals)
                        med = vals[int(count/2)+1]
                        p95 = vals[int(count*0.95)+1]
                        printf "   Kanata CPU%%:  avg=%.1f%%  median=%.1f%%  p95=%.1f%%  max=%.1f%%\n", avg, med, p95, max
                        if (max > 80) {
                            print "   >>> HIGH CPU: Kanata itself is CPU-bound. Event processing"
                            print "       may be delayed by its own workload, not just OS scheduling."
                        } else if (avg < 5 && max < 20) {
                            print "   >>> LOW CPU: Kanata is mostly idle. Duplicates are likely caused"
                            print "       by scheduling delays (OS not waking Kanata fast enough)."
                        }
                    }
                ' >> "$report"
            else
                echo "   Could not extract Kanata CPU data." >> "$report"
            fi
        else
            echo "   No Kanata metrics collected."
        fi
        echo
    } >> "$report"

    # --- Section 5: Alert timeline with Kanata state ---
    {
        echo "5. ALERT TIMELINE (first 15 alerts with context)"
        echo "   ──────────────────────────────────────────────"
        if [[ -f "$ALERTS_FILE" ]] && [[ -s "$ALERTS_FILE" ]]; then
            echo "   Time                | Key   | Span   | Gap pattern"
            echo "   --------------------|-------|--------|------------------"
            head -n 15 "$ALERTS_FILE" | while IFS='|' read -r _ ts keyf runf startf spanf deltasf _rest; do
                key=$(echo "$keyf" | sed 's/key=//')
                span=$(echo "$spanf" | sed 's/span_ms=//')
                deltas=$(echo "$deltasf" | sed 's/deltas_ms=//')
                printf "   %-20s| %-6s| %5sms| %s\n" "$ts" "$key" "$span" "${deltas}ms"
            done
        else
            echo "   No alerts to display."
        fi
        echo
    } >> "$report"

    # --- Section 6: Recommendations ---
    {
        echo "6. NEXT STEPS"
        echo "   ──────────"
        if [[ ! -f "$ALERTS_FILE" ]] || [[ ! -s "$ALERTS_FILE" ]]; then
            echo "   No duplicates detected at preset=$PRESET."
            echo "   Try: --preset high, or --duration 120 for longer trials."
        else
            echo "   a) Compare presets: run with --preset baseline, then --preset high."
            echo "      If baseline=0 and high>0, CPU load is confirmed as the trigger."
            echo "   b) Review the gap distribution in Section 3 for root-cause category."
            echo "   c) Check Kanata process priority: ps -o pid,pri,nice -p \$(pgrep kanata)"
            echo "   d) Raw data for deeper analysis:"
            echo "        Events:  $EVENTS_FILE  (format: log_ts|key|epoch_ms|delta_ms)"
            echo "        Kanata:  $KANATA_FILE  (format: ts|epoch_ms|pid|cpu|mem|...)"
            echo "        CPU:     $CPU_FILE"
        fi
        echo
        echo "================================================================================"
    } >> "$report"
}

generate_analysis

echo
echo "Run complete."
echo "  Analysis:       $ANALYSIS_FILE"
echo "  Summary:        $SUMMARY_FILE"
echo "  Alerts:         $ALERTS_FILE"
echo "  Events:         $EVENTS_FILE"
echo "  CPU:            $CPU_FILE"
echo "  Kanata metrics: $KANATA_FILE"
echo

# Print the report to stdout as well.
cat "$ANALYSIS_FILE"
