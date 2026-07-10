#!/usr/bin/env bash

# Prepare a worktree-local SwiftPM cache for canonical path reuse.
#
# Older quick-deploy versions derived PROJECT_DIR as `Scripts/..`. Swift embeds
# the Clang module-cache path in compiled modules, so artifacts produced by that
# spelling cannot be safely reused with the canonical path even though both
# resolve to the same directory. Clean build products once, keep dependency
# checkouts, and mark the migration complete.
keypath_prepare_build_cache() {
    local project_dir="$1"
    local scratch_path="$2"
    local canonical_scratch="$project_dir/.build"
    local migration_marker="$scratch_path/.keypath-canonical-module-cache-v1"

    mkdir -p "$scratch_path"

    if [[ "$scratch_path" == "$canonical_scratch" && ! -f "$migration_marker" ]]; then
        if [[ -f "$scratch_path/build.db" || -d "$scratch_path/arm64-apple-macosx" || -d "$scratch_path/out" ]]; then
            echo "🧹 Migrating legacy SwiftPM artifacts to canonical cache paths (one time)"
            (cd "$project_dir" && swift package clean)
        fi
        rm -rf "$scratch_path/ModuleCache.noindex"
        mkdir -p "$scratch_path"
        touch "$migration_marker"
    fi

    # SwiftPM's stable and beta build systems use different generated `debug`
    # symlink targets. Remove only generated metadata and let this invocation
    # recreate the target appropriate for its toolchain.
    if [[ -L "$scratch_path/debug" ]]; then
        echo "🧹 Refreshing generated $scratch_path/debug symlink"
        rm "$scratch_path/debug"
    fi
}
