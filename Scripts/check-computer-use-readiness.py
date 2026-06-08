#!/usr/bin/env python3
"""
Source-level contract check for Computer Use reliability.

This complements Scripts/check-accessibility.py. The generic checker verifies
interactive controls have identifiers; this script tracks the high-value IDs,
labels, and values that Computer Use depends on for stable automation.
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_SNIPPETS: dict[str, list[str]] = {
    "Sources/KeyPathAppKit/UI/Overlay/OverlayKeycapView+ContentAndStyling.swift": [
        '"keycap-code-\\(key.keyCode)"',
        ".accessibilityAction",
        "isAutomationClickable",
    ],
    "Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayView.swift": [
        '"keyboard-overlay"',
    ],
    "Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayView+Header.swift": [
        '"overlay-layer-indicator"',
        ".accessibilityValue(layerDisplayName)",
    ],
    "Sources/KeyPathAppKit/UI/Overlay/OverlayDragHeader+LayerPicker.swift": [
        '"layer-picker-new"',
        '"layer-picker-\\(layer)"',
        '"layer-delete-\\(layer)"',
        '"layer-picker-row-\\(layer)"',
        ".accessibilityValue(isCurrentLayer ? \"selected\" : (canDelete ? \"custom\" : \"system\"))",
        ".accessibilityAction(named: \"Select\")",
        "LayerPickerDeleteAccessibilityAction",
        ".accessibilityAction(named: \"Delete\")",
    ],
    "Sources/KeyPathAppKit/UI/Overlay/InspectorPanelToolbar.swift": [
        '"inspector-tab-settings-gear-button"',
        '"inspector-tab-custom-rules"',
        '"inspector-tab-mapper"',
        '"inspector-tab-launchers"',
        '"inspector-tab-history"',
        '"inspector-tab-keymap"',
        '"inspector-tab-layout"',
        '"inspector-tab-keycaps"',
        '"inspector-tab-sounds"',
        '"inspector-tab-devices"',
    ],
    "Sources/KeyPathAppKit/UI/Overlay/OverlayInspectorPanel+CustomRules.swift": [
        '"custom-rules-reset-button"',
        '"custom-rules-new-button"',
        '"active-chords-edit-button"',
    ],
    "Sources/KeyPathAppKit/UI/Overlay/OverlayInspectorPanel+Keymaps.swift": [
        '"overlay-keymap-button-system"',
        '"system-keymap-settings-link"',
        '"international-physical-layouts-link"',
    ],
    "Sources/KeyPathAppKit/UI/Settings/SettingsContainerView.swift": [
        '"settings-window"',
        '"settings-shortcut-status-button"',
        ".openSettingsSystemStatus",
        ".openSettingsLogs",
    ],
    "Sources/KeyPathAppKit/UI/Settings/SettingsView.swift": [
        '"status-system-health-button"',
        ".accessibilityValue(overallHealthLevel.accessibilityValue)",
        '"status-active-rules-button"',
        '"status-service-toggle"',
    ],
    "Sources/KeyPathAppKit/UI/Settings/SettingsView+General.swift": [
        '"settings-key-label-style-picker"',
        '"settings-unmapped-layer-keys-picker"',
        '"settings-capture-mode-picker"',
        '"settings-recording-behavior-picker"',
        '"settings-open-keypath-log-button"',
        '"settings-open-kanata-log-button"',
        '"settings-import-karabiner-button"',
        '"settings-virtual-keys-section"',
        '"settings-layer-indicator-toggle"',
        '"settings-verbose-logging-toggle"',
    ],
    "Sources/KeyPathAppKit/UI/Settings/AdvancedSettingsTabView.swift": [
        '"settings-uninstall-button"',
        '"settings-reset-everything-button"',
        '"settings-uninstall-helper-button"',
        '"settings-open-simulator-button"',
        '"settings-remove-duplicates-button"',
        '"settings-restore-backup-\\(index)"',
    ],
    "Sources/KeyPathAppKit/UI/Settings/SettingsView+ScriptExecution.swift": [
        '"settings-script-execution-toggle"',
        '"settings-script-bypass-dialog-toggle"',
        '"settings-script-execution-log-button"',
        '"settings-script-clear-log-button"',
        '"settings-script-clear-log-confirm"',
        '"settings-script-clear-log-cancel"',
    ],
    "Sources/KeyPathAppKit/UI/Status/SettingsSystemStatusRows.swift": [
        '"settings-status-row-button-\\(id)"',
        ".accessibilityValue(accessibilityValue)",
    ],
    "Sources/KeyPathAppKit/Services/ActionDispatcher.swift": [
        '"settings"',
        "handleSettings",
        "onSettingsAction",
        "onSettingsNavigationAction",
        "SettingsNavigationUserInfo.ruleCollectionTarget",
        "openPreferencesTab(notification, userInfo: userInfo)",
    ],
    "Sources/KeyPathAppKit/Utilities/Notifications.swift": [
        "SettingsNavigationCoordinator",
        "ruleCollectionTarget",
    ],
    "Sources/KeyPathAppKit/UI/Rules/RulesSummaryView+CollectionRow.swift": [
        '"rules-summary-icon-button-\\(collectionId)"',
        '"rules-summary-expand-button-\\(collectionId)"',
        ".accessibilityValue(effectiveEnabled ? \"on\" : \"off\")",
        '"rules-summary-add-rule-\\(collectionId)"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/RulesSummaryView+MappingRow.swift": [
        '"rules-summary-mapping-row-button-\\(mapping.id)"',
        '"rules-summary-mapping-edit-\\(mapping.id)"',
        '"rules-summary-mapping-delete-\\(mapping.id)"',
        ".accessibilityValue(\"\\(prettyKeyName(mapping.input)) to \\(prettyKeyName(mapping.output))\")",
    ],
    "Sources/KeyPathAppKit/UI/Rules/RulesSummaryView+MappingTable.swift": [
        '"rules-mapping-table-row-\\(mapping.id)"',
        "mappingAccessibilityValue",
    ],
    "Sources/KeyPathAppKit/UI/Rules/RulesSummaryView.swift": [
        "focusRuleCollection(from:",
        "collectionMatchesNavigationTarget",
    ],
    "Sources/KeyPathAppKit/UI/Rules/CustomRulesView+Subviews.swift": [
        '"custom-rules-inline-input"',
        '"custom-rules-inline-input-menu"',
        '"custom-rules-inline-output"',
        '"custom-rules-inline-output-menu"',
        '"custom-rules-inline-add-button"',
        '"custom-rules-inline-title"',
        '"custom-rules-inline-notes"',
        '"custom-rules-toggle-\\(rule.id)"',
        '"custom-rules-menu-\\(rule.id)"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/AppRuleRow.swift": [
        '"app-rule-row-\\(override.id)"',
        '"app-rule-delete-\\(override.id)"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/AppRuleRowCompact.swift": [
        '"app-rule-row-compact-input-\\(override.id)"',
        '"app-rule-row-compact-button-\\(override.id)"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/MappingBehaviorEditor.swift": [
        '"mapping-behavior-mode-picker"',
        '"mapping-behavior-type-picker"',
        '"mapping-behavior-tap-action-field"',
        '"mapping-behavior-hold-action-field"',
        '"mapping-behavior-tap-timeout-stepper"',
        '"mapping-behavior-hold-timeout-stepper"',
        '"mapping-behavior-tap-dance-window-stepper"',
        '"mapping-behavior-tap-dance-step-\\(index)-field"',
        '"mapping-behavior-add-step-button"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/ChordGroupsCollectionView.swift": [
        '"chord-groups-show-details-button"',
        '"chord-groups-open-modal-button"',
        '"chord-groups-menu"',
        '"chord-groups-load-preset-button"',
        '"chord-groups-create-custom-button"',
        '"chord-groups-group-picker"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/ChordGroupsModalView.swift": [
        '"chord-groups-modal"',
        '"chord-groups-add-group-button"',
        '"chord-group-category-picker"',
        '"chord-group-add-chord-button"',
        '"chord-group-row-\\(group.id)"',
        '"chord-edit-button-\\(chord.id)"',
        '"chord-delete-button-\\(chord.id)"',
        '"chord-groups-modal-save-button"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/LauncherMappingEditor.swift": [
        '"launcher-editor-enabled-toggle"',
        '"launcher-editor-key-field"',
        '"launcher-editor-type-picker"',
        '"launcher-editor-app-name-field"',
        '"launcher-editor-url-field"',
        '"launcher-editor-folder-path-field"',
        '"launcher-editor-script-browse-button"',
        '"launcher-editor-keystroke-field"',
        '"launcher-editor-system-action-picker"',
        '"launcher-editor-save-button"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/HomeRowModsCollectionView.swift": [
        '"home-row-mods-config-panel"',
        "homeRowModsAccessibilityValue",
        '"🧪 [QA] Home Row Mods config changed:',
    ],
    "Sources/KeyPathAppKit/UI/Rules/HomeRowModsCollectionView+Configuration.swift": [
        '"home-row-mods-preferences-panel"',
        '"home-row-mods-hold-mode-picker"',
        '"home-row-mods-new-layer-sheet"',
    ],
    "Sources/KeyPathAppKit/UI/Rules/HomeRowKeyboardView.swift": [
        '"home-row-key-chip-\\(key)"',
        ".accessibilityValue(accessibilityValue)",
    ],
    "Sources/KeyPathAppKit/UI/Rules/HomeRowTimingSection.swift": [
        '"home-row-mods-feel-slider"',
        '"home-row-mods-tap-window-field"',
        '"home-row-mods-hold-delay-field"',
        '"home-row-mods-prior-idle-field"',
        '"home-row-mods-fast-typing-protection-toggle"',
        '"home-row-mods-quick-tap-term-field"',
        '"home-row-mods-finger-\\(finger.rawValue)-field"',
        '"home-row-mods-tap-offset-\\(key)-field"',
        '"home-row-mods-hold-offset-\\(key)-field"',
        "automationIntegerField",
    ],
    "Sources/KeyPathAppKit/UI/Rules/HomeRowLayerTogglesCollectionView.swift": [
        '"home-row-layer-toggles-mode-picker"',
        '"home-row-layer-toggles-preset-picker"',
        '"home-row-layer-toggles-key-selection-picker"',
        '"home-row-layer-toggles-tap-window-field"',
        '"home-row-layer-toggles-hold-delay-field"',
        '"home-row-layer-toggles-quick-tap-term-slider"',
        '"home-row-layer-toggles-tap-offset-\\(key)-field"',
        "automationIntegerField",
    ],
    "Sources/KeyPathAppKit/UI/Rules/HomeRowLayerTogglesModalView.swift": [
        '"home-row-layer-toggles-modal-mode-picker"',
        '"home-row-layer-toggles-modal-preset-picker"',
        '"home-row-layer-toggles-modal-key-selection-picker"',
        '"home-row-layer-toggles-modal-tap-window-field"',
        '"home-row-layer-toggles-modal-hold-delay-field"',
        '"home-row-layer-toggles-modal-quick-tap-term-slider"',
        '"home-row-layer-toggles-modal-tap-offset-\\(key)-field"',
        '"home-row-layer-toggles-modal-hold-offset-\\(key)-field"',
        "automationIntegerField",
    ],
    "Sources/KeyPathAppKit/UI/Rules/LauncherDrawerView.swift": [
        '"launcher-card-\\(mapping.key)"',
        '"launcher-card-toggle-\\(mapping.key)"',
        ".accessibilityValue(mapping.isEnabled ? \"enabled\" : \"disabled\")",
        ".accessibilityAction(named: \"Edit\")",
        ".accessibilityAction(named: mapping.isEnabled ? \"Disable\" : \"Enable\")",
        ".accessibilityAction(named: \"Delete\")",
    ],
    "Sources/KeyPathAppKit/UI/Overlay/OverlayLaunchersSection.swift": [
        '"overlay-launcher-row-\\(mapping.key)"',
        '"overlay-launcher-toggle-\\(mapping.key)"',
        '"overlay-launcher-delete-\\(mapping.key)"',
        ".accessibilityValue(isEnabled ? \"enabled\" : \"disabled\")",
        ".accessibilityAction(named: \"Edit\")",
        ".accessibilityAction(named: isEnabled ? \"Disable\" : \"Enable\")",
        ".accessibilityAction(named: \"Delete\")",
    ],
    "Sources/KeyPathAppKit/UI/Rules/SequencesModalView.swift": [
        '"sequences-modal-name-field"',
        '"sequences-modal-key-picker-\\(index)"',
        '"sequences-modal-layer-picker"',
        '"sequences-modal-timeout-slider"',
        '"sequences-modal-save-button"',
    ],
    "Sources/KeyPathAppKit/UI/Gallery/PackDetailView.swift": [
        '"pack-detail-close"',
        '"pack-detail-dismiss"',
        '"pack-detail-help"',
        '"pack-detail-toggle"',
        '"pack-detail-quick-setting-\\(setting.id)"',
    ],
    "Sources/KeyPathAppKit/UI/Gallery/SystemPackComponentsView.swift": [
        '"system-pack-card-\\(title.lowercased().replacingOccurrences(of: \" \", with: \"-\"))"',
        '"system-pack-layer-tab-\\(id)"',
    ],
    "Sources/KeyPathAppKit/UI/Settings/VirtualKeysInspectorView.swift": [
        '"virtual-keys-refresh-button"',
        '"virtual-keys-source-badge"',
        '"virtual-keys-copy-button-\\(key.name)"',
        '"virtual-keys-test-button-\\(key.name)"',
    ],
    "Sources/KeyPathAppKit/UI/Components/AccessibleIntegerField.swift": [
        "NSViewRepresentable",
        "AccessibilitySettableIntegerTextField",
        "override func setAccessibilityValue",
        "onAccessibilityValueChanged",
        "parent.onValueChanged(nextValue)",
    ],
    "Sources/KeyPathCLI/Commands/Config/ConfigCommand.swift": [
        "ConfigBackup.self",
        "ConfigRestore.self",
    ],
    "Sources/KeyPathCLI/Commands/Collection/CollectionShowCommand.swift": [
        "var full: Bool",
        "showCollectionDetail",
    ],
}

FORBIDDEN_SNIPPETS: dict[str, list[str]] = {
    "Sources/KeyPathAppKit/UI/Overlay/OverlayKeyboardView.swift": [
        '"overlay-keyboard"',
    ],
}


def main() -> int:
    failures: list[str] = []

    for relative_path, snippets in REQUIRED_SNIPPETS.items():
        path = ROOT / relative_path
        if not path.exists():
            failures.append(f"Missing file: {relative_path}")
            continue

        contents = path.read_text()
        for snippet in snippets:
            if snippet not in contents:
                failures.append(f"{relative_path}: missing required snippet {snippet!r}")

    for relative_path, snippets in FORBIDDEN_SNIPPETS.items():
        path = ROOT / relative_path
        if not path.exists():
            continue

        contents = path.read_text()
        for snippet in snippets:
            if snippet in contents:
                failures.append(f"{relative_path}: forbidden snippet still present {snippet!r}")

    if failures:
        print("Computer Use readiness check failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("Computer Use readiness source contracts passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
