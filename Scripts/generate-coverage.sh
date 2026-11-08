#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${1:-coverage}"
mkdir -p "$OUT_DIR"

# The older build system produced one KeyPathPackageTests.xctest under
# .build/debug; the current one writes one bundle per test target under
# .build/out/Products/Debug. Report across every test binary found.
TEST_BINARIES=()
while IFS= read -r binary; do TEST_BINARIES+=("$binary"); done < <(
  find .build -ipath '*debug/*.xctest/Contents/MacOS/*' -type f -perm -u+x | sort
)
PROFDATA="$(find .build -ipath '*debug/codecov/default.profdata' | head -n1)"

if [[ ${#TEST_BINARIES[@]} -eq 0 ]]; then
  echo "ERROR: Coverage test binaries not found. Run: swift test --enable-code-coverage"
  exit 1
fi

if [[ -z "${PROFDATA:-}" || ! -f "$PROFDATA" ]]; then
  echo "ERROR: default.profdata not found. Run: swift test --enable-code-coverage"
  exit 1
fi

echo "Using test binaries: ${TEST_BINARIES[*]}"
echo "Using profile data: $PROFDATA"

OBJECT_ARGS=("${TEST_BINARIES[0]}")
for binary in "${TEST_BINARIES[@]:1}"; do OBJECT_ARGS+=(-object "$binary"); done
xcrun llvm-cov report \
  -instr-profile "$PROFDATA" \
  "${OBJECT_ARGS[@]}" | tee "$OUT_DIR/coverage-report.txt"

# Skip llvm-cov export — it generates a multi-MB JSON file that hangs on CI
# runners and is not used by the coverage floor check. Re-enable locally if
# you need per-file coverage data:
#   xcrun llvm-cov export -format=text -instr-profile "$PROFDATA" "${OBJECT_ARGS[@]}" > "$OUT_DIR/coverage.json"

TOTAL_LINE="$(grep '^TOTAL' "$OUT_DIR/coverage-report.txt" || true)"
if [[ -n "$TOTAL_LINE" ]]; then
  echo "$TOTAL_LINE" > "$OUT_DIR/coverage-summary.txt"
  echo "Coverage summary: $TOTAL_LINE"
else
  echo "WARN: TOTAL coverage line not found" | tee "$OUT_DIR/coverage-summary.txt"
fi

# Core business-logic files we care about most (privileged install, config
# generation/parsing, service health, permissions). The full llvm-cov report
# already lists every file; extract just these so the per-file signal isn't
# lost in the noise. Empty when running the narrow lane (those files aren't
# instrumented), which is expected.
CORE_FILES_PATTERN='InstallerEngine|ConfigurationService|ServiceHealthChecker|PermissionOracle|KanataConfigurationGenerator|KanataDefcfg|VHIDDeviceManager|ServiceBootstrapper'
grep -E "$CORE_FILES_PATTERN" "$OUT_DIR/coverage-report.txt" > "$OUT_DIR/coverage-core.txt" || true
if [[ -s "$OUT_DIR/coverage-core.txt" ]]; then
  echo "Core-file coverage:"
  cat "$OUT_DIR/coverage-core.txt"
fi

echo "Coverage artifacts written to: $OUT_DIR"
