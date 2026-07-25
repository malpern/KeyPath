#!/bin/bash

# Lightweight signing/notarization helpers.
# - Wraps the external tools so tests can swap in stubs.
# - Honors KP_SIGN_DRY_RUN=1 to echo instead of executing.

KP_SIGN_CMD=${KP_SIGN_CMD:-codesign}
KP_NOTARY_CMD=${KP_NOTARY_CMD:-xcrun notarytool}
KP_STAPLER_CMD=${KP_STAPLER_CMD:-xcrun stapler}
KP_SPCTL_CMD=${KP_SPCTL_CMD:-spctl}
KP_VERIFY_CMD=${KP_VERIFY_CMD:-codesign}
KP_SIGN_DRY_RUN=${KP_SIGN_DRY_RUN:-0}
KP_NOTARY_WAIT_TIMEOUT=${KP_NOTARY_WAIT_TIMEOUT:-15m}

kp_run() {
    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        echo "[DRY RUN] $*"
        return 0
    fi
    "$@"
}

kp_sign() {
    local target=$1
    shift
    kp_run "$KP_SIGN_CMD" "$@" "$target"
}

kp_verify_signature() {
    local target=$1
    shift
    kp_run "$KP_VERIFY_CMD" -dvvv "$target" "$@"
}

kp_write_notary_state() {
    local state_file=$1
    local submission_id=$2
    local archive_path=$3
    local archive_sha256=$4
    local profile=$5
    local status=$6

    /usr/bin/python3 - "$state_file" "$submission_id" "$archive_path" "$archive_sha256" "$profile" "$status" <<'PY'
import datetime
import json
import os
import sys

state_file, submission_id, archive_path, archive_sha256, profile, status = sys.argv[1:]
directory = os.path.dirname(state_file)
if directory:
    os.makedirs(directory, exist_ok=True)

payload = {
    "schemaVersion": 1,
    "submissionId": submission_id,
    "archivePath": archive_path,
    "archiveSHA256": archive_sha256,
    "profile": profile,
    "status": status,
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
temporary_file = f"{state_file}.tmp"
with open(temporary_file, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(temporary_file, state_file)
PY
}

kp_write_notary_submit_failure_state() {
    local state_file=$1
    local submission_id=$2
    local archive_path=$3
    local archive_sha256=$4
    local profile=$5
    local submit_exit=$6
    local submit_stdout=$7
    local submit_stderr=$8
    local candidates_json=$9

    /usr/bin/python3 - "$state_file" "$submission_id" "$archive_path" "$archive_sha256" "$profile" "$submit_exit" "$submit_stdout" "$submit_stderr" "$candidates_json" <<'PY'
import datetime
import json
import os
import sys

(
    state_file,
    submission_id,
    archive_path,
    archive_sha256,
    profile,
    submit_exit,
    submit_stdout,
    submit_stderr,
    candidates_json,
) = sys.argv[1:]
directory = os.path.dirname(state_file)
if directory:
    os.makedirs(directory, exist_ok=True)

payload = {
    "schemaVersion": 1,
    "submissionId": submission_id or None,
    "archivePath": archive_path,
    "archiveSHA256": archive_sha256,
    "profile": profile,
    "status": "submit-client-failed",
    "submitExitCode": int(submit_exit),
    "submitStdout": submit_stdout,
    "submitStderr": submit_stderr,
    "candidateSubmissions": [],
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
try:
    candidate_submissions = json.loads(candidates_json)
except (json.JSONDecodeError, TypeError, ValueError):
    candidate_submissions = []
if isinstance(candidate_submissions, list):
    payload["candidateSubmissions"] = candidate_submissions
temporary_file = f"{state_file}.tmp"
with open(temporary_file, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(temporary_file, state_file)
PY
}

kp_notary_json_field() {
    local field=$1
    /usr/bin/python3 -c '
import json
import sys

payload = json.load(sys.stdin)
value = payload.get(sys.argv[1])
if value is None:
    raise SystemExit(1)
print(value)
' "$field"
}

kp_notary_recent_history_candidates() {
    local history_json=$1
    local archive_name=$2
    local started_epoch=$3
    local window_seconds=${KP_NOTARY_HISTORY_WINDOW_SECONDS:-900}

    printf '%s' "$history_json" | /usr/bin/python3 - "$archive_name" "$started_epoch" "$window_seconds" 3<&0 <<'PY'
import datetime
import json
import os
import sys

archive_name, started_epoch, window_seconds = sys.argv[1:]
try:
    payload = json.load(os.fdopen(3))
except (json.JSONDecodeError, TypeError, ValueError):
    print("[]")
    raise SystemExit(0)

if not isinstance(payload, dict):
    print("[]")
    raise SystemExit(0)

minimum_timestamp = float(started_epoch) - float(window_seconds)
candidates = []
for entry in payload.get("history", []):
    if not isinstance(entry, dict):
        continue
    if entry.get("name") != archive_name:
        continue
    created_date = entry.get("createdDate")
    if not isinstance(created_date, str):
        continue
    try:
        timestamp = datetime.datetime.fromisoformat(created_date.replace("Z", "+00:00")).timestamp()
    except (TypeError, ValueError):
        continue
    if timestamp >= minimum_timestamp:
        candidates.append({
            "id": entry.get("id"),
            "createdDate": created_date,
            "status": entry.get("status"),
        })

print(json.dumps(candidates, separators=(",", ":")))
PY
}

kp_print_notary_submit_failure() {
    local submit_exit=$1
    local submit_stdout=$2
    local submit_stderr=$3
    local submission_id=$4
    local candidates_json=$5
    local state_file=$6

    echo "❌ Notarization client exited $submit_exit before returning a parseable submission ID." >&2
    if [ -n "$submit_stdout" ]; then
        echo "   submit stdout: $submit_stdout" >&2
    fi
    if [ -n "$submit_stderr" ]; then
        echo "   submit stderr: $submit_stderr" >&2
    fi
    echo "   Recovery state: $state_file" >&2

    if [ -n "$submission_id" ]; then
        echo "⚠️  Apple submission ID captured before the local client failed: $submission_id" >&2
        echo "   Do not retry automatically. Check this submission ID before submitting again." >&2
        return
    fi

    local candidate_count
    candidate_count=$(printf '%s' "$candidates_json" | /usr/bin/python3 -c 'import json, sys; print(len(json.load(sys.stdin)))')
    if [ "$candidate_count" -gt 0 ]; then
        echo "⚠️  Apple may have received the archive despite the local client failure." >&2
        echo "   Candidate submissions from the last ${KP_NOTARY_HISTORY_WINDOW_SECONDS:-900}s:" >&2
        printf '%s' "$candidates_json" | /usr/bin/python3 -c '
import json
import sys
for candidate in json.load(sys.stdin):
    print("   {}  {}  {}".format(
        candidate.get("id"),
        candidate.get("status"),
        candidate.get("createdDate"),
    ))
' >&2
        echo "   Do not retry automatically. Check these candidate IDs before submitting again." >&2
    fi
}

kp_print_notary_recovery() {
    local submission_id=$1
    local archive_path=$2
    local archive_sha256=$3
    local profile=$4
    local state_file=$5

    echo "⚠️  Notarization did not reach Accepted within ${KP_NOTARY_WAIT_TIMEOUT}."
    echo "   Submission ID: $submission_id"
    echo "   Archive SHA-256: $archive_sha256"
    echo "   Recovery state: $state_file"
    echo ""
    echo "   Check the existing submission before considering a retry:"
    if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
        echo "   xcrun notarytool info \"$submission_id\" --keychain-profile \"$profile\" --keychain \"$KP_NOTARY_KEYCHAIN\""
    else
        echo "   xcrun notarytool info \"$submission_id\" --keychain-profile \"$profile\""
    fi
    echo ""
    echo "   Do not submit another archive automatically. If one explicit retry is"
    echo "   necessary, first verify the archive still has this exact checksum:"
    echo "   shasum -a 256 \"$archive_path\""
    if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
        echo "   xcrun notarytool submit \"$archive_path\" --keychain-profile \"$profile\" --keychain \"$KP_NOTARY_KEYCHAIN\" --no-wait --output-format json --no-progress"
    else
        echo "   xcrun notarytool submit \"$archive_path\" --keychain-profile \"$profile\" --no-wait --output-format json --no-progress"
    fi
}

kp_notarize_zip() {
    local zip_path=$1
    local profile=$2
    shift 2
    local state_file=${KP_NOTARY_STATE_FILE:-"${zip_path%.zip}.notary-submission.json"}

    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
            echo "[DRY RUN] $KP_NOTARY_CMD submit $zip_path --keychain-profile $profile --keychain $KP_NOTARY_KEYCHAIN --no-wait --output-format json --no-progress $*"
            echo "[DRY RUN] $KP_NOTARY_CMD wait <submission-id> --keychain-profile $profile --keychain $KP_NOTARY_KEYCHAIN --timeout $KP_NOTARY_WAIT_TIMEOUT --output-format json --no-progress"
        else
            echo "[DRY RUN] $KP_NOTARY_CMD submit $zip_path --keychain-profile $profile --no-wait --output-format json --no-progress $*"
            echo "[DRY RUN] $KP_NOTARY_CMD wait <submission-id> --keychain-profile $profile --timeout $KP_NOTARY_WAIT_TIMEOUT --output-format json --no-progress"
        fi
        echo "[DRY RUN] persist submission evidence to $state_file"
        return 0
    fi

    local archive_directory
    if ! archive_directory=$(cd "$(dirname "$zip_path")" >/dev/null && pwd -P); then
        echo "❌ Notarization archive directory does not exist or is inaccessible: $(dirname "$zip_path")" >&2
        return 1
    fi
    local archive_path="$archive_directory/$(basename "$zip_path")"
    if [ ! -f "$archive_path" ]; then
        echo "❌ Notarization archive does not exist: $archive_path" >&2
        return 1
    fi
    local archive_sha256
    archive_sha256=$(/usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{print $1}')

    local submit_started_epoch
    submit_started_epoch=$(/bin/date -u +%s)
    local submit_stderr_file
    submit_stderr_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/keypath-notary-submit.XXXXXX")

    local submit_output=""
    local submit_exit=0
    if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
        submit_output=$($KP_NOTARY_CMD submit "$archive_path" --keychain-profile "$profile" --keychain "$KP_NOTARY_KEYCHAIN" --no-wait --output-format json --no-progress "$@" 2>"$submit_stderr_file") || submit_exit=$?
    else
        submit_output=$($KP_NOTARY_CMD submit "$archive_path" --keychain-profile "$profile" --no-wait --output-format json --no-progress "$@" 2>"$submit_stderr_file") || submit_exit=$?
    fi
    local submit_stderr
    submit_stderr=$(<"$submit_stderr_file")
    /bin/rm -f "$submit_stderr_file"

    if [ "$submit_exit" -ne 0 ]; then
        local submission_id
        submission_id=$(printf '%s' "$submit_output" | kp_notary_json_field id 2>/dev/null) || true
        local candidates_json="[]"
        local history_output=""
        if [ -z "$submission_id" ]; then
            if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
                history_output=$($KP_NOTARY_CMD history --keychain-profile "$profile" --keychain "$KP_NOTARY_KEYCHAIN" --output-format json 2>/dev/null) || true
            else
                history_output=$($KP_NOTARY_CMD history --keychain-profile "$profile" --output-format json 2>/dev/null) || true
            fi
            candidates_json=$(kp_notary_recent_history_candidates "$history_output" "$(basename "$archive_path")" "$submit_started_epoch") || candidates_json="[]"
        fi
        kp_write_notary_submit_failure_state "$state_file" "$submission_id" "$archive_path" "$archive_sha256" "$profile" "$submit_exit" "$submit_output" "$submit_stderr" "$candidates_json"
        kp_print_notary_submit_failure "$submit_exit" "$submit_output" "$submit_stderr" "$submission_id" "$candidates_json" "$state_file"
        return "$submit_exit"
    fi

    local submission_id
    submission_id=$(printf '%s' "$submit_output" | kp_notary_json_field id 2>/dev/null) || true
    if [ -z "$submission_id" ]; then
        echo "❌ Notarization upload returned no parseable submission ID." >&2
        echo "$submit_output" >&2
        return 1
    fi

    kp_write_notary_state "$state_file" "$submission_id" "$archive_path" "$archive_sha256" "$profile" "submitted"
    echo "✅ Notarization upload recorded"
    echo "   Submission ID: $submission_id"
    echo "   Archive SHA-256: $archive_sha256"
    echo "   Recovery state: $state_file"
    echo "⏳ Waiting up to $KP_NOTARY_WAIT_TIMEOUT for Apple notarization..."

    local wait_output=""
    local wait_exit=0
    if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
        wait_output=$($KP_NOTARY_CMD wait "$submission_id" --keychain-profile "$profile" --keychain "$KP_NOTARY_KEYCHAIN" --timeout "$KP_NOTARY_WAIT_TIMEOUT" --output-format json --no-progress) || wait_exit=$?
    else
        wait_output=$($KP_NOTARY_CMD wait "$submission_id" --keychain-profile "$profile" --timeout "$KP_NOTARY_WAIT_TIMEOUT" --output-format json --no-progress) || wait_exit=$?
    fi

    local final_status=""
    final_status=$(printf '%s' "$wait_output" | kp_notary_json_field status 2>/dev/null) || true
    if [ "$wait_exit" -ne 0 ] || [ -z "$final_status" ]; then
        local info_output=""
        if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
            info_output=$($KP_NOTARY_CMD info "$submission_id" --keychain-profile "$profile" --keychain "$KP_NOTARY_KEYCHAIN" --output-format json 2>/dev/null) || true
        else
            info_output=$($KP_NOTARY_CMD info "$submission_id" --keychain-profile "$profile" --output-format json 2>/dev/null) || true
        fi
        local info_status=""
        info_status=$(printf '%s' "$info_output" | kp_notary_json_field status 2>/dev/null) || true
        if [ -n "$info_status" ]; then
            final_status=$info_status
        fi
    fi
    if [ "$final_status" = "Accepted" ]; then
        kp_write_notary_state "$state_file" "$submission_id" "$archive_path" "$archive_sha256" "$profile" "accepted"
        echo "✅ Apple notarization accepted submission $submission_id"
        return 0
    fi

    local recorded_status="unknown"
    if [ -n "$final_status" ]; then
        recorded_status=$(printf '%s' "$final_status" | /usr/bin/tr '[:upper:] ' '[:lower:]-')
    elif [ "$wait_exit" -ne 0 ]; then
        recorded_status="wait-failed"
    fi
    kp_write_notary_state "$state_file" "$submission_id" "$archive_path" "$archive_sha256" "$profile" "$recorded_status"
    kp_print_notary_recovery "$submission_id" "$archive_path" "$archive_sha256" "$profile" "$state_file"

    if [ "$final_status" = "In Progress" ]; then
        return 75
    fi
    if [ "$wait_exit" -ne 0 ]; then
        return "$wait_exit"
    fi
    return 1
}

kp_staple() {
    local target=$1
    shift
    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        echo "[DRY RUN] $KP_STAPLER_CMD staple $target $*"
        return 0
    fi
    # Use word-splitting for multi-word command (xcrun stapler)
    $KP_STAPLER_CMD staple "$target" "$@"
}

kp_spctl_assess() {
    local target=$1
    shift
    kp_run "$KP_SPCTL_CMD" -a -vvv "$target" "$@"
}
