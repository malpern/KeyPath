#!/bin/bash
set -euo pipefail

# KeyPath named test lanes.
# Most lanes are filters over the existing safe runner. The default smoke lane
# uses an isolated SwiftPM harness so local sanity checks avoid the AppKit graph.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

LANE="${1:-${KEYPATH_TEST_LANE:-full}}"
LANE="${LANE#--lane=}"

usage() {
  cat <<'USAGE'
Usage: ./Scripts/test-lane.sh <lane>

Lanes:
  smoke      Fast isolated sanity checks against core products.
  smoke-root Root-package smoke target; useful for diagnostics, not the fast path.
  core-isolated
             Experimental isolated Core harness; must avoid the KeyPathAppKit graph.
  unit       Fast root-package model/parser/renderer logic; may compile AppKit-facing targets.
  appkit     UI-adjacent app logic, services, packs, config, mappers, and rule collections.
  installer  InstallerEngine, wizard, daemon/service lifecycle, and health-check tests.
  snapshot   Visual snapshot tests; sets KEYPATH_SNAPSHOTS=1.
  device     Opt-in real-system installer smoke; requires KEYPATH_E2E_DEVICE=1.
  full       Full safe SwiftPM test suite.

Environment:
  TIMEOUT_SECONDS            Watchdog timeout passed through to run-tests-safe.sh.
  KEYPATH_TEST_VERBOSE_LOGS  Set to 1 for debug-level app diagnostics.
  KEYPATH_TEST_PREBUILD      Set to 0 to let swift test handle the build.
  KEYPATH_TEST_RESET_MODULE_CACHE
                             Set to 0 to reuse the Swift module cache.
  KEYPATH_TEST_FILTER        Overrides the lane's default Swift test filter.
  KEYPATH_TEST_SKIP          Optional Swift test skip regex.
  KEYPATH_ISOLATED_SMOKE_CLEAN
                             Set to 1 to remove the isolated harness build dir first.
  KEYPATH_ISOLATED_SMOKE_ALLOW_APPKIT
                             Set to 1 to allow KeyPathAppKit mentions in the isolated lane log.
  KEYPATH_ISOLATED_CORE_CLEAN
                             Set to 1 to remove the isolated Core harness build dir first.
  KEYPATH_ISOLATED_CORE_ALLOW_APPKIT
                             Set to 1 to allow KeyPathAppKit mentions in the isolated Core log.
USAGE
}

run_safe_lane() {
  local lane="$1"
  local default_filter="${2:-}"
  local default_timeout="${3:-240}"
  local default_reset_module_cache="${4:-1}"
  local default_log="$PROJECT_DIR/test_output.${lane}.txt"

  if [ "$lane" = "full" ]; then
    default_log="$PROJECT_DIR/test_output.safe.txt"
  fi

  export KEYPATH_TEST_LANE="$lane"
  export KEYPATH_TEST_FILTER="${KEYPATH_TEST_FILTER:-$default_filter}"
  export KEYPATH_TEST_LOG="${KEYPATH_TEST_LOG:-$default_log}"
  export KEYPATH_TEST_RESET_MODULE_CACHE="${KEYPATH_TEST_RESET_MODULE_CACHE:-$default_reset_module_cache}"
  export TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-$default_timeout}"

  if [ -z "$KEYPATH_TEST_FILTER" ]; then
    unset KEYPATH_TEST_FILTER
  fi

  echo "🛣️  Running KeyPath test lane: $lane"
  "$SCRIPT_DIR/run-tests-safe.sh"
}

run_isolated_smoke_lane() {
  local lane="${1:-smoke}"
  local harness_dir="$PROJECT_DIR/dev-tools/smoke-harness"
  local log_path="${KEYPATH_TEST_LOG:-$PROJECT_DIR/test_output.${lane}.txt}"
  local build_path="${KEYPATH_ISOLATED_SMOKE_BUILD_PATH:-$harness_dir/.build}"

  if [ "${KEYPATH_ISOLATED_SMOKE_CLEAN:-0}" = "1" ]; then
    rm -rf "$build_path"
  fi

  mkdir -p "$(dirname "$log_path")"

  echo "🛣️  Running KeyPath test lane: $lane"
  echo "📦 Harness: $harness_dir"
  echo "🧱 Build path: $build_path"
  echo "📄 Log: $log_path"

  local start elapsed exit_code
  start="$(date +%s)"
  set +e
  (
    cd "$harness_dir"
    SWIFT_TEST=1 \
      SKIP_EVENT_TAP_TESTS=1 \
      KEYPATH_LOG_LEVEL="${KEYPATH_LOG_LEVEL:-3}" \
      swift test \
        --scratch-path "$build_path" \
        --disable-xctest
  ) 2>&1 | tee "$log_path"
  exit_code="${PIPESTATUS[0]}"
  set -e
  elapsed="$(( $(date +%s) - start ))"

  local appkit_compiles=0
  if grep -q "KeyPathAppKit" "$log_path"; then
    appkit_compiles=1
  fi

  echo "📊 Isolated smoke summary: exit=$exit_code total=${elapsed}s appkit_in_log=$appkit_compiles log=$(wc -c < "$log_path") bytes"

  if [ "$appkit_compiles" = "1" ]; then
    echo "⚠️  Isolated smoke log mentioned KeyPathAppKit; cold-build isolation was not proven."
    if [ "${KEYPATH_ISOLATED_SMOKE_ALLOW_APPKIT:-0}" != "1" ]; then
      return 1
    fi
  fi

  return "$exit_code"
}

