# Fresh driverless release prerequisites

Read-only investigation on 2026-10-06, for integrated product
`8e66aca43d1435677858f4504893dfe613b1a5b2`. The root reports 180 focused
package tests passed. This investigation performed no component installation,
submodule update, build, notarization, deployment, VM or physical-input action.

## 1. Enable fresh Metal compilation

The canonical selector in `Scripts/lib/xcode.sh` chooses Xcode 27.0 at
`/Applications/Xcode-27.app/Contents/Developer` (installed build `27A266a`).
`xcrun -sdk macosx metal -v` still fails because Metal Toolchain is missing.
The older 26.6 path in AGENTS.md is stale; do not change global `xcode-select`
to follow it. Apple's [component installation documentation](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
documents downloading the Metal component. The repository already supplies
the selected-Xcode installer and a compiler reprobe:

```bash
./Scripts/ensure-metal-toolchain.sh
```

This invokes the selected `xcodebuild -downloadComponent MetalToolchain` and
changes installed host components/download storage. **Explicit host-component
authorization is required; the present read-only task excludes it.** Do not
add sudo, change permissions, reinstall Xcode or upgrade other components.
Once authorized and installed, prove actual fresh compilation rather than
component metadata or the previously copied metallib:

```bash
bash -euc '
source Scripts/lib/xcode.sh
keypath_use_stable_xcode
probe_dir=$(mktemp -d /private/tmp/keypath-metal-probe.XXXXXX)
xcrun -sdk macosx metal \
  Sources/KeyPathAppKit/UI/KeyboardStage/Metal/KeyboardStage.metal \
  -o "$probe_dir/default.metallib"
shasum -a 256 Sources/KeyPathAppKit/UI/KeyboardStage/Metal/KeyboardStage.metal \
  "$probe_dir/default.metallib"
'
```

Keep `Plugins/CompileKeyboardStageMetal/CompileKeyboardStageMetal.swift`
unmodified during the ensuing package/release gate. Cached-shader tests do not
qualify this step.

## 2. Obtain and assert the exact companion source

Product gitlink: `0853689f04d40f6b8d283fef80e34b3d53531b89`, repository
`https://github.com/malpern/kanata.git`. A read-only GitHub commit lookup confirmed
[the commit](https://github.com/malpern/kanata/commit/0853689f04d40f6b8d283fef80e34b3d53531b89)
exists with tree `0c0e6af72dfa9c1c3eab9dfa9db51441efb9ff7a`. Its `src/lib.rs`
lines 54–62 map a numeric UInt16 port to `127.0.0.1:port`. This is direct pinned
source evidence, not evidence of the preserved bridge's build inputs.

The inspected release/root worktrees lack a populated Kanata submodule; the
main checkout's older populated submodule lacks this object. Do not change
that checkout or substitute its `79bd7fab…` HEAD. After the root authorizes a
dedicated fresh build checkout, use the product gitlink, never `--remote`:

```bash
git worktree add --detach /private/tmp/keypath-driverless-fresh-release \
  8e66aca43d1435677858f4504893dfe613b1a5b2
cd /private/tmp/keypath-driverless-fresh-release
git submodule update --init --checkout --recursive External/kanata
test -f External/kanata/Cargo.toml
test "$(git -C External/kanata rev-parse HEAD)" = \
  0853689f04d40f6b8d283fef80e34b3d53531b89
test -z "$(git status --porcelain --untracked-files=normal)"
test -z "$(git -C External/kanata status --porcelain --untracked-files=normal)"
```

These commands write checkout/submodule metadata and fetch source; **they are
not authorized for execution in this read-only task**. They preserve the main
checkout and gitlink. Stop on missing source, changed lockfiles or a different
HEAD. `keypath_ensure_kanata_submodule` only checks for `Cargo.toml` when source
already exists, so invoking the builder alone does not assert the pin.

The preserved accepted packaged bridge with SHA prefix `9410b3bc…` remains an
older accepted artifact. Its acceptance must not be described as a fresh build
from this pin. Rust/cargo 1.99.0 and both Apple Darwin targets are already
installed; no Rust installation is currently indicated.

## 3. Assemble a fresh signed candidate without external side effects

**Wait for the root's exclusive build slot and build authorization.** In the
new checkout above, with empty local build outputs and no copied caches:

```bash
SKIP_DEPLOY=1 SKIP_NOTARIZE=1 SKIP_SPARKLE=1 SKIP_WEBSITE=1 \
  SKIP_SNAPSHOTS=1 SKIP_PEEKABOO=1 \
  ./Scripts/build-and-sign.sh
./Scripts/verify-identity-contract.sh --app dist/KeyPath.app
APP_PATH="$PWD/dist/KeyPath.app" CHECK_RUNTIME=0 \
  REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

This retains real Developer ID signing and creates `dist/KeyPath.app`; it does
not qualify notarization or running-session readiness. The builder acquires the
shared deploy lock even with `SKIP_DEPLOY=1`, recreates its local `dist/`, and
can download Cargo/Swift dependencies. Its Rust builds do not pass `--locked`:
assert unchanged source/lockfiles again afterward and refuse qualification if
dependency resolution changed them. No component installer runs in this path.

`build-and-sign.sh` builds KeyPath, `keypath-cli`, Insights, engine, simulator,
and host bridge, and embeds Sparkle plus SwiftPM resources. Helper, launcher,
DriverKit installer and LaunchDaemons are deliberately absent. The source
signing and identity checks explicitly enforce that omission; restoring them
is not a prerequisite. The CLI's new command surface must come from this fresh
product build. KeyPath supports Apple Silicon only. Release Swift builds explicitly
target `arm64`, and `Scripts/verify-apple-silicon.sh` rejects missing, Intel or mixed
architecture KeyPath components before signing and during installed-app verification.
The Rust engine's `kanata-universal` filename is retained for existing callers;
its contents are ARM64, not a universal binary. Vendored frameworks may retain
additional architectures without extending KeyPath's supported hardware.

Preserve the build log, full product/gitlink identities, clean-source checks,
`rustc --version --verbose`, `cargo --version`, selected Xcode/linker identity,
`build/kanata-host-bridge/host-bridge-cache.info`, bridge/header/crate/lockfile
hashes, fresh shader/plugin/metallib hashes, and final signed bundle/file hashes.
The bridge cache fingerprint includes source/pin/features/toolchain inputs;
recording only that opaque fingerprint or an old packaged SHA is insufficient.
The fresh log must show compilation rather than a reused companion cache.

## Subsequent gates

The root owns the final full package gate, rebuilt CLI/help acceptance, and
exact signed app/session/physical-input acceptance. Notarization, stapling,
installation and public release are **outside this authorization**. Do not run
`release-candidate.sh` for the bounded assembly above: its defaults notarize and
deploy. After separate authorization, `release-candidate.sh` is the canonical
notarized/deployed path and `verify-installed-app.sh` must retain default trust,
staple and runtime checks. Older production migration remains out of scope.

## Investigation checks

Read-only Metal probe reproduced the missing-component failure. GitHub commit
and pinned-source reads succeeded through scoped read-only network escalation.
`verify-release-signing-contract.sh --source` and
`verify-identity-contract.sh --source` passed. No secrets were printed.
