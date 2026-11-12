#!/bin/bash
# Shared settings for the localization scripts (project review P8).
L10N_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The one catalog. SwiftPM builds it into KeyPath_KeyPathAppKit.bundle for
# `bundle:` lookups; compile-strings.sh also builds it into the app's main
# bundle, which is where plain Text("…") and Button("…") look in every module.
L10N_CATALOG="$L10N_ROOT/Sources/KeyPathAppKit/Resources/Localizable.xcstrings"
# Modules whose user-visible strings belong in the catalog. The CLI prints
# English by design and is not listed.
L10N_MODULES="KeyPathAppKit KeyPathCore KeyPathInstallationWizard KeyPathInsights KeyPathLayoutTracerKit KeyPathWizardCore KeyPathPermissions KeyPathRulesCore"

# Prints the .stringsdata files the compiler wrote for L10N_MODULES under a
# SwiftPM build folder (default .build). Every Debug build writes them.
l10n_stringsdata_files() {
    local build_dir="${1:-$L10N_ROOT/.build}"
    local intermediates="$build_dir/out/Intermediates.noindex/KeyPath.build/Debug"
    local module
    for module in $L10N_MODULES; do
        # A listed module with no output means the build did not cover it;
        # skipping it would let a check pass without reading its strings.
        if [ -z "$(find "$intermediates/$module-t.build" -name "*.stringsdata" -print -quit 2>/dev/null)" ]; then
            echo "❌ No .stringsdata for $module under $intermediates" >&2
            return 1
        fi
        find "$intermediates/$module-t.build" -name "*.stringsdata"
    done
}
