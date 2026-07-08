#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/review-gate.sh [--require-local]

Run the pre-PR review gate for the current branch.

Exit codes:
  0  Local review gate ran and passed.
  2  Local review tooling is unavailable; PR must rely on GitHub claude-review.
  1  Local review gate ran and failed, or repository state is invalid.

Options:
  --require-local  Treat unavailable local review tooling as a failure.

Codex note:
  The Codex shell does not currently provide /thermo-nuclear-swift-review or
  claude. In that environment this script should be run before PR creation and
  its exit code 2 recorded as "remote review required"; the PR must not merge
  until the GitHub claude-review check passes.
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

changed_summary=$(git diff --stat origin/master...HEAD)
if [[ -z "$changed_summary" ]] && [[ -z "$(git diff --stat)" ]]; then
    echo "review-gate: no branch or working-tree diff to review"
    exit 0
fi

if command -v thermo-nuclear-swift-review >/dev/null 2>&1; then
    echo "review-gate: running thermo-nuclear-swift-review"
    thermo-nuclear-swift-review
    exit $?
fi

if command -v claude >/dev/null 2>&1; then
    echo "review-gate: running claude review prompt against origin/master...HEAD"
    diff_file=$(mktemp "${TMPDIR:-/tmp}/keypath-review-diff.XXXXXX.patch")
    trap 'rm -f "$diff_file"' EXIT
    git diff --find-renames origin/master...HEAD > "$diff_file"
    claude <<EOF
/thermo-nuclear-swift-review

Review the KeyPath branch diff in this file:
$diff_file

Focus on bugs, behavioral regressions, concurrency/lifecycle hazards, installer
postcondition violations, missing tests, and false-success paths. Classify each
finding as CONFIRMED, PLAUSIBLE, or SPECULATIVE.
EOF
    exit $?
fi

message="review-gate: local review tooling unavailable; require GitHub claude-review before merge"
if [[ "$require_local" -eq 1 ]]; then
    echo "$message" >&2
    exit 1
fi

echo "$message"
exit 2
