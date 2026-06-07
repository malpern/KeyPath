#!/usr/bin/env bash
set -euo pipefail

keypath_test_lane_filter() {
    local lane
    lane=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

    case "$lane" in
        fast|unit|units)
            echo "KeyAction|MappingBehavior|ConfigApply|GenericPackConfig|HomeRowModsConfig|MapperKanataFormat|LabelMetadata|PackRegistry|RuleCollection|CustomRule|KeymapMappingGenerator|RecommendationEngine|JapaneseInputMode|LayerKeyInfoExtraction|PackDependency|PackOwnership|PackSummary"
            ;;
        integration|integrations)
            echo "Integration|Golden|PackInstall|TCPClient|TcpServer|ProcessLifecycle|InstallerEngine|ServiceBootstrapper|PermissionOracle|FDADetection|SystemRequirements|RuntimeCoordinator"
            ;;
        visual|snapshot|snapshots)
            echo "KeyPathSnapshotTests|Snapshot"
            ;;
        cli|command|commands)
            echo "CLI|Command|Facade|PackageManager|AIConfigGeneration"
            ;;
        config|configuration|kanata)
            echo "Config|KanataFormat|Golden|MapperKanataFormat|HomeRowModsConfig|GenericPackConfig|SimpleMods"
            ;;
        installer|install|wizard|service)
            echo "Installer|ServiceBootstrapper|PermissionOracle|SystemValidator|PrivilegedOperations|Wizard|Daemon|Helper"
            ;;
        packs|pack|gallery)
            echo "Pack|Collection|Vallack|RecommendationEngine"
            ;;
        rules|rule|rulecollections|rule-collections)
            echo "RuleCollection|RuleCollections|CustomRule|MapperConflict|PackCollection"
            ;;
        layout|layouts|tracer|keyboard)
            echo "LayoutTracer|PhysicalLayout|KeyboardLayout|KeyboardDetection|Keymap"
            ;;
        ui|overlay|viewmodel|viewmodels)
            echo "ViewModel|Overlay|KeyboardVisualization|ContentView|PackDetailWindow|MapperViewModel|WindowManager"
            ;;
        tcp|runtime|daemon)
            echo "TCP|Tcp|RuntimeCoordinator|ProcessLifecycle|ServiceHealth|KanataDaemon"
            ;;
        *)
            return 1
            ;;
    esac
}

keypath_test_lane_reason_for_path() {
    local path="$1"

    case "$path" in
        Sources/KeyPathCLI/*|Sources/KeyPathCLIMain/*|Tests/KeyPathTests/CLI/*)
            echo "cli"
            ;;
        Sources/KeyPathInstallationWizard/*|Sources/KeyPathWizardCore/*|Sources/KeyPathDaemonLifecycle/*|Sources/KeyPathHelper/*|Tests/KeyPathTests/*Installer*|Tests/KeyPathTests/*Wizard*)
            echo "installer"
            ;;
        Sources/KeyPathLayoutTracer*/*|Tests/KeyPathLayoutTracerTests/*)
            echo "layout"
            ;;
        Tests/KeyPathSnapshotTests/*)
            echo "visual"
            ;;
        Sources/KeyPathAppKit/UI/*|Tests/KeyPathTests/UI/*)
            echo "ui"
            ;;
        Sources/KeyPathAppKit/Services/Packs/*|Sources/KeyPathAppKit/Resources/Packs/*|Tests/KeyPathTests/*Pack*)
            echo "packs"
            ;;
        Sources/KeyPathAppKit/Services/RuleCollections/*|Sources/KeyPathAppKit/UI/Rules/*|Tests/KeyPathTests/*Rule*)
            echo "rules"
            ;;
        Sources/KeyPathAppKit/Services/Kanata/*|Sources/KeyPathAppKit/Services/Monitoring/*|Tests/KeyPathTests/*TCP*|Tests/KeyPathTests/*Runtime*)
            echo "tcp"
            ;;
        Sources/KeyPathAppKit/Services/Configuration*|Sources/KeyPathAppKit/Services/Config*|Tests/KeyPathTests/*Config*)
            echo "config"
            ;;
        Sources/KeyPathAppKit/Models/*|Sources/KeyPathCore/*|Tests/KeyPathTests/Models/*)
            echo "fast"
            ;;
        *)
            return 1
            ;;
    esac
}

keypath_join_filters() {
    local IFS='|'
    echo "$*"
}
