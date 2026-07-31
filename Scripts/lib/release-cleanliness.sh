#!/usr/bin/env bash

# Fail-closed source-state checks for release builds.
#
# Release artifacts must be attributable to the commit recorded in
# BuildInfo.plist. A dirty superproject, a submodule checked out at a different
# revision, or an edited lockfile breaks that attribution even when the build
# itself succeeds.

kp_release_require_clean_source() {
    local project_dir=$1
    local repository_status=""
    local lockfile_status=""
    local submodule_status=""
    local dirty_submodules=""
    local failed=0

    if ! git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "❌ Release source is not a Git worktree: $project_dir" >&2
        return 1
    fi

    # `dirty` ignores files inside a submodule while retaining gitlink revision
    # changes. Submodule working trees are inspected recursively below so their
    # file-level diagnostics are not collapsed into a single opaque `M`.
    repository_status=$(
        git -C "$project_dir" status \
            --porcelain=v1 \
            --untracked-files=all \
            --ignore-submodules=dirty
    )
    if [[ -n "$repository_status" ]]; then
        echo "❌ Release repository has tracked, staged, or untracked changes:" >&2
        printf '%s\n' "$repository_status" | sed 's/^/   /' >&2
        failed=1
    fi

    lockfile_status=$(
        git -C "$project_dir" status \
            --porcelain=v1 \
            --untracked-files=all \
            --ignore-submodules=all \
            -- \
            Cargo.lock \
            Package.resolved \
            ':(glob)**/Cargo.lock' \
            ':(glob)**/Package.resolved'
    )
    if [[ -n "$lockfile_status" ]]; then
        echo "❌ Release lockfiles do not match HEAD:" >&2
        printf '%s\n' "$lockfile_status" | sed 's/^/   /' >&2
        failed=1
    fi

    if ! submodule_status=$(git -C "$project_dir" submodule status --recursive 2>&1); then
        echo "❌ Could not inspect release submodules:" >&2
        printf '%s\n' "$submodule_status" | sed 's/^/   /' >&2
        failed=1
    elif printf '%s\n' "$submodule_status" | grep -Eq '^[-+U]'; then
        echo "❌ Release submodules are uninitialized, conflicted, or not at the recorded revisions:" >&2
        printf '%s\n' "$submodule_status" | grep -E '^[-+U]' | sed 's/^/   /' >&2
        failed=1
    fi

    if ! dirty_submodules=$(
        git -C "$project_dir" submodule foreach --quiet --recursive '
            child_status=$(
                git status \
                    --porcelain=v1 \
                    --untracked-files=all \
                    --ignore-submodules=dirty
            )
            if [ -n "$child_status" ]; then
                printf "__KEYPATH_DIRTY_SUBMODULE__ %s\n" "$displaypath"
                printf "%s\n" "$child_status"
            fi
        ' 2>&1
    ); then
        echo "❌ Could not inspect release submodule working trees:" >&2
        printf '%s\n' "$dirty_submodules" | sed 's/^/   /' >&2
        failed=1
    elif [[ -n "$dirty_submodules" ]]; then
        echo "❌ Release submodule working trees are dirty:" >&2
        printf '%s\n' "$dirty_submodules" |
            sed 's/^__KEYPATH_DIRTY_SUBMODULE__ /   submodule: /; /^   submodule:/!s/^/      /' >&2
        failed=1
    fi

    if (( failed > 0 )); then
        echo "   Commit intentional release inputs or use a clean worktree; refusing to build an unattributable artifact." >&2
        return 1
    fi

    return 0
}
