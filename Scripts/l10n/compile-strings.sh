#!/bin/bash
# Compiles the string catalog into <lang>.lproj/Localizable.strings(dict) in an
# app's Contents/Resources, so SwiftUI literals in every module translate.
# Usage: Scripts/l10n/compile-strings.sh <Contents/Resources dir>
set -euo pipefail
source "$(dirname "$0")/strings-common.sh"
resources="${1:?usage: compile-strings.sh <Contents/Resources dir>}"
mkdir -p "$resources"
xcrun xcstringstool compile "$L10N_CATALOG" --output-directory "$resources"
echo "✅ Compiled string catalog into $(ls -d "$resources"/*.lproj | xargs -n1 basename | tr '\n' ' ')"