run_isolated_core_lane() {
  local lane="${1:-core-isolated}"
  local harness_dir="$PROJECT_DIR/dev-tools/core-harness"
  local log_path="${KEYPATH_TEST_LOG:-$PROJECT_DIR/test_output.${lane}.txt}"
  local build_path="${KEYPATH_ISOLATED_CORE_BUILD_PATH:-$harness_dir/.build}"

  if [ "${KEYPATH_ISOLATED_CORE_CLEAN:-0}" = "1" ]; then
    rm -rf "$build_path"
  fi

  mkdir -p "$(dirname "$log_path")"

  echo "🛣️  Running KeyPath test lane: $lane"
  echo "📦 Harness: $harness_dir"
  echo "🧱 Build path: $build_path"
  echo "📄 Log: $log_path"

  local start elapsed exit_code
  start="$(date +%s)"
  set +e
  (
    cd "$harness_dir"
    SWIFT_TEST=1 \
      SKIP_EVENT_TAP_TESTS=1 \
      KEYPATH_LOG_LEVEL="${KEYPATH_LOG_LEVEL:-3}" \
      swift test \
        --scratch-path "$build_path" \
        --disable-xctest
  ) 2>&1 | tee "$log_path"
  exit_code="${PIPESTATUS[0]}"
  set -e
  elapsed="$(( $(date +%s) - start ))"

  local appkit_compiles=0
  if grep -q "KeyPathAppKit" "$log_path"; then
    appkit_compiles=1
  fi

  echo "📊 Isolated Core summary: exit=$exit_code total=${elapsed}s appkit_in_log=$appkit_compiles log=$(wc -c < "$log_path") bytes"

  if [ "$appkit_compiles" = "1" ]; then
    echo "⚠️  Isolated Core log mentioned KeyPathAppKit; cold-build isolation was not proven."
    if [ "${KEYPATH_ISOLATED_CORE_ALLOW_APPKIT:-0}" != "1" ]; then
      return 1
    fi
  fi

  return "$exit_code"
}

case "$LANE" in
  smoke)
    run_isolated_smoke_lane "$LANE"
    ;;
  core-isolated)
    run_isolated_core_lane "$LANE"
    ;;
  smoke-root)
    export KEYPATH_TEST_PREBUILD="${KEYPATH_TEST_PREBUILD:-0}"
    export KEYPATH_TEST_DISABLE_XCTEST="${KEYPATH_TEST_DISABLE_XCTEST:-1}"
    export KEYPATH_TEST_RESET_MODULE_CACHE="${KEYPATH_TEST_RESET_MODULE_CACHE:-0}"
    run_safe_lane "$LANE" "KeyPathSmokeTests" 120
    ;;
  unit)
    run_safe_lane "$LANE" "KeyPathErrorTests|TextToKanataKeyMapperTests|KanataBehaviorParserTests|KanataBehaviorRendererTests|KanataDefseqParserTests|PhysicalLayoutTests|MappingBehaviorTests|LayerKeyMapperNormalizeTests|LayerKeyMapperLabelTests|LayerKeyInfoExtractionTests|LabelMetadataTests|ConfigApplyTypesTests|VirtualKeyParserTests|QMKLayoutParserTests|HandAssignmentTests|TypingFeelMappingTests|KindaVimTelemetryStoreTests|GlobalHotkeyMatcherTests|VimSequenceObserverTests" 180 0
    ;;
  appkit)
    run_safe_lane "$LANE" "AppContext|Mapper|RuleCollections|Config|RuntimeCoordinator|Pack|Services|Preferences|Keyboard|MainAppState|ContentView|FDADetection|RecordingCoordinator|RecommendationEngine|Vallack|GenericPack" 240 0
    ;;
  installer)
    run_safe_lane "$LANE" "InstallerEngine|InstallationWizard|PackageManager|ServiceLifecycle|ServiceHealth|ConfigReloadCoordinator|KanataDaemon|PlistGenerator|PrivilegedExecutor|RecoveryCoordinator|ServiceInstallGuard" 240 0
    ;;
  snapshot)
    export KEYPATH_SNAPSHOTS=1
    run_safe_lane "$LANE" "KeyPathSnapshotTests" 240 0
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
    run_safe_lane "$LANE" "" "${TIMEOUT_SECONDS:-300}" 0
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
