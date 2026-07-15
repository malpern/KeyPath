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

## Host disk reserve

The Mini keeps a 100 GiB internal-data-volume reserve for runner builds,
indexing, and host OS work. `create` checks this reserve after taking the
provider admission lock and exits 75 with `disk_reserve_busy` when admitting a
new lease would be unsafe. It is an infrastructure wait, not a product failure.
`preflight` reports the current reserve evidence. Set
`KEYPATH_LAB_MIN_FREE_DISK_GIB` only for a deliberately different host policy.

The primary self-hosted CI and cache-warm workflows run
`Scripts/lab/host-disk-reserve` before expensive compilation. It exits 75 when
the same 100 GiB threshold is not met.

Check the non-mutating host/provider contract:

```bash
Scripts/lab/keypath-lab preflight
```

## Concurrent agents and provider admission

Agents may prepare code, artifacts, and local contract tests concurrently, but
VM creation is admitted centrally on the mini. The default host limits are one
active Tart lease and two active Parallels leases. `create` takes an atomic
provider-specific host-side admission lock, counts unexpired owned lease
manifests, and reserves capacity before another creator for that provider can
enter. Tart and Parallels provisioning can proceed in parallel. The lock is
held only during provisioning; each resulting manifest remains the capacity
reservation until the lease is destroyed or expires.

When a pool is full, `create` exits 75 and prints `capacity_busy` plus every
owning lease, OS, lane, expiry, commit, and slug. This is an infrastructure wait,
not a KeyPath failure. Agents should continue non-VM work or retry after the
reported lease is destroyed; they must not stop or adopt that lease. A dead
creator's admission lock is reclaimed automatically, while a live creator gets
a five-minute bounded window to finish provisioning.

The limits can be tuned on the mini with `KEYPATH_LAB_CAPACITY_TART` and
`KEYPATH_LAB_CAPACITY_PARALLELS`. Keep Tart at one until repeated concurrent
Tart runs prove that the host and provider inventory remain isolated.

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
  --lane unmanaged-ui \
  --commit "$SHA" \
  --installer dist/KeyPath.zip \
  --ttl 2h \
  --desktop

Scripts/lab/keypath-lab list
Scripts/lab/keypath-lab status cbx_example
Scripts/lab/keypath-lab install-app cbx_example
Scripts/lab/keypath-lab nameplate cbx_example enable
Scripts/lab/keypath-lab run cbx_example -- sw_vers
Scripts/lab/keypath-lab secure-dialog-input cbx_example \
  --app 'System Settings' --field Password --submit 'Modify Settings'
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

### Desktop-base admission

`--desktop` reserves a display-capable lease; it does not by itself prove that
the guest is ready for semantic UI automation. Before a scenario relies on
System Settings, admit the base through these postconditions:

- a real console user is logged in (not merely an SSH account);
- the guest has a Python runtime for the scenario drivers; and
- `Scripts/lab/peekaboo-ui preflight` succeeds for that console session.

If any condition is absent, record an `environment-precondition-failure`,
collect artifacts, and destroy the lease. Do not fall back to raw provider
commands or treat the result as a KeyPath failure. The macOS 26 Parallels base
observed on July 13, 2026 was SSH-ready but had no logged-in console user and
no Python runtime; it needs a new clean base checkpoint after automatic login
and desktop-tool provisioning before selector scenarios can run.

For a console-ready candidate base, run `desktop-bootstrap --install-tools`
once before capturing its checkpoint. It installs Python 3 as well as
Peekaboo and mcporter, then records the console-user and Peekaboo evidence.
This is base provisioning, not a per-scenario setup step.

### Disposable desktop identity with Nameplate

Nameplate can label an owned desktop lease without modifying its base image:

```bash
Scripts/lab/keypath-lab nameplate cbx_example enable
Scripts/lab/keypath-lab nameplate cbx_example status
Scripts/lab/keypath-lab nameplate cbx_example hide
Scripts/lab/keypath-lab nameplate cbx_example show
```

`enable` is accepted only for a desktop-enabled lease. It downloads the pinned
Nameplate `0.2.5` archive in the guest, verifies its SHA-256 checksum, Developer
ID signature, and Gatekeeper acceptance, and installs it beneath the console
user's `~/Applications`. The generated tag names the macOS lane, test lane,
provider, lease, and its disposable status. The version, checksum, visibility,
and last-change time are recorded in the owned lease manifest.

Nameplate's launch-at-login setting stays disabled because it registers an
`SMAppService` login item and would pollute the Background Items state that
KeyPath tests inspect. After a reboot, explicitly run `nameplate ... show`.
Automatic updates, watermarks, and connection-triggered splashes are also
disabled so a two-hour lease stays pinned and visually quiet.

Nameplate is operator instrumentation, not KeyPath evidence. `artifacts`
therefore hides a visible Nameplate before the controller screenshot and
restores it afterward. If hiding fails, the controller refuses to capture that
screenshot and records `unavailable:nameplate-hide-failed` instead of silently
producing contaminated evidence. Scenario scripts that take their own
screenshots should bracket them with `nameplate ... hide` and `show` as well.

### Semantic UI automation with Peekaboo 3

For the current capability matrix, security boundaries, and agent handoff
sequence, see
[`installer-gui-automation-capabilities.md`](installer-gui-automation-capabilities.md).

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
  Scripts/lab/permission-drag \
  --path /Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher \
  --target-identifier KeyPath_Title \
  --output "$OUT/permission-drag.json"
