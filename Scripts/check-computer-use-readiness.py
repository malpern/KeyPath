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
        '"home-row-mods-fast-typing-protection-toggle"',
        '"home-row-mods-tap-offset-\\(key)-field"',
        '"home-row-mods-hold-offset-\\(key)-field"',
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
