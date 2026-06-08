#!/bin/bash
set -euo pipefail

# KeyPath named test lanes.
# These lanes intentionally start as filters over the existing safe runner.
# Milestone 4 can narrow SwiftPM test target dependencies once timings show
# which lanes justify package graph changes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

LANE="${1:-${KEYPATH_TEST_LANE:-full}}"
LANE="${LANE#--lane=}"

usage() {
  cat <<'USAGE'
Usage: ./Scripts/test-lane.sh <lane>

Lanes:
  smoke      Fast sanity checks across core parsing, permissions, installer planning, CLI, and layout tracer.
  unit       Pure or mostly pure model/parser/renderer logic.
  appkit     UI-adjacent app logic, services, packs, config, mappers, and rule collections.
  installer  InstallerEngine, wizard, daemon/service lifecycle, and health-check tests.
  snapshot   Visual snapshot tests; sets KEYPATH_SNAPSHOTS=1.
  device     Opt-in real-system installer smoke; requires KEYPATH_E2E_DEVICE=1.
  full       Full safe SwiftPM test suite.

Environment:
  TIMEOUT_SECONDS            Watchdog timeout passed through to run-tests-safe.sh.
  KEYPATH_TEST_VERBOSE_LOGS  Set to 1 for debug-level app diagnostics.
  KEYPATH_TEST_FILTER        Overrides the lane's default Swift test filter.
  KEYPATH_TEST_SKIP          Optional Swift test skip regex.
USAGE
}

run_safe_lane() {
  local lane="$1"
  local default_filter="${2:-}"
  local default_timeout="${3:-240}"
  local default_log="$PROJECT_DIR/test_output.${lane}.txt"

  if [ "$lane" = "full" ]; then
    default_log="$PROJECT_DIR/test_output.safe.txt"
  fi

  export KEYPATH_TEST_LANE="$lane"
  export KEYPATH_TEST_FILTER="${KEYPATH_TEST_FILTER:-$default_filter}"
  export KEYPATH_TEST_LOG="${KEYPATH_TEST_LOG:-$default_log}"
  export TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-$default_timeout}"

  if [ -z "$KEYPATH_TEST_FILTER" ]; then
    unset KEYPATH_TEST_FILTER
  fi

  echo "🛣️  Running KeyPath test lane: $lane"
  "$SCRIPT_DIR/run-tests-safe.sh"
}

case "$LANE" in
  smoke)
    run_safe_lane "$LANE" "KeyPathErrorTests|PermissionOracleFastModeTests|TextToKanataKeyMapperTests|KanataDefseqParserTests|RuleCollectionCatalogTests|InstallerEnginePlanTests|CLISmokeTests|LayoutTracerExporterTests" 120
    ;;
  unit)
    run_safe_lane "$LANE" "KeyPathErrorTests|TextToKanataKeyMapperTests|KanataBehaviorParserTests|KanataBehaviorRendererTests|KanataDefseqParserTests|PhysicalLayoutTests|MappingBehaviorTests|LayerKeyMapperNormalizeTests|LayerKeyMapperLabelTests|LayerKeyInfoExtractionTests|LabelMetadataTests|ConfigApplyTypesTests|VirtualKeyParserTests|QMKLayoutParserTests|HandAssignmentTests|TypingFeelMappingTests|KindaVimTelemetryStoreTests|GlobalHotkeyMatcherTests|VimSequenceObserverTests" 180
    ;;
  appkit)
    run_safe_lane "$LANE" "AppContext|Mapper|RuleCollections|Config|RuntimeCoordinator|Pack|Services|Preferences|Keyboard|MainAppState|ContentView|FDADetection|RecordingCoordinator|RecommendationEngine|Vallack|GenericPack" 240
    ;;
  installer)
    run_safe_lane "$LANE" "InstallerEngine|InstallationWizard|PackageManager|ServiceLifecycle|ServiceHealth|ConfigReloadCoordinator|KanataDaemon|PlistGenerator|PrivilegedExecutor|RecoveryCoordinator|ServiceInstallGuard" 240
    ;;
  snapshot)
    export KEYPATH_SNAPSHOTS=1
    run_safe_lane "$LANE" "KeyPathSnapshotTests" 240
    ;;
  device)
    if [ "${KEYPATH_E2E_DEVICE:-0}" != "1" ]; then
      echo "❌ Device lane requires KEYPATH_E2E_DEVICE=1."
      echo "   This lane can touch real system surfaces; run intentionally."
      exit 2
    fi
    export KEYPATH_TEST_LANE="$LANE"
    echo "🛣️  Running KeyPath test lane: $LANE"
    "$SCRIPT_DIR/test-installer-device.sh"
    ;;
  full)
    run_safe_lane "$LANE" "" "${TIMEOUT_SECONDS:-300}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "❌ Unknown test lane: $LANE"
    echo ""
    usage
    exit 64
    ;;
esac
