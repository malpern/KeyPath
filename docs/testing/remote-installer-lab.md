# Remote KeyPath Installer Lab

`Scripts/lab/keypath-lab` is the supported controller for disposable installer
testing on the existing Mac mini lab. It defaults to
`clawd@keypath-lab-mini`; use `--host` or `KEYPATH_LAB_HOST` for another SSH
alias that exposes the same lab contract.

The controller does not modify disk layout, the host's main drive, the stopped
Parallels base VM, or the Tart OCI base image. Destructive commands require an
exact `keypath-installer-lab-v1` ownership manifest under:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/leases/<lease-id>/`

Only disposable leases created by this interface can be destroyed or swept.
Logs, manifests, commands, results, screenshots, and collected test artifacts
remain beneath `KeyPathInstallerLab` on the external volume after cleanup.

## Prerequisites

- SSH access to `clawd@keypath-lab-mini` without an interactive password.
- `/Volumes/KeyPath Lab/CrabBox/keypath15`, `keypath26`, and `keypath27` executable.
- Shared CrabBox 0.36.0 tools beneath `CrabBox/SharedTools`.
- A full 40-character KeyPath commit SHA present in the local repository.
- A signed installer artifact whose SHA-256 checksum can be recorded.

`--ttl` defaults to `2h` and accepts values from one second through two hours,
matching the maximum lifecycle exposed by the existing launchers.

Check the non-mutating host/provider contract:

```bash
Scripts/lab/keypath-lab preflight
```

## Lifecycle

Creation never syncs the current worktree. It exports the explicit commit with
`git archive`, adds the installer and source metadata, uploads that immutable
payload, and atomically initializes a clean synthetic archive on the external
lab volume. Each lease receives its own clean checkout cloned from that archive.
CrabBox's claim therefore binds one disposable lease to one stable repository
root, and every run, download, and destructive stop executes from that exact
claimed checkout. The interface refuses to sync if Git reports tracked or
nonignored untracked changes.

Uploads use a host-generated, owner-only `mktemp` ticket rather than a
commit-derived `/tmp` filename. Publishing the immutable archive is protected by
a per-key lock, so concurrent requests either publish once or validate and reuse
the completed archive.

```bash
SHA=$(git rev-parse HEAD)
Scripts/lab/keypath-lab create \
  --macos 27 \
  --commit "$SHA" \
  --installer dist/KeyPath.zip \
  --ttl 2h \
  --desktop

Scripts/lab/keypath-lab list
Scripts/lab/keypath-lab status cbx_example
Scripts/lab/keypath-lab install-app cbx_example
Scripts/lab/keypath-lab run cbx_example -- sw_vers
Scripts/lab/keypath-lab artifacts cbx_example
Scripts/lab/keypath-lab destroy cbx_example
Scripts/lab/keypath-lab cleanup --dry-run
Scripts/lab/keypath-lab cleanup
```

Every manifest records the source commit, macOS product version and build,
provider, installer name and checksum, expiration, commands/results, artifact
collection, and cleanup state. `destroy` is idempotent after successful cleanup.
Artifact collection packages scenario output inside the guest and retrieves the
single archive with CrabBox's native, owner-only `run --download` path. It does
not parse private SSH-key locations or invoke `scp`. CrabBox 0.36's provider
`cp` command is not supported by these providers, and its aggregate desktop
artifact workflow requires a desktop-enabled lease.

Pass `--desktop` when approval interaction or screenshots are required. The
controller mirrors the existing provider launcher configuration while adding
CrabBox's desktop capability; ordinary creation continues to use the launchers
unchanged. Artifact collection captures a screenshot for desktop leases and
records an explicit unavailable status otherwise.

### Semantic UI automation with Peekaboo 3

Desktop guests can use `Scripts/lab/peekaboo-ui` to discover and operate
KeyPath and System Settings without framebuffer coordinate assumptions. The
adapter provides typed commands for snapshots, semantic clicks, dialog
inspection, file selection, and Retina screenshots. Every command writes JSON
evidence alongside the scenario output so it is included by `artifacts`.

```bash
OUT=.keypath-lab/scenario-output/approvals/peekaboo

Scripts/lab/keypath-lab run cbx_example -- \
  Scripts/lab/peekaboo-ui preflight
Scripts/lab/keypath-lab run cbx_example -- \
  Scripts/lab/peekaboo-ui snapshot \
  --app 'System Settings' --output "$OUT/input-monitoring.json"
Scripts/lab/keypath-lab run cbx_example -- \
  Scripts/lab/peekaboo-ui click \
  --app 'System Settings' --query Add --output "$OUT/add-click.json"
