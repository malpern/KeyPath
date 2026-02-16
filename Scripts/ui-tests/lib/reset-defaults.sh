#!/bin/bash
# reset-defaults.sh — Reset all KeyPath persistent state to defaults.
#
# Clears @AppStorage, feature flags, preferences, and config files
# so the app returns to first-launch behavior.
#
# Usage: source this file, or run directly: bash reset-defaults.sh

set -euo pipefail

BUNDLE_ID="com.keypath.KeyPath"

echo "=== Resetting KeyPath defaults ==="

# ── @AppStorage / Layout & Overlay Preferences ────────────────────────────────
echo "Clearing @AppStorage and overlay preferences..."

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
    "LiveKeyboardOverlay.isVisible" \
    "LiveKeyboardOverlay.userExplicitlyHidden" \
    "LiveKeyboardOverlay.lastBuildIdentifier" \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Feature Flags ──────────────────────────────────────────────────────────────
echo "Clearing feature flags..."

for key in \
    CAPTURE_LISTEN_ONLY_ENABLED \
    USE_SMAPPSERVICE_FOR_DAEMON \
    SIMULATOR_AND_VIRTUAL_KEYS_ENABLED \
    USE_JIT_PERMISSION_REQUESTS \
    ALLOW_OPTIONAL_WIZARD \
    KEYBOARD_SUPPRESSION_DEBUG_ENABLED \
    UNINSTALL_FOR_TESTING \
    LEARNING_TIPS_MODE \
    CONTEXT_HUD_LIST_ENABLED \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Preferences Service Keys ──────────────────────────────────────────────────
echo "Clearing preferences service keys..."

for key in \
    "KeyPath.Communication.Protocol" \
    "KeyPath.TCP.ServerPort" \
    "KeyPath.Notifications.Enabled" \
    "KeyPath.Recording.ApplyMappingsDuringRecording" \
    "KeyPath.Recording.IsSequenceMode" \
    "KeyPath.Diagnostics.VerboseKanataLogging" \
    "KeyPath.ActivityLogging.Enabled" \
    "KeyPath.ActivityLogging.ConsentDate" \
    "KeyPath.LeaderKey.Preference" \
    "KeyPath.ContextHUD.DisplayMode" \
    "KeyPath.ContextHUD.TriggerMode" \
    "KeyPath.ContextHUD.Timeout" \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Security & AI Keys ────────────────────────────────────────────────────────
echo "Clearing security and AI keys..."

for key in \
    "KeyPath.Security.ScriptExecutionEnabled" \
    "KeyPath.Security.BypassFirstRunDialog" \
    "KeyPath.Security.ScriptExecutionLog" \
    "KeyPath.AI.CostHistory" \
    "KeyPath.AI.RequireBiometricAuth" \
    "KeyPath.AIKeyRequired.Dismissed" \
    "KeyPath.GlobalHotkey.Enabled" \
    "KeyPath.PermissionRequest.LastRequested" \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Wizard & Permission Keys ──────────────────────────────────────────────────
echo "Clearing wizard and permission keys..."

for key in \
    "KeyPath.WizardRestorePoint" \
    "KeyPath.WizardRestoreTime" \
    wizard_return_to_summary \
    wizard_return_to_accessibility \
    wizard_return_to_input_monitoring \
    wizard_pending_accessibility \
    wizard_pending_input_monitoring \
    wizard_accessibility_timestamp \
    wizard_input_monitoring_timestamp \
    keypath_service_bounce_needed \
    keypath_service_bounce_timestamp \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Migration & Misc Keys ─────────────────────────────────────────────────────
echo "Clearing migration and misc keys..."

for key in \
    "RuleCollections.Migration.LauncherEnabledByDefault" \
    "RuleCollections.Migration.VimEnabledByDefault" \
    HasShownOrphanCleanupAlert \
    LastNotificationSent \
    "KeyPath.lastSeenVersion" \
    "com.keypath.KeyPath.updateChannel" \
; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
done

# ── Config Files (backup first) ───────────────────────────────────────────────
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
else
    echo "No config directory found at $CONFIG_DIR"
fi

echo "=== Reset complete ==="
