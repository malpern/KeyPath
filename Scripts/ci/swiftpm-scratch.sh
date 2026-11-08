#!/bin/bash
# Keep SwiftPM's downloaded package state across CI jobs on the mini.
#
# A cold SwiftPM fetch of Sparkle's binary artifact traps (SIGTRAP, exit 133)
# under the headless runner daemons on macOS 27.3: AppSSO misuses XPC inside
# NSURLSession. See docs/bugs/2026-07-16-headless-swiftpm-appsso-trap.md.
# A scratch whose workspace-state.json already records the artifact makes no
# request, so this script never throws that state away:
#
#   prepare SCRATCH   Reuse SCRATCH. On a toolchain change or when it grows past
#                     KEYPATH_SCRATCH_CAP_GIB, delete only build products and keep
#                     the fetched state. Writes SCRATCH_PATH and
#                     SWIFTPM_SCRATCH_STATE to $GITHUB_ENV when set.
#   seed FROM TO      Copy FROM's fetched state into TO, which has none, and
#                     rewrite its absolute paths. Used for builds that cannot
#                     share FROM, such as coverage in the checkout's .build.

set -euo pipefail

# Everything SwiftPM fetched. Build products are everything else.
FETCHED=(workspace-state.json artifacts checkouts repositories prebuilts)

keep_only_fetched() {
    local scratch=$1 entry keep name
    for entry in "$scratch"/* "$scratch"/.[!.]*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        name=${entry##*/}
        keep=0
        for fetched in "${FETCHED[@]}"; do [[ "$name" == "$fetched" ]] && keep=1; done
        (( keep )) || rm -rf "$entry"
    done
}

prepare() {
    local scratch=$1 stamp toolchain state=warm size_gib
    stamp="$scratch/.keypath-toolchain"
    toolchain="$(swift --version 2>&1 | head -1)"
    if [[ ! -d "$scratch" ]]; then
        state=cold
    elif [[ "$(cat "$stamp" 2>/dev/null)" != "$toolchain" ]]; then
        echo "Toolchain changed; clearing build products in $scratch, keeping fetched packages"
        keep_only_fetched "$scratch"; state=toolchain-changed
    else
        size_gib=$(( $(du -sk "$scratch" | cut -f1) / 1048576 ))
        if (( size_gib > ${KEYPATH_SCRATCH_CAP_GIB:-30} )); then
            echo "Scratch is ${size_gib} GiB (cap ${KEYPATH_SCRATCH_CAP_GIB:-30}); clearing build products"
            keep_only_fetched "$scratch"; state=over-cap
        fi
    fi
    [[ "$state" == warm || -f "$scratch/workspace-state.json" ]] || state="$state-unfetched"
    mkdir -p "$scratch"
    printf '%s\n' "$toolchain" > "$stamp"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "SCRATCH_PATH=$scratch" >> "$GITHUB_ENV"
        echo "SWIFTPM_SCRATCH_STATE=$state" >> "$GITHUB_ENV"
    fi
    echo "SwiftPM scratch: $scratch ($state)"
}

seed() {
    local from=$1 to=$2 fetched
    if [[ -f "$to/workspace-state.json" ]]; then
        echo "SwiftPM seed: $to already has fetched packages"; return 0
    fi
    if [[ ! -f "$from/workspace-state.json" ]]; then
        echo "SwiftPM seed: $from has no fetched packages; this build will fetch them"; return 0
    fi
    mkdir -p "$to"
    for fetched in "${FETCHED[@]}"; do
        [[ -e "$from/$fetched" ]] && cp -Rc "$from/$fetched" "$to/$fetched"
    done
    FROM="$from" TO="$to" /usr/bin/python3 -I -c '
import os
path = os.path.join(os.environ["TO"], "workspace-state.json")
text = open(path).read()
open(path, "w").write(text.replace(os.environ["FROM"], os.environ["TO"]))
'
    echo "SwiftPM seed: copied fetched packages from $from to $to"
}

case "${1:-}" in
    prepare) [[ $# -eq 2 ]] || { echo "usage: $0 prepare SCRATCH" >&2; exit 2; }; prepare "$2" ;;
    seed) [[ $# -eq 3 ]] || { echo "usage: $0 seed FROM TO" >&2; exit 2; }; seed "$2" "$3" ;;
    *) echo "usage: $0 prepare SCRATCH | seed FROM TO" >&2; exit 2 ;;
esac