Scripts/lab/keypath-lab run cbx_example -- \
  Scripts/lab/peekaboo-ui file \
  --app 'System Settings' \
  --path /Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher \
  --output "$OUT/file-dialog.json"
```

Peekaboo click success means that it delivered an action to the selected UI
element. It is not proof that macOS accepted a protected change. Background App
Activity, Driver Extensions, Accessibility, and Input Monitoring must be
verified through the canonical CLI/system/runtime postcondition after every
click. Driver Extension activation on macOS 15 may still require CrabBox's
native RFB click delivery. Use fresh Peekaboo geometry to locate the control,
convert logical points to framebuffer coordinates using the current display
scale, and verify activation afterward; never preserve raw coordinates between
runs.

The adapter deliberately has no password-input command. Do not put a lab
password in a command line, workflow file, shell trace, or collected artifact.
Authentication-sheet automation needs a separate secure credential-injection
contract before it becomes part of the reusable workflow.

`install-app` expands the staged ZIP into `/Applications` on the disposable
guest. Tart uses the base image's noninteractive sudo contract. Parallels uses
the same passwordless `prlctl exec` guest-control channel CrabBox already uses
to prepare the disposable clone, scoped to the exact provider resource recorded
in the owned lease manifest. Neither path changes the base image or stores a
guest password.

## Installer scenarios

Run a named scenario after creating a lease:

```bash
Scripts/lab/keypath-lab scenario cbx_example clean-install
Scripts/lab/keypath-lab scenario cbx_example approvals
Scripts/lab/keypath-lab scenario cbx_example helper-daemon-health
Scripts/lab/keypath-lab scenario cbx_example launch
Scripts/lab/keypath-lab scenario cbx_example repair-reinstall
Scripts/lab/keypath-lab scenario cbx_example reboot-persistence-before
# Reboot the disposable guest through the approved lab workflow.
Scripts/lab/keypath-lab scenario cbx_example reboot-persistence-after
Scripts/lab/keypath-lab scenario cbx_example uninstall
Scripts/lab/keypath-lab scenario cbx_example cancellation-failure
Scripts/lab/keypath-lab scenario cbx_example artifact-capture
Scripts/lab/keypath-lab scenario cbx_example macos-27-regression
Scripts/lab/keypath-lab artifacts cbx_example
```

The scenario set covers clean installation, every macOS approval gate,
helper/daemon and TCP health, launch, repair/reinstall, reboot persistence,
uninstall, cancellation/failure rendering, and final artifact capture. Approval
and cancellation cases intentionally give an operator a controlled observation
point rather than attempting to bypass macOS security UI. Never place Apple IDs,
passwords, private keys, TCC databases, or other credentials in a scenario or
artifact bundle. CrabBox does not redact collected files automatically; inspect
every bundle before sharing or publishing it.

### macOS 27 beta regression capture

On every significant macOS 27 beta seed, run the non-destructive evidence
capture on an installed signed and notarized build:

```bash
Scripts/qa-macos-27-regression.sh
```

For a disposable macOS 27 desktop lease, run the same capture after installing
the app:

```bash
Scripts/lab/keypath-lab scenario cbx_example macos-27-regression
Scripts/lab/keypath-lab artifacts cbx_example
```

The command records the exact OS build, canonical CLI system snapshot,
VirtualHID extension state, KeyPath-owned launchd jobs, signatures, Gatekeeper
and stapling results, processes, TCP readiness, and relevant logs. It also emits
an operator checklist for Accessibility, Input Monitoring, Background App
Activity, Driver Extension approval, overlay behavior, and reboot persistence.
Those interactions remain manual because programmatically modifying TCC or
bypassing macOS approval UI would invalidate the regression test.

Distribution trust checks are required by default. For harness development
against a locally signed debug deployment only, set
`KEYPATH_MACOS27_QA_REQUIRE_DISTRIBUTION_TRUST=0`; never use that override for a
release or beta-seed result.

## Failure and recovery

- If creation reports a lease but guest verification fails, preserve the lease
  ID and logs, inspect it with `status`, collect artifacts, then `destroy` it.
- If cleanup fails, the manifest remains `cleanup-failed`; the interface does
  not discard evidence or pretend the provider object was deleted.
- `cleanup` considers only expired manifests owned by this interface. It never
  invokes a provider-wide cleanup and never deletes archive caches or base
  images. The final `crabbox stop` runs from the exact checkout recorded in the
  lease manifest so CrabBox's own repository claim remains an additional
  destructive-operation guard.
- To test a different SSH endpoint, pass `--host user@host`; do not edit the
  launchers or embed host credentials in the repository.

## Local contract tests

The shell tests use fake launchers and a temporary lab root; they never contact
the mini or provision a VM:

```bash
Scripts/lab/tests/keypath-lab-tests.sh
```
