#!/bin/bash

# Shared /Applications deploy for release flows.
#
# The bundle is copied verbatim with ditto — never re-signed here. Re-signing
# after notarization changes the cdhash, which detaches the app from its
# notarization ticket and makes stapling the installed copy impossible
# (2026-07-30 RC incident). Both build-and-sign.sh and notarize-resume.sh must
# deploy the exact stapled dist bundle through this function.

kp_deploy_bundle_to_applications() {
    local app_bundle=$1
    local app_name=$2

    # Stop running KeyPath and kanata BEFORE replacing the app bundle.
    # Replacing binaries while the process is live causes macOS to detect
    # code page mismatches and kill the process with:
    #   SIGKILL (Code Signature Invalid) / CODESIGNING / Invalid Page
    # If kanata is killed mid-keystroke, the virtual HID holds the key down
    # and the character repeats infinitely.
    if pgrep -x "$app_name" > /dev/null; then
        echo "🛑 Stopping running $app_name before deploy..."
        killall "$app_name" 2>/dev/null || true

        # Wait up to 5 seconds for graceful shutdown
        local i
        for i in {1..10}; do
            if ! pgrep -x "$app_name" > /dev/null; then
                break
            fi
            sleep 0.5
        done

        # Force kill if still running
        if pgrep -x "$app_name" > /dev/null; then
            echo "   ⚠️  Process still running, force killing..."
            killall -9 "$app_name" 2>/dev/null || true
            sleep 1
        fi
    fi

    # Verify no KeyPath process remains
    if pgrep -x "$app_name" > /dev/null; then
        echo "   ❌ ERROR: Failed to stop $app_name process" >&2
        echo "   Please manually quit $app_name and run the deploy manually." >&2
        return 1
    fi

    # Stop kanata so it doesn't get killed by the bundle replacement.
    if pgrep -x "kanata" > /dev/null; then
        echo "🛑 Stopping kanata service..."
        local kanata_pid
        kanata_pid=$(pgrep -x "kanata")
        sudo kill "$kanata_pid" 2>/dev/null || true
        sleep 1
    fi

    echo "📂 Deploying to /Applications..."
    local app_dest="/Applications/${app_name}.app"
    rm -rf "$app_dest"
    if ditto "$app_bundle" "$app_dest"; then
        echo "✅ Deployed latest $app_name to $app_dest"
    else
        echo "⚠️ WARNING: Failed to copy $app_name to $app_dest" >&2
        echo "💡 TIP: You may need to manually copy $app_bundle to /Applications/" >&2
    fi

    echo "🚪 Restarting app..."
    echo "   Starting new $app_name..."
    open "$app_dest"

    # Wait for new process to start and verify
    sleep 2
    if pgrep -x "$app_name" > /dev/null; then
        local new_pid
        new_pid=$(pgrep -x "$app_name")
        echo "   ✅ $app_name restarted successfully (PID: $new_pid)"
    else
        echo "   ⚠️  WARNING: $app_name may not have started. Run manually: open $app_dest" >&2
    fi
}
