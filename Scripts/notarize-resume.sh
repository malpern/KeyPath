#!/usr/bin/env bash

# Resume a release-candidate whose notarization failed after dist/ was built.
#
# Reads the recovery state written by kp_notarize_zip, finishes or re-runs the
# Apple submission for the exact dist archive, staples dist/KeyPath.app, and
# deploys that stapled bundle to /Applications unchanged (no rebuild, no
# re-sign). Use via Scripts/release-candidate.sh --resume-notarization.
#
# Environment:
#   KP_NOTARY_STATE_FILE      Recovery state override (default:
#                             dist/KeyPath.notary-submission.json).
#   KP_NOTARY_SUBMISSION_ID   Wait on this submission id instead of the
#                             recorded one (use when the state file lists
#                             candidateSubmissions).
#   SKIP_DEPLOY=1             Staple and verify dist/ without touching
#                             /Applications.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
cd "$PROJECT_DIR"

source "$SCRIPT_DIR/lib/xcode.sh"
source "$SCRIPT_DIR/lib/signing.sh"
source "$SCRIPT_DIR/lib/deploy-lock.sh"
source "$SCRIPT_DIR/lib/deploy-app.sh"
keypath_use_stable_xcode
keypath_acquire_deploy_lock "notarize-resume ($PROJECT_DIR)" "${KEYPATH_RELEASE_DEPLOY_LOCK_TIMEOUT_SECONDS:-600}"
trap keypath_release_deploy_lock EXIT

APP_NAME="KeyPath"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"
STATE_FILE=${KP_NOTARY_STATE_FILE:-"${ZIP_PATH%.zip}.notary-submission.json"}

for required in "$APP_BUNDLE" "$ZIP_PATH" "$STATE_FILE"; do
    if [ ! -e "$required" ]; then
        echo "❌ Missing $required — nothing to resume. Run Scripts/release-candidate.sh instead." >&2
        exit 1
    fi
done

recorded_sha=$(kp_notary_json_field archiveSHA256 < "$STATE_FILE" 2>/dev/null) || recorded_sha=""
recorded_status=$(kp_notary_json_field status < "$STATE_FILE" 2>/dev/null) || recorded_status=""
recorded_submission_id=$(kp_notary_json_field submissionId < "$STATE_FILE" 2>/dev/null) || recorded_submission_id=""
recorded_profile=$(kp_notary_json_field profile < "$STATE_FILE" 2>/dev/null) || recorded_profile=""

# Fall back to the profile the failed release actually used, so a resume
# without the original NOTARY_PROFILE override still authenticates.
NOTARY_PROFILE="${NOTARY_PROFILE:-${recorded_profile:-KeyPath-Profile}}"

current_sha=$(/usr/bin/shasum -a 256 "$ZIP_PATH" | /usr/bin/awk '{print $1}')
if [ -z "$recorded_sha" ] || [ "$current_sha" != "$recorded_sha" ]; then
    echo "❌ $ZIP_PATH no longer matches the recovery state (recorded ${recorded_sha:-<none>}, found $current_sha)." >&2
    echo "   dist/ was rebuilt or modified; run the full Scripts/release-candidate.sh instead." >&2
    exit 1
fi

kp_notary_default_auth_from_environment

submission_id="${KP_NOTARY_SUBMISSION_ID:-$recorded_submission_id}"

if [ "$recorded_status" = "accepted" ]; then
    echo "✅ Recovery state already shows an accepted submission; continuing to staple."
elif [ -n "$submission_id" ]; then
    echo "🔁 Resuming submission $submission_id (recorded status: ${recorded_status:-unknown})..."
    kp_notary_await_submission "$submission_id" "$NOTARY_PROFILE" "$STATE_FILE" "$ZIP_PATH" "$current_sha"
else
    candidate_count=$(/usr/bin/python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("candidateSubmissions") or []))' < "$STATE_FILE" 2>/dev/null) || candidate_count=0
    if [ "$candidate_count" -gt 0 ]; then
        echo "❌ The failed submit may have reached Apple; refusing to resubmit automatically." >&2
        echo "   Candidate submissions in $STATE_FILE:" >&2
        /usr/bin/python3 -c '
import json, sys
for candidate in json.load(sys.stdin).get("candidateSubmissions") or []:
    print("   {}  {}  {}".format(candidate.get("id"), candidate.get("status"), candidate.get("createdDate")))
' < "$STATE_FILE" >&2
        echo "   Re-run with KP_NOTARY_SUBMISSION_ID=<id> to wait on one of them." >&2
        exit 1
    fi
    # An empty recorded candidate list is not proof nothing reached Apple: the
    # original history lookup may itself have failed or lagged the upload.
    # Require a successful, authoritative history check now before resubmitting.
    echo "🔎 Checking Apple submission history before resubmitting..."
    kp_notary_resolve_auth "$NOTARY_PROFILE"
    history_output=""
    if ! history_output=$($KP_NOTARY_CMD history "${KP_NOTARY_AUTH_ARGS[@]}" --output-format json 2>/dev/null); then
        echo "❌ notarytool history is unavailable; refusing to resubmit without positive evidence" >&2
        echo "   that the failed upload never reached Apple (a blind retry can create duplicates)." >&2
        echo "   Fix credentials/connectivity and re-run, or wait on a known submission with" >&2
        echo "   KP_NOTARY_SUBMISSION_ID=<id>." >&2
        exit 1
    fi
    failure_epoch=$(/usr/bin/python3 - "$STATE_FILE" <<'PY'
import datetime
import json
import sys

try:
    updated_at = json.load(open(sys.argv[1])).get("updatedAt")
    print(int(datetime.datetime.fromisoformat(updated_at.replace("Z", "+00:00")).timestamp()))
except Exception:
    print(0)  # unparseable -> widest window, which can only add caution
PY
)
    fresh_candidates=$(kp_notary_recent_history_candidates "$history_output" "$(basename "$ZIP_PATH")" "$failure_epoch") || fresh_candidates="[]"
    fresh_count=$(printf '%s' "$fresh_candidates" | /usr/bin/python3 -c 'import json, sys; print(len(json.load(sys.stdin)))') || fresh_count=0
    if [ "$fresh_count" -gt 0 ]; then
        echo "❌ Apple history shows submissions of $(basename "$ZIP_PATH") around the failed run; refusing to resubmit." >&2
        printf '%s' "$fresh_candidates" | /usr/bin/python3 -c '
import json, sys
for candidate in json.load(sys.stdin):
    print("   {}  {}  {}".format(candidate.get("id"), candidate.get("status"), candidate.get("createdDate")))
' >&2
        echo "   Re-run with KP_NOTARY_SUBMISSION_ID=<id> to wait on one of them." >&2
        exit 1
    fi
    echo "🔁 No submission reached Apple; resubmitting the recorded archive..."
    kp_notarize_zip "$ZIP_PATH" "$NOTARY_PROFILE"
fi

echo "🔖 Stapling notarization..."
kp_staple "$APP_BUNDLE"
kp_staple_validate "$APP_BUNDLE"

echo "🔍 Final verification..."
kp_spctl_assess "$APP_BUNDLE"

if [ "${SKIP_DEPLOY:-0}" = "1" ]; then
    echo "⏭️  Skipping deployment (SKIP_DEPLOY=1)"
    echo "📍 Stapled candidate retained at: $APP_BUNDLE"
    exit 0
fi

kp_deploy_bundle_to_applications "$APP_BUNDLE" "$APP_NAME"

echo "🎉 Notarization resume complete."
echo "📍 Deployed app: /Applications/${APP_NAME}.app"
