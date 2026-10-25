#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/review-gate.sh [--require-local]

Run the pre-PR review gate for the current branch.

Exit codes:
  0  Local review gate ran and passed.
  2  Remote review gate required; PR must wait for GitHub claude-review.
  1  Local review gate ran and failed (a CONFIRMED finding, a review that did
     not complete, or one without a verdict), or repository state is invalid.

Options:
  --require-local  Treat unavailable local review tooling as a failure.

Remote review note:
  Exit 2 is the expected path when local review tooling is not configured
  (common in Codex shells). Record it as "remote review gate selected" in the
  PR. This is not a failure; the merge gate is the GitHub claude-review check.
EOF
}

require_local=0
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
elif [[ "${1:-}" == "--require-local" ]]; then
    require_local=1
elif [[ $# -gt 0 ]]; then
    usage >&2
    exit 1
fi

script_dir=$(cd "$(dirname "$0")" >/dev/null && pwd)
repo_root=$(cd "$script_dir/.." >/dev/null && pwd)
cd "$repo_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "review-gate: not inside a git worktree" >&2
    exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" == "master" ]]; then
    echo "review-gate: refusing to review master directly; use a feature worktree" >&2
    exit 1
fi

if ! git rev-parse --verify origin/master >/dev/null 2>&1; then
    echo "review-gate: origin/master is unavailable; run git fetch first" >&2
    exit 1
fi

# Review everything the branch would ship: commits since the merge base, plus
# uncommitted tracked changes, plus untracked files. A diff of commits only
# reviews nothing for a branch whose work is still in the working tree.
base=$(git merge-base origin/master HEAD)
# BSD mktemp replaces only trailing X's, so the template must end in them;
# "….XXXXXX.patch" made one fixed filename and a second run collided.
diff_file=$(mktemp "${TMPDIR:-/tmp}/keypath-review-diff.XXXXXX")
output_file=""
trap 'rm -f "$diff_file" ${output_file:+"$output_file"}' EXIT
git diff --find-renames "$base" > "$diff_file"
while IFS= read -r -d '' untracked; do
    git diff --no-index -- /dev/null "$untracked" >> "$diff_file" || true
done < <(git ls-files -z --others --exclude-standard)

if [[ ! -s "$diff_file" ]]; then
    echo "review-gate: no branch or working-tree diff to review"
    exit 0
fi

if command -v thermo-nuclear-swift-review >/dev/null 2>&1; then
    echo "review-gate: running thermo-nuclear-swift-review"
    thermo-nuclear-swift-review
    exit $?
fi

if command -v claude >/dev/null 2>&1; then
    echo "review-gate: running claude review of $(wc -l < "$diff_file" | tr -d ' ') diff lines against $base"
    output_file=$(mktemp "${TMPDIR:-/tmp}/keypath-review-output.XXXXXX")
    prompt='/thermo-nuclear-swift-review

Review the KeyPath branch diff given on standard input.

Focus on bugs, behavioral regressions, concurrency/lifecycle hazards, installer
postcondition violations, missing tests, and false-success paths. Classify each
finding as CONFIRMED, PLAUSIBLE, or SPECULATIVE.

End your reply with exactly one final line:
REVIEW-VERDICT: FAIL   if any finding is CONFIRMED
REVIEW-VERDICT: PASS   otherwise'
    set +e
    claude -p "$prompt" < "$diff_file" | tee "$output_file"
    status=${PIPESTATUS[0]}
    set -e
    if [[ "$status" -ne 0 ]]; then
        echo "review-gate: claude exited $status; the review did not complete" >&2
        exit 1
    fi
    # The exit code says the CLI ran, not what the review found: gate on the verdict.
    # `|| true`: under pipefail a grep that finds no verdict would otherwise end
    # the script with status 1 and no message — a silent failure.
    verdict=$(grep -E '^REVIEW-VERDICT: (PASS|FAIL)[[:space:]]*$' "$output_file" | tail -1 | awk '{print $2}' || true)
    case "$verdict" in
        PASS) echo "review-gate: review passed"; exit 0 ;;
        FAIL) echo "review-gate: review found CONFIRMED issues" >&2; exit 1 ;;
        *) echo "review-gate: the review gave no REVIEW-VERDICT line; cannot tell whether it passed" >&2; exit 1 ;;
    esac
fi

message="review-gate: remote review gate selected; GitHub claude-review must pass before merge"
if [[ "$require_local" -eq 1 ]]; then
    echo "review-gate: local review tooling required but unavailable" >&2
    exit 1
fi

echo "$message"
exit 2