```

The Accessibility and Input Monitoring plus-button panels filter the raw
`kanata-launcher` executable and leave Open disabled. `permission-drag` uses
the supported KeyPath flow instead: reveal the exact binary in Finder, derive
the current source and permission-list target geometry from fresh AX snapshots,
and drag between the two arranged windows. It succeeds only when macOS presents
an authorization sheet or the expected permission row appears. If authorization
is requested, follow it with `secure-dialog-input` and verify the new
`kanata-launcher_Title` row before continuing. The adapter records both windows'
original geometry and restores it on every exit path, so a failed attempt does
not leave later UI targeting in a modified coordinate space.

The July 12 macOS 15 unmanaged spike confirmed that the authenticated synthetic
drag still did not create a `kanata-launcher` row. Treat the drag adapter as an
evidence-producing experiment, not a solved registration path, until its row
and canonical permission postconditions pass. See
[`p01-unmanaged-input-monitoring-spike.md`](p01-unmanaged-input-monitoring-spike.md).

Peekaboo click success means that it delivered an action to the selected UI
element. It is not proof that macOS accepted a protected change. Background App
Activity, Driver Extensions, Accessibility, and Input Monitoring must be
verified through the canonical CLI/system/runtime postcondition after every
click. Driver Extension activation on macOS 15 may still require CrabBox's
native RFB click delivery. Use fresh Peekaboo geometry to locate the control
and compare it with the current CrabBox desktop viewport before clicking. In
the Tart 1024x768 desktop lane, Peekaboo's Accessibility bounds already match
the 1024x768 VNC viewport even though the backing display reports 2048x1536;
doubling those coordinates targets the wrong pixel. Never infer a scale from
the backing display alone, and never preserve raw coordinates between runs.

For a macOS 15 Tart desktop lease, `secure-dialog-input` handles an
authentication sheet without putting its password in a command line. It focuses
the named field with Peekaboo, decrypts only `KEYPATH_TART_ADMIN_PASSWORD` on
the mini, and streams it over the lease-specific CrabBox SSH connection to
Peekaboo's supported MCP `type` tool. Peekaboo and `mcporter` must be installed
in the guest (`brew install steipete/tap/peekaboo steipete/tap/mcporter`).

The command suppresses the complete MCP response because Peekaboo's `type`
result contains the value it typed. The secret is never an argument, never
written to `commands.tsv`, and never retained as an artifact. Only the app,
field label, optional submit button, and pass/fail result are recorded. Do not
use the generic `run` command to improvise password entry. macOS 26 and 27
Parallels guests remain unsupported until they have an equally constrained
lease-specific transport.

On macOS 15 authentication sheets, use an explicit submit selector when the
button is available:

```bash
Scripts/lab/keypath-lab secure-dialog-input cbx_example \
  --app 'System Settings' --field Password --submit 'Modify Settings'
```

The controller must strip the encrypted dotenv record's terminating newline
before sending the password. A newline passed to Peekaboo's type transport can
become part of the secure-field value rather than a Return key. Always confirm
success by checking that the protected state changed. When `--submit` is used,
`secure_dialog_input passed` proves the secret transport completed and both the
named password field and submit control disappeared; it still does not prove
that macOS accepted the underlying protected-state change.

Driver-extension authorization is owned by `SecurityAgent`, whose secure
window is not available to Peekaboo snapshots. When a fresh framebuffer image
proves that its password field is already focused, use the constrained focused
mode without a submit selector:

```bash
Scripts/lab/keypath-lab secure-dialog-input cbx_example \
  --app SecurityAgent --field Password --already-focused
```

This mode skips AX discovery but uses the same stdin-only encrypted secret
transport. It is valid only after current visual evidence shows the focused
secure field, and success still requires the corresponding system-extension
postcondition.

When an authorization sheet exposes an `AXSecureTextField`, prefer the stricter
role-based path with a submit label. This covers both standalone SecurityAgent
windows and sheets hosted by System Settings. The controller writes the
streamed password to a mode-0600 guest temporary file long enough for
AppleScript to set the protected field in the named app, derives the submit button's
current center from AX geometry, and delivers a synthesized foreground pointer
click. The file is removed by an exit trap, the clipboard is never used, and
the helper succeeds only after that secure field disappears. It does not use
`sudo` as a password oracle because the disposable Tart image intentionally has
passwordless sudo.

For a protected control that requires native RFB delivery, use the lease-owned
guard instead of invoking CrabBox directly:

```bash
Scripts/lab/keypath-lab protected-click cbx_example \
  --app 'System Settings' \
  --window Accessibility \
  --ax-x 402 --ax-y 247
```

With `--ax-x` and `--ax-y`, the command measures the current display's logical
and native dimensions and converts Accessibility coordinates to framebuffer
coordinates. Raw native coordinates remain available as `--x` and `--y` for
diagnostics. The command snapshots the named app before and after delivery and fails
if either window title differs from the declared page. When the click is
expected to open another page or dialog, declare that explicitly with
`--after-window`. This guard detects a delivered click that landed on the wrong
System Settings surface; it does not replace the permission's canonical product
or system postcondition.

For ordinary text or single-key input on a macOS 15 desktop lease, use the
lease-owned VNC path rather than calling CrabBox directly:

```bash
Scripts/lab/keypath-lab desktop-type cbx_example --text q
```

The controller verifies ownership, desktop capability, OS lane, and the exact
provider resource before invoking CrabBox `desktop type`. On macOS this is an
RFB key event (`method=vnc-key`), not guest-side AppleScript or CGEvent
injection. The command proves delivery only; the scenario must separately
observe its expected application or runtime postcondition. P01 used a captured
key chip in KeyPath's Input Capture Experiment as that postcondition.

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
Those interactions must use the real logged-in System Settings UI. They may be
driven by Peekaboo or CrabBox RFB automation; directly modifying TCC or
bypassing macOS approval UI would invalidate the regression test. Every
automated interaction still requires the corresponding system/runtime
postcondition.

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
