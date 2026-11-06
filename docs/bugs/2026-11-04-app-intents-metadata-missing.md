# App Intents metadata is never generated for the shipped app

Status: fix in the build, discovery unverified. Investigated 2026-11-04
(finding 5 of the 2026-10-31 architecture review). Option A below is
implemented as `Scripts/generate-app-intents-metadata.sh`, called from
`Scripts/build-and-sign.sh`. Whether Shortcuts and Siri then find the intents
has not been checked on a real install yet.

## Summary

KeyPath defines three App Intents, one App Entity, one App Enum and an
`AppShortcutsProvider` in `Sources/KeyPathAppKit/Intents/`, and
[`docs/guides/app-intents.md`](../guides/app-intents.md) says they work in
Siri, Shortcuts and Spotlight. They most likely do not. macOS finds an app's
intents through a `Metadata.appintents` bundle in `Contents/Resources/`. Xcode
writes that bundle with `appintentsmetadataprocessor` as a build step. KeyPath
is built with `swift build` and its bundle is assembled by hand in
`Scripts/build-and-sign.sh`, and nothing in that path runs the processor.

The fix generates the bundle during the release build (option A below).

## Evidence

- `Scripts/build-and-sign.sh` copies the executables, `Info.plist`,
  `Sources/KeyPathApp/Resources/` and the SwiftPM resource bundles into
  `dist/KeyPath.app`. None of those contains `Metadata.appintents`, and no file
  in `Scripts/` or `.github/` mentions `appintents`.
- Nothing in the repo or in `.build` (debug, Swift Build system) is named
  `*.appintents`: SwiftPM does not run the extractor for package products.
- Not yet checked: a built `dist/KeyPath.app` (none exists on this Air), and
  whether the installed 1.0.1 app shows any actions in Shortcuts. The second
  check needs a machine with KeyPath installed (a vm-lab desktop guest).

## What the processor needs, and what SwiftPM already provides

`appintentsmetadataprocessor` (in the Xcode toolchain, `xcrun -f
appintentsmetadataprocessor`) reads the Swift compiler's *const values*: JSON
files listing every type that conforms to an App Intents protocol, with its
compile-time-known properties. Under Xcode 27, SwiftPM's default build system
(Swift Build) already writes them, one `.swiftconstvalues` per source file,
next to the objects:

```
.build/out/Intermediates.noindex/KeyPath.build/<Config>/KeyPathAppKit-t.build/Objects-normal/arm64/*.swiftconstvalues
```

`KeyPathShortcuts.swiftconstvalues` there lists the
`AppIntents.AppShortcutsProvider` conformance and its phrases.

`build-and-sign.sh` passes `--build-system` only when `KEYPATH_BUILD_SYSTEM`
is set to something other than `native`. Left unset, `swift build` uses its
own default, which on Xcode 27 is Swift Build, so the default release build
should produce const values too. Checked for both a debug and a release
build. The
deprecated `--build-system native` may not write them; check before relying
on it.

## Invocation that works

Run against the debug build in this worktree on 2026-11-04 (Xcode 27.0,
27A266a), writing to a scratch directory:

```bash
OBJ=.build/out/Intermediates.noindex/KeyPath.build/Debug/KeyPathAppKit-t.build/Objects-normal/arm64
find Sources/KeyPathAppKit -name '*.swift' > /tmp/ai-sources.txt
ls "$OBJ"/*.swiftconstvalues > /tmp/ai-constvals.txt

"$(xcrun -f appintentsmetadataprocessor)" \
  --output "$OUT_DIR" \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name KeyPathAppKit \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
  --platform-family macOS \
  --deployment-target 15.0 \
  --target-triple arm64-apple-macos15.0 \
  --bundle-identifier com.keypath.KeyPath \
  --source-file-list /tmp/ai-sources.txt \
  --swift-const-vals-list /tmp/ai-constvals.txt \
  --compile-time-extraction
```

It wrote `$OUT_DIR/Metadata.appintents/{extract.actionsdata,version.json}`
(about 8 KB). `extract.actionsdata` contains:

- actions `GetCurrentLayerIntent`, `SendActionIntent`, `ServiceControlIntent`
- entity `LayerEntity`, enum `ServiceAction`
- 3 auto shortcuts, provider `13KeyPathAppKit0aB9ShortcutsV`

The provider's mangled name is present in the linked `KeyPath` executable
(`nm .build/debug/KeyPath`), because `KeyPathAppKit` is linked statically.

Flags worth knowing: `--help` is not supported (it prints usage after an
"Unable to parse options" error). The full option set Xcode uses is in
`AppIntentsMetadata.xcspec` inside
`Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework`. Xcode also passes
`--dependency-file` and `--stringsdata-file`, which matter for incremental
builds and for localising shortcut phrases; neither is needed for a one-shot
release build.

## Intents in a library target

The intents live in `KeyPathAppKit`, a library, not in the `KeyPath`
executable target (`Sources/KeyPathApp/Main.swift`). The processor handles
that: run with `--module-name KeyPathAppKit`, it extracted everything above.

