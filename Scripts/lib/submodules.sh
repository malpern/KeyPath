#!/bin/bash

# Helpers for build paths that require checked-out git submodules.

keypath_ensure_kanata_submodule() {
    local project_root="${1:?project root required}"
    local kanata_source="$project_root/External/kanata"
    local kanata_manifest="$kanata_source/Cargo.toml"

    if [ "${KEYPATH_KANATA_SUBMODULE_READY:-0}" = "1" ] && [ -f "$kanata_manifest" ]; then
        return 0
    fi

    if [ -f "$kanata_manifest" ]; then
        export KEYPATH_KANATA_SUBMODULE_READY=1
        return 0
    fi

    if [ ! -f "$project_root/.gitmodules" ]; then
        echo "❌ Error: Kanata source is missing at $kanata_source" >&2
        echo "   Expected $kanata_manifest, but this checkout has no .gitmodules file." >&2
        return 1
    fi

    echo "📦 Initializing Kanata submodule..."
    if git -C "$project_root" submodule update --init --recursive External/kanata; then
        if [ -f "$kanata_manifest" ]; then
            export KEYPATH_KANATA_SUBMODULE_READY=1
            return 0
        fi

        echo "❌ Error: Kanata submodule initialized, but $kanata_manifest is still missing." >&2
        return 1
    fi

    echo "❌ Error: Failed to initialize Kanata submodule." >&2
    echo "   Run: git submodule update --init --recursive External/kanata" >&2
    return 1
}
