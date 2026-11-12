#!/bin/bash
# Refreshes the string catalog from the strings the compiler found in source.
# Run after a Debug `swift build` (it reads the build's .stringsdata files).
#
#   Scripts/l10n/sync-strings.sh                 add new keys, mark removed ones stale
#   Scripts/l10n/sync-strings.sh --check         fail if the code has keys the catalog lacks
#   Scripts/l10n/sync-strings.sh --build-dir D   read a build folder other than .build
set -euo pipefail
source "$(dirname "$0")/strings-common.sh"

check=0
build_dir="$L10N_ROOT/.build"
while [ $# -gt 0 ]; do
    case "$1" in
        --check) check=1 ;;
        --build-dir) build_dir="$2"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

list="$(l10n_stringsdata_files "$build_dir")" || {
    echo "❌ Run a Debug swift build first (or pass --build-dir)." >&2
    exit 1
}
files=()
while IFS= read -r file; do files+=(--stringsdata "$file"); done <<<"$list"

if [ "$check" -eq 0 ]; then
    out="$(xcrun xcstringstool sync "$L10N_CATALOG" "${files[@]}" 2>&1)" || {
        echo "$out" >&2
        echo "❌ xcstringstool sync failed" >&2
        exit 1
    }
    grep -v "^notice:" <<<"$out" || true
    echo "✅ Synced $L10N_CATALOG from $((${#files[@]} / 2)) files"
    exit 0
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp "$L10N_CATALOG" "$scratch/Localizable.xcstrings"
if ! out="$(xcrun xcstringstool sync "$scratch/Localizable.xcstrings" "${files[@]}" 2>&1)"; then
    echo "$out" >&2
    echo "❌ xcstringstool sync failed" >&2
    exit 1
fi
missing="$(python3 - "$L10N_CATALOG" "$scratch/Localizable.xcstrings" <<'PY'
import json, sys
before = set(json.load(open(sys.argv[1]))["strings"])
after = json.load(open(sys.argv[2]))["strings"]
new = sorted(k for k, v in after.items() if k not in before and v.get("extractionState") != "stale")
print("\n".join(new))
PY
)"
if [ -n "$missing" ]; then
    echo "❌ The code has strings the catalog does not. Run Scripts/l10n/sync-strings.sh and commit the catalog:" >&2
    echo "$missing" | head -40 | sed 's/^/   /' >&2
    exit 1
fi
echo "✅ String catalog is in sync with the code"