What is not verified is whether macOS accepts metadata whose module is the
library rather than the app's main module. Apple's supported pattern for
intents in a package is:

1. the library declares a type conforming to `AppIntentsPackage`;
2. the app's main module declares its own `AppIntentsPackage` listing it in
   `includedPackages`;
3. Xcode runs the processor for the library, then for the app with
   `--static-metadata-file-list` pointing at the library's metadata, and only
   the app's merged `Metadata.appintents` ships.

KeyPath has no `AppIntentsPackage` conformance today. Option A below skips it
and generates the metadata for `KeyPathAppKit` directly. If Shortcuts does not
pick that up, option B adds the two conformances and the two-step run.

## Options

**A. Generate `KeyPathAppKit` metadata in `build-and-sign.sh` (recommended
first step).** After the release `swift build`, run the invocation above
against the release const values with `--output "$RESOURCES"`, so the bundle
lands at `KeyPath.app/Contents/Resources/Metadata.appintents` before codesign.
Fail the build rather than shipping without it, and check content, not just
presence: an empty const-values list (the intermediates path above is
hard-coded to the scratch layout, config, target suffix and arch, and
`swift build` has no `--show-bin-path` equivalent for it) may still let the
processor emit a `Metadata.appintents` with no actions. So fail when the
const-values list is empty, and when `extract.actionsdata` does not name all
three intents. `Scripts/verify-installed-app.sh` could make the same check. About 20 lines of shell, no Swift changes.
`Metadata.appintents` is plain resource data, so it is sealed by the existing
`codesign` of the app and needs nothing new for notarization.

**B. Option A plus `AppIntentsPackage` conformances and a two-step run.**
Closer to what Xcode does. Use it if A turns out not to be discovered.

**C. Move the intents into the `KeyPath` executable target.** Simplest
metadata story, but the intents call into `KeyPathAppKit` internals, so it
means widening access control. Not worth it unless A and B both fail.

**D. Remove the claim.** If none of this is wanted before 1.x, take the
Siri/Shortcuts promises out of `docs/guides/app-intents.md` so the guide
matches what ships.

## What was implemented

Option A, approved by Micah on 2026-11-04.
`Scripts/generate-app-intents-metadata.sh <resources-dir> [Release|Debug]`
runs the invocation above with the bundle ID and deployment target read from
`Sources/KeyPathApp/Info.plist`. `build-and-sign.sh` calls it after the
resources are copied and before codesign, so `Metadata.appintents` is sealed
with the rest of `Contents/Resources`. The script fails the build when:

- there are no Swift Build intermediates (a `--build-system native` build);
- no const values are found. A release (whole-module) build writes one
  `KeyPathAppKit-primary.swiftconstvalues`; a debug build writes one file per
  source. The script takes per-source files only for current sources, so one
  left by a deleted source is ignored, and when both layouts are present it
  uses whichever was written last;
- the processor fails or writes no `extract.actionsdata` (it skips writing
  output when it finds no intents);
- the extract does not match the sources. `Scripts/check-app-intents-metadata.py`
  finds every type in `Sources/KeyPathAppKit` declared as conforming to
  `AppIntent`, `AppEntity`, `AppEnum` or `AppShortcutsProvider`, and requires
  each in the extract. It reads declaration lines (attributes, generics,
  extensions and protocols that refine `AppIntent`, such as `OpenIntent`,
  are handled); it is a drift guard, not a Swift parser, so a conformance it
  cannot see is not required. Its tests are in
  `Scripts/tests/test_check_app_intents_metadata.py`
  (`python3 -m unittest Scripts.tests.test_check_app_intents_metadata`). No CI
  job runs `Scripts/tests/` yet, so they run only by hand.

`Scripts/verify-installed-app.sh` runs the same check on an installed app,
after the trust checks, whenever it requires notarization (override with
`REQUIRE_APP_INTENTS_METADATA`). The expected types come from the checkout
it runs from, so verify an install built from the same tree. And `Scripts/release-doctor.sh` checks that
the selected Xcode has the processor.

Each of those paths was run against a fake scratch directory, and the success
path against real Debug and Release builds.

`quick-deploy.sh` and `ui-deploy.sh` do not run it, so development deploys
still have no intents metadata.

## Still to verify

On a vm-lab desktop guest (needs the Mac mini, offline for service as of
2026-11-04), with a release-candidate build:

1. `ls KeyPath.app/Contents/Resources/Metadata.appintents`;
2. install, launch once, and check that Shortcuts lists the three KeyPath
   actions, the Siri phrases resolve, and "Control KeyPath Service" offers
   Start / Stop / Restart;
3. if nothing appears, try option B before concluding. Keep the status notes
   in `guides/siri-and-shortcuts.md` (user-facing, ships as offline help) and
   `docs/guides/app-intents.md` until it works.

`--xcode-version` takes the build string (`27A266a`): Xcode's xcspec passes
`$(XCODE_PRODUCT_BUILD_VERSION)`, and the metadata records it as
`toolsVersion`.
