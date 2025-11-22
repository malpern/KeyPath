#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.keypath.KeyPath"
LOG_FILE="$HOME/Library/Logs/KeyPath/keypath-debug.log"

echo "=== KeyPath Permission UX Validation ==="
echo "Time: $(date)"
echo

echo "1) Feature flags (UserDefaults):"
defaults read "$APP_ID" USE_AUTOMATIC_PERMISSION_PROMPTS 2>/dev/null || echo "USE_AUTOMATIC_PERMISSION_PROMPTS: (not set)"
defaults read "$APP_ID" USE_JIT_PERMISSION_REQUESTS 2>/dev/null || echo "USE_JIT_PERMISSION_REQUESTS: (not set)"
defaults read "$APP_ID" ALLOW_OPTIONAL_WIZARD 2>/dev/null || echo "ALLOW_OPTIONAL_WIZARD: (not set)"
echo

echo "2) App log file existence:"
if [[ -f "$LOG_FILE" ]]; then
  ls -lh "$LOG_FILE"
else
  echo "Log file not found: $LOG_FILE"
fi
echo

echo "3) Recent app logs (permission/jit/banner):"
if [[ -f "$LOG_FILE" ]]; then
  grep -Ei "(Permission|Wizard|Oracle|Setup|Input Monitoring|Accessibility|PermissionRequest|PermissionGate|SetupBanner|KeyboardCapture)" "$LOG_FILE" | tail -n 200 || true
else
  echo "No log file yet. Interact with the app to generate logs."
fi
echo

echo "4) Next manual steps (perform in app):"
cat <<'STEPS'
- Open Settings > verify the setup banner if permissions are missing; click "Complete Setup" to open the wizard
- In the wizard:
  * Input Monitoring page: click "Grant Permission" (auto-prompt should appear if foreground)
  * Accessibility page: click "Grant Permission" (auto-prompt should appear if foreground)
- In the main window:
  * Try recording a key without Accessibility → JIT pre-dialog should appear, then OS prompt
  * Make a mapping change and Save → if IM missing, JIT gate should prompt, then reload proceeds
STEPS
echo

echo "5) To live-tail logs while testing:"
echo "   tail -f \"$LOG_FILE\" | egrep -Ei '(Permission|Wizard|Oracle|Setup|Input Monitoring|Accessibility|PermissionRequest|PermissionGate|SetupBanner|KeyboardCapture)'"
echo

echo "=== Validation script completed ==="


