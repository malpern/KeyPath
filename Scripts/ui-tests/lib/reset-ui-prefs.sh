#!/bin/bash
# reset-ui-prefs.sh — Reset only UI preferences for overlay test suites.
#
# Unlike reset-defaults.sh (full reset), this preserves:
#   - Wizard/permission state (avoids triggering the first-run wizard)
#   - Helper/service registration
#   - Security & AI keys
#   - Migration state
#
# Use this for overlay/drawer test suites (02-10) that need the system
# to be "green" (helper functional, permissions granted) before testing.
#
# Use reset-defaults.sh for wizard suite (12) or full-reset scenarios.

set -euo pipefail

BUNDLE_ID="com.keypath.KeyPath"

echo "=== Resetting KeyPath UI preferences ==="

# ── Overlay & Inspector Preferences ──────────────────────────────────────────
echo "Clearing overlay and inspector preferences..."

for key in \
    overlayLayoutId \
    overlayKeymapId \
    overlayColorwayId \
    overlayKeymapIncludePunctuation \
    inspectorSettingsSection \
    inspectorSection \
    qmkSearchEnabled \
    typingSoundProfileId \
    typingSoundVolume \
    customKeyboardLayouts \
    launcherWelcomeSeenForBuild \
    OverlayInspectorDebug \
    activeKeymapId \
    keymapIncludesPunctuation \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Feature Flags (safe to reset) ────────────────────────────────────────────
echo "Clearing feature flags..."

for key in \
    CAPTURE_LISTEN_ONLY_ENABLED \
    SIMULATOR_AND_VIRTUAL_KEYS_ENABLED \
    KEYBOARD_SUPPRESSION_DEBUG_ENABLED \
    LEARNING_TIPS_MODE \
    CONTEXT_HUD_LIST_ENABLED \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Preferences Service Keys (non-destructive) ──────────────────────────────
echo "Clearing preferences service keys..."

for key in \
    "KeyPath.Testing.AccessibilityTestMode" \
    "KeyPath.Notifications.Enabled" \
    "KeyPath.Recording.ApplyMappingsDuringRecording" \
    "KeyPath.Recording.IsSequenceMode" \
    "KeyPath.Diagnostics.VerboseKanataLogging" \
    "KeyPath.LeaderKey.Preference" \
    "KeyPath.ContextHUD.DisplayMode" \
    "KeyPath.ContextHUD.TriggerMode" \
    "KeyPath.ContextHUD.Timeout" \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Config Files (backup first) ──────────────────────────────────────────────
CONFIG_DIR="$HOME/.config/keypath"

if [[ -d "$CONFIG_DIR" ]]; then
    echo "Backing up and resetting config files..."

    for file in CustomRules.json RuleCollections.json AppKeymaps.json; do
        if [[ -f "$CONFIG_DIR/$file" ]]; then
            cp "$CONFIG_DIR/$file" "$CONFIG_DIR/${file}.bak" 2>/dev/null || true
            rm "$CONFIG_DIR/$file" 2>/dev/null || true
            echo "  Backed up and removed $file"
        fi
    done
fi

echo "=== UI preferences reset complete ==="
