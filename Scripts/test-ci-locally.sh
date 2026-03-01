#!/bin/bash
set -euo pipefail

# Local runner to approximate CI steps

echo "🔍 Lint: WizardAutoFixer subprocess guard"
chmod +x ./Scripts/lint-no-subprocess-in-autofixer.sh
./Scripts/lint-no-subprocess-in-autofixer.sh

echo "🔨 Building..."
swift build

echo "🧪 Running smoke tests"
export KP_SIGN_DRY_RUN=1
swift test --filter SigningPipelineTests || true
swift test --filter InstallerEngineEndToEndTests || true

echo "🧭 Running installer reliability matrix"
chmod +x ./Scripts/run-installer-reliability-matrix.sh
./Scripts/run-installer-reliability-matrix.sh

# Safe test runner (matches CI script)
chmod +x ./Scripts/run-tests-safe.sh
./Scripts/run-tests-safe.sh
