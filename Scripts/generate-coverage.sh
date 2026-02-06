#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${1:-coverage}"
mkdir -p "$OUT_DIR"

TEST_BINARY="$(find .build -path '*debug/KeyPathPackageTests.xctest/Contents/MacOS/KeyPathPackageTests' | head -n1)"
PROFDATA="$(find .build -path '*debug/codecov/default.profdata' | head -n1)"

if [[ -z "${TEST_BINARY:-}" || ! -f "$TEST_BINARY" ]]; then
  echo "ERROR: Coverage test binary not found. Run: swift test --enable-code-coverage"
  exit 1
fi

if [[ -z "${PROFDATA:-}" || ! -f "$PROFDATA" ]]; then
  echo "ERROR: default.profdata not found. Run: swift test --enable-code-coverage"
  exit 1
fi

echo "Using test binary: $TEST_BINARY"
echo "Using profile data: $PROFDATA"

xcrun llvm-cov report \
  -instr-profile "$PROFDATA" \
  "$TEST_BINARY" | tee "$OUT_DIR/coverage-report.txt"

xcrun llvm-cov export \
  -format=text \
  -instr-profile "$PROFDATA" \
  "$TEST_BINARY" > "$OUT_DIR/coverage.json"

TOTAL_LINE="$(grep '^TOTAL' "$OUT_DIR/coverage-report.txt" || true)"
if [[ -n "$TOTAL_LINE" ]]; then
  echo "$TOTAL_LINE" > "$OUT_DIR/coverage-summary.txt"
  echo "Coverage summary: $TOTAL_LINE"
else
  echo "WARN: TOTAL coverage line not found" | tee "$OUT_DIR/coverage-summary.txt"
fi

echo "Coverage artifacts written to: $OUT_DIR"
