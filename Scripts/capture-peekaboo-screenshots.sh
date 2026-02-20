#!/bin/zsh
# capture-peekaboo-screenshots.sh
#
# Captures System Settings screenshots using Peekaboo for help documentation.
# These are the 3 screenshots that can't be generated via SwiftUI snapshot tests.
#
# Prerequisites:
#   - Peekaboo installed: brew install steipete/tap/peekaboo
#   - KeyPath.app installed in /Applications (for Accessibility/Input Monitoring to show it)
#   - Screen Capture permission granted to Terminal/iTerm
#
# Usage:
#   ./Scripts/capture-peekaboo-screenshots.sh              # capture all 3
#   ./Scripts/capture-peekaboo-screenshots.sh accessibility # capture one
#   ./Scripts/capture-peekaboo-screenshots.sh input-monitoring
#   ./Scripts/capture-peekaboo-screenshots.sh file-picker
#
# Output goes to Sources/KeyPathAppKit/Resources/ alongside existing help images.

set -euo pipefail

OUTPUT_DIR="Sources/KeyPathAppKit/Resources"
TEMP_DIR=$(mktemp -d)
WAIT_LONG=3

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_peekaboo() {
    if ! command -v peekaboo &>/dev/null; then
        echo "ERROR: peekaboo not found. Install with: brew install steipete/tap/peekaboo"
        exit 1
    fi
}

wait_for_app() {
    local app_name="$1"
    local max_seconds="${2:-10}"
    local waited=0
    echo "  Waiting for $app_name to open..."
    while (( waited < max_seconds )); do
        if pgrep -xq "$app_name" 2>/dev/null; then
            sleep 1  # extra settle time after process appears
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "  WARNING: Timed out waiting for $app_name"
    return 1
}

capture_window() {
    local output_file="$1"
    local description="$2"

    echo "  Capturing: $description"
    peekaboo see --app "System Settings" --path "$TEMP_DIR/raw.png" 2>/dev/null || {
        # Fallback: capture frontmost window
        peekaboo see --mode frontmost --path "$TEMP_DIR/raw.png" 2>/dev/null || {
            echo "  ERROR: peekaboo capture failed for $description"
            return 1
        }
    }

    cp "$TEMP_DIR/raw.png" "$OUTPUT_DIR/$output_file"
    echo "  Saved: $OUTPUT_DIR/$output_file"
}

open_system_settings() {
    local pane="$1"
    echo "  Opening System Settings > $pane..."

    case "$pane" in
        accessibility)
            open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ;;
        input-monitoring)
            open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            ;;
    esac

    sleep "$WAIT_LONG"
    wait_for_app "System Settings"
    sleep 1  # let the pane render
}

quit_system_settings() {
    osascript -e 'quit app "System Settings"' 2>/dev/null || true
    sleep 0.5
}

# ---------------------------------------------------------------------------
# Screenshot 1: Accessibility Settings
# ---------------------------------------------------------------------------
capture_accessibility() {
    echo ""
    echo "[1/3] Accessibility Settings"
    echo "  System Settings > Privacy & Security > Accessibility"
    echo ""
    echo "  SETUP: Before capturing, ensure:"
    echo "    - KeyPath.app is in /Applications"
    echo "    - KeyPath is listed in Accessibility (toggled ON)"
    echo ""

    quit_system_settings
    open_system_settings "accessibility"

    capture_window "screenshot-accessibility-settings.png" \
        "Privacy > Accessibility with KeyPath listed"
}

# ---------------------------------------------------------------------------
# Screenshot 2: File Picker (adding kanata binary)
# ---------------------------------------------------------------------------
capture_file_picker() {
    echo ""
    echo "[2/3] File Picker (Add Kanata Binary)"
    echo "  System Settings > Accessibility > + button > Go to Folder"
    echo ""
    echo "  NOTE: This screenshot requires manual interaction."
    echo "  The script will open the Accessibility pane. You need to:"
    echo "    1. Click the + button at bottom of the app list"
    echo "    2. In the file picker, press Cmd+Shift+G (Go to Folder)"
    echo "    3. Type: /Library/KeyPath/bin/kanata"
    echo "    4. Press Enter to navigate there"
    echo "    5. Press Enter again in this terminal to capture"
    echo ""

    quit_system_settings
    open_system_settings "accessibility"

    echo "  Waiting for you to open the file picker dialog..."
    echo "  Press Enter when the Go to Folder sheet is visible."
    read -r

    echo "  Capturing file picker..."
    peekaboo see --mode frontmost --path "$TEMP_DIR/raw.png" 2>/dev/null || {
        echo "  ERROR: peekaboo capture failed"
        return 1
    }
    cp "$TEMP_DIR/raw.png" "$OUTPUT_DIR/screenshot-file-picker.png"
    echo "  Saved: $OUTPUT_DIR/screenshot-file-picker.png"
}

# ---------------------------------------------------------------------------
# Screenshot 3: Input Monitoring
# ---------------------------------------------------------------------------
capture_input_monitoring() {
    echo ""
    echo "[3/3] Input Monitoring Settings"
    echo "  System Settings > Privacy & Security > Input Monitoring"
    echo ""
    echo "  SETUP: Before capturing, ensure:"
    echo "    - KeyPath.app is toggled ON in Input Monitoring"
    echo "    - kanata is toggled ON in Input Monitoring"
    echo ""

    quit_system_settings
    open_system_settings "input-monitoring"

    capture_window "screenshot-input-monitoring.png" \
        "Privacy > Input Monitoring with KeyPath and kanata ON"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_peekaboo

echo "=== Peekaboo Screenshot Capture ==="
echo "Output: $OUTPUT_DIR/"

target="${1:-all}"

case "$target" in
    accessibility)
        capture_accessibility
        ;;
    file-picker)
        capture_file_picker
        ;;
    input-monitoring)
        capture_input_monitoring
        ;;
    all)
        capture_accessibility
        capture_file_picker
        capture_input_monitoring
        ;;
    *)
        echo "Unknown target: $target"
        echo "Usage: $0 [accessibility|file-picker|input-monitoring|all]"
        exit 1
        ;;
esac

quit_system_settings

echo ""
echo "=== Done ==="
echo "Screenshots saved to $OUTPUT_DIR/"
echo ""
echo "Review the captures and re-run individual targets if needed:"
echo "  $0 accessibility"
echo "  $0 input-monitoring"
echo "  $0 file-picker"

# Cleanup
rm -rf "$TEMP_DIR"
