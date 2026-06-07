#!/bin/bash
set -euo pipefail

# Local runner to approximate CI steps

echo "🔍 Lint: WizardAutoFixer subprocess guard"
chmod +x ./Scripts/lint-no-subprocess-in-autofixer.sh
./Scripts/lint-no-subprocess-in-autofixer.sh

echo "🔍 Lint: Wizard sleep guard"
chmod +x ./Scripts/lint-no-sleep.sh
./Scripts/lint-no-sleep.sh

echo "♿ Accessibility check"
python3 Scripts/check-accessibility.py

echo "🔨 Building..."
swift build

echo "🧪 Running safe test suite"
export KP_SIGN_DRY_RUN=1
export CI_ENVIRONMENT=true
export SKIP_EVENT_TAP_TESTS=1
export TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
chmod +x ./Scripts/run-tests-safe.sh
./Scripts/run-tests-safe.sh

echo "🧭 Parsing installer reliability matrix from safe test log"
chmod +x ./Scripts/parse-installer-matrix.sh
./Scripts/parse-installer-matrix.sh test_output.safe.txt
