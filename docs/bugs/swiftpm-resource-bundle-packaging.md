# SwiftPM resource bundles in the packaged macOS app

## Symptom

Opening first-success onboarding crashed in SwiftPM's generated
`Bundle.module` accessor. The crash occurred only after the feature worktree had
been removed.

## Root cause

SwiftPM generates an accessor that searches for target resource bundles at
`Bundle.main.bundleURL/<target>.bundle`. For KeyPath's macOS app, that is the
root of `KeyPath.app`.

KeyPath's deploy and release scripts copied the physical bundles only into
`KeyPath.app/Contents/Resources`. Development builds appeared to work because
the generated accessor also embeds an absolute fallback path into the current
worktree's `.build` directory. Removing that worktree exposed the invalid
packaged layout.

An app-root compatibility link was considered, but `codesign` rejects extra
contents at the macOS bundle root as unsealed. The runtime fix therefore cannot
change the signed app layout to satisfy SwiftPM's generated accessor.

## Invariant

Physical SwiftPM resource bundles remain in `Contents/Resources`. Code shipped
inside `KeyPathAppKit` and `KeyPathInstallationWizard` must use their explicit
packaged-resource resolvers instead of `#bundle` or `Bundle.module`.
Installed-app verification must reject an app missing any target bundle or the
AppKit Metal library.

Never use successful execution from an extant build worktree as proof that a
packaged SwiftPM resource is available. Verify the app-root runtime lookup path
inside the installed app.
