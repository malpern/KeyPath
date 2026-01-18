#!/bin/bash
# Build statistics viewer
# Shows build times, success rates, and skip/cancellation frequency

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
BUILD_STATS_FILE="$PROJECT_DIR/.build/build-stats.log"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

show_help() {
    echo "Usage: build-stats.sh [command]"
    echo ""
    echo "Commands:"
    echo "  summary     Show summary statistics (default)"
    echo "  recent      Show last 20 builds"
    echo "  today       Show today's builds"
    echo "  skipped     Show all skipped builds"
    echo "  slow        Show builds over 5 seconds"
    echo "  clear       Clear the stats log"
    echo "  raw         Show raw log file"
    echo "  help        Show this help"
    echo ""
}

if [[ ! -f "$BUILD_STATS_FILE" ]]; then
    echo "📊 No build stats yet. Run a build first!"
    exit 0
fi

command="${1:-summary}"

case "$command" in
    summary)
        echo -e "${BOLD}📊 Build Statistics Summary${NC}"
        echo "═══════════════════════════════════════"
        echo ""

        # Count function that handles grep's exit code properly
        count_matches() {
            local pattern="$1"
            local result
            result=$(grep -c "$pattern" "$BUILD_STATS_FILE" 2>/dev/null) || result=0
            echo "$result"
        }

        # Total builds
        total=$(count_matches "STARTED")
        total=${total:-0}
        echo -e "${CYAN}Total builds started:${NC} $total"

        # Successful builds
        success=$(count_matches "SUCCESS")
        success=${success:-0}
        echo -e "${GREEN}Successful builds:${NC}    $success"

        # Failed builds
        failed=$(count_matches "BUILD_FAILED")
        failed=${failed:-0}
        echo -e "${RED}Failed builds:${NC}        $failed"

        # Skipped builds
        skipped_concurrent=$(count_matches "SKIPPED_CONCURRENT")
        skipped_concurrent=${skipped_concurrent:-0}
        skipped_swiftpm=$(count_matches "SKIPPED_SWIFTPM_BUSY")
        skipped_swiftpm=${skipped_swiftpm:-0}
        skipped_total=$((skipped_concurrent + skipped_swiftpm))
        echo -e "${YELLOW}Skipped (concurrent):${NC} $skipped_concurrent"
        echo -e "${YELLOW}Skipped (SwiftPM busy):${NC} $skipped_swiftpm"

        echo ""
        echo -e "${BOLD}Build Times (successful builds)${NC}"
        echo "───────────────────────────────────────"

        if [[ $success -gt 0 ]]; then
            # Extract durations from successful builds (exclude 0 duration entries)
            durations=$(grep "SUCCESS" "$BUILD_STATS_FILE" | sed 's/.*duration_ms=//' | grep -v '^0$' | sort -n)

            if [[ -n "$durations" ]]; then
                # Calculate stats using awk for reliability
                stats=$(echo "$durations" | awk '
                    BEGIN { min=999999999; max=0; sum=0; count=0 }
                    {
                        if ($1 > 0) {
                            if ($1 < min) min = $1
                            if ($1 > max) max = $1
                            sum += $1
                            count++
                            values[count] = $1
                        }
                    }
                    END {
                        if (count > 0) {
                            avg = sum / count
                            mid = int((count + 1) / 2)
                            median = values[mid]
                            printf "%d %d %d %d", min, max, int(avg), median
                        }
                    }
                ')

                if [[ -n "$stats" ]]; then
                    read min max avg median <<< "$stats"
                    echo -e "  ${CYAN}Fastest:${NC}  ${min}ms ($(echo "scale=1; $min/1000" | bc)s)"
                    echo -e "  ${CYAN}Slowest:${NC}  ${max}ms ($(echo "scale=1; $max/1000" | bc)s)"
                    echo -e "  ${CYAN}Average:${NC}  ${avg}ms ($(echo "scale=1; $avg/1000" | bc)s)"
                    echo -e "  ${CYAN}Median:${NC}   ${median}ms ($(echo "scale=1; $median/1000" | bc)s)"
                fi
            fi
        else
            echo "  No successful builds yet"
        fi

        echo ""
        echo -e "${BOLD}Efficiency${NC}"
        echo "───────────────────────────────────────"
        if [[ $total -gt 0 ]]; then
            success_rate=$((success * 100 / total))
            skip_rate=$((skipped_total * 100 / total))
            echo -e "  ${GREEN}Success rate:${NC}     ${success_rate}%"
            echo -e "  ${YELLOW}Skip rate:${NC}        ${skip_rate}% (avoided redundant builds)"
        fi

        echo ""
        echo -e "${BLUE}Log file:${NC} $BUILD_STATS_FILE"
        echo -e "${BLUE}Log size:${NC} $(du -h "$BUILD_STATS_FILE" | cut -f1)"
        ;;

    recent)
        echo -e "${BOLD}📋 Last 20 Builds${NC}"
        echo "═══════════════════════════════════════"
        tail -40 "$BUILD_STATS_FILE" | grep -E "SUCCESS|FAILED|SKIPPED" | tail -20 | while read -r line; do
            if echo "$line" | grep -q "SUCCESS"; then
                duration=$(echo "$line" | sed 's/.*duration_ms=\([0-9]*\)/\1/')
                timestamp=$(echo "$line" | cut -d'|' -f1)
                echo -e "${GREEN}✓${NC} $timestamp - ${duration}ms"
            elif echo "$line" | grep -q "SKIPPED"; then
                timestamp=$(echo "$line" | cut -d'|' -f1)
                reason=$(echo "$line" | grep -o "SKIPPED_[A-Z_]*")
                echo -e "${YELLOW}⏭${NC} $timestamp - $reason"
            elif echo "$line" | grep -q "FAILED"; then
                timestamp=$(echo "$line" | cut -d'|' -f1)
                echo -e "${RED}✗${NC} $timestamp - FAILED"
            fi
        done
        ;;

    today)
        echo -e "${BOLD}📅 Today's Builds${NC}"
        echo "═══════════════════════════════════════"
        today=$(date '+%Y-%m-%d')
        grep "$today" "$BUILD_STATS_FILE" 2>/dev/null || echo "No builds today"
        ;;

    skipped)
        echo -e "${BOLD}⏭️  Skipped Builds${NC}"
        echo "═══════════════════════════════════════"
        grep "SKIPPED" "$BUILD_STATS_FILE" | tail -30
        ;;

    slow)
        echo -e "${BOLD}🐢 Slow Builds (>5s)${NC}"
        echo "═══════════════════════════════════════"
        grep "SUCCESS" "$BUILD_STATS_FILE" | while read -r line; do
            duration=$(echo "$line" | sed 's/.*duration_ms=\([0-9]*\)/\1/')
            if [[ $duration -gt 5000 ]]; then
                timestamp=$(echo "$line" | cut -d'|' -f1)
                echo "$timestamp - ${duration}ms ($(echo "scale=1; $duration/1000" | bc)s)"
            fi
        done
        ;;

    clear)
        echo "🗑️  Clearing build stats..."
        rm -f "$BUILD_STATS_FILE"
        echo "✅ Stats cleared"
        ;;

    raw)
        cat "$BUILD_STATS_FILE"
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        echo "Unknown command: $command"
        show_help
        exit 1
        ;;
esac
