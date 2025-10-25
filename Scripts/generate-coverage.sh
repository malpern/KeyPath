#!/usr/bin/env bash
# Generate Swift code coverage for KeyPath
# - Runs tests with coverage (or reuses existing .profdata)
# - Exports summary, LCOV, and text reports to dist/coverage

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage: Scripts/generate-coverage.sh [options]

Options:
  --full            Run full test suite (no filter). Default is UnitTestSuite.
  --filter NAME     Run tests filtered to NAME (overrides default).
  --reuse           Do not run tests; reuse existing .build/*/codecov/default.profdata.
  --outdir DIR      Output directory (default: dist/coverage).
  -h, --help        Show this help.

Env vars:
  COVERAGE_FULL_SUITE=true   Same as --full
  COVERAGE_FILTER=NAME       Same as --filter NAME
  COVERAGE_REUSE=true        Same as --reuse
  COVERAGE_OUTDIR=DIR        Same as --outdir DIR
USAGE
}

FULL=false
FILTER="${COVERAGE_FILTER:-UnitTestSuite}"
REUSE=${COVERAGE_REUSE:-false}
OUTDIR="${COVERAGE_OUTDIR:-dist/coverage}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL=true; shift ;;
    --filter) FILTER="$2"; shift 2 ;;
    --reuse) REUSE=true; shift ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "${COVERAGE_FULL_SUITE:-false}" == "true" ]]; then FULL=true; fi

mkdir -p "$OUTDIR"

echo "📦 Generating coverage -> $OUTDIR"

# Run tests (unless reusing existing data)
if [[ "$REUSE" != "true" ]]; then
  if [[ "$FULL" == "true" ]]; then
    echo "🧪 Running full test suite with coverage (timeout: 5 minutes)"
    timeout 300 swift test --parallel --enable-code-coverage 2>&1 | tee "$OUTDIR/.coverage-test-output.log" || {
      EXIT_CODE=$?
      if [[ $EXIT_CODE == 124 ]]; then
        echo "⏰ Test run timed out after 5 minutes"
        echo "⚠️  Consider using --filter to run a subset of tests, or investigate slow/hanging tests"
      fi
      exit $EXIT_CODE
    }
  else
    echo "🧪 Running filtered tests with coverage (filter: $FILTER, timeout: 2 minutes)"
    timeout 120 swift test --parallel --enable-code-coverage --filter "$FILTER" 2>&1 | tee "$OUTDIR/.coverage-test-output.log" || {
      EXIT_CODE=$?
      if [[ $EXIT_CODE == 124 ]]; then
        echo "⏰ Test run timed out after 2 minutes"
        echo "⚠️  Filtered tests should complete quickly. This may indicate a test issue."
      fi
      exit $EXIT_CODE
    }
  fi
else
  echo "⏭️  Reusing existing coverage data (no test run)"
fi

# Locate build dir and profdata
BUILDDIR=$(swift build --show-bin-path | sed 's/\/.build\/.*/.build/g')
[[ -d "$BUILDDIR" ]] || BUILDDIR=".build"

PROFDATA="$BUILDDIR/arm64-apple-macosx/debug/codecov/default.profdata"
if [[ ! -f "$PROFDATA" ]]; then
  # Fallback: search anywhere under .build for a profdata
  PROFDATA=$(rg --hidden --glob '**/*.profdata' -n --no-heading "$BUILDDIR" | head -n1 | awk -F: '{print $1}')
fi
if [[ -z "${PROFDATA:-}" || ! -f "$PROFDATA" ]]; then
  echo "❌ No .profdata found under $BUILDDIR" >&2
  exit 3
fi

# Identify primary binaries
TEST_BUNDLE="$BUILDDIR/arm64-apple-macosx/debug/KeyPathPackageTests.xctest/Contents/MacOS/KeyPathPackageTests"
APP_BIN="$BUILDDIR/arm64-apple-macosx/debug/KeyPath"

if command -v xcrun >/dev/null 2>&1; then LLVM_COV="xcrun llvm-cov"; LLVM_PROFDATA="xcrun llvm-profdata"; else LLVM_COV="llvm-cov"; LLVM_PROFDATA="llvm-profdata"; fi

# Merge (noop if single file) so consumers can reuse merged profile
MERGED="$OUTDIR/default.profdata"
$LLVM_PROFDATA merge -sparse "$PROFDATA" -o "$MERGED" >/dev/null 2>&1 || cp "$PROFDATA" "$MERGED"

echo "🧮 Exporting coverage reports"
set +e
$LLVM_COV report "$TEST_BUNDLE" -instr-profile "$MERGED" -use-color > "$OUTDIR/summary.txt"
$LLVM_COV export "$TEST_BUNDLE" -instr-profile "$MERGED" -format lcov > "$OUTDIR/coverage.lcov"
$LLVM_COV export "$TEST_BUNDLE" -instr-profile "$MERGED" -format text > "$OUTDIR/coverage.txt"

# App-only (exclude Tests and .build)
$LLVM_COV report "$TEST_BUNDLE" -instr-profile "$MERGED" \
  -ignore-filename-regex='(^|/)(Tests|\\.build|KeyPathPackageTests\\.derived)/' \
  -use-color > "$OUTDIR/summary_app_only.txt"

# Also report with the app binary if present
if [[ -x "$APP_BIN" ]]; then
  $LLVM_COV report "$APP_BIN" -instr-profile "$MERGED" \
    -ignore-filename-regex='(^|/)(Tests|\\.build)/' \
    -use-color > "$OUTDIR/summary_app_target.txt"
fi
set -e

# HTML via genhtml if available
if command -v genhtml >/dev/null 2>&1; then
  echo "🌐 Generating HTML report"
  genhtml -o "$OUTDIR/html" "$OUTDIR/coverage.lcov" >/dev/null 2>&1 || true
else
  echo "ℹ️  HTML report skipped (genhtml not found)"
fi

printf "\n=== Coverage (app-only totals) ===\n"
if [[ -f "$OUTDIR/summary_app_target.txt" ]]; then
  tail -n 1 "$OUTDIR/summary_app_target.txt" | sed -E 's/\x1b\[[0-9;]*m//g'
else
  tail -n 1 "$OUTDIR/summary_app_only.txt" | sed -E 's/\x1b\[[0-9;]*m//g'
fi

printf "\nArtifacts written to: %s\n" "$OUTDIR"
