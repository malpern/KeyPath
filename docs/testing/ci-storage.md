# CI storage on the Mac mini

SwiftPM test and coverage scratch belongs on `/Volumes/Foot Locker`, under
`KeyPathCI/<runner>/<run-id>-<attempt>-<job>`. Source checkouts and the runner
service remain on the startup disk. No app interface or installed runtime changes.

`Scripts/ci-storage.py prepare` verifies the exact mount point and the APFS volume
UUID before making directories. GitHub repository variable `KEYPATH_CI_VOLUME_UUID`
holds that identity. A missing variable, missing mount, wrong volume, or symlinked
root fails closed: it must never create a substitute directory on the startup disk.
The workflows retain the existing startup reserve check, and preparation requires
100 GiB free on **both** startup and external storage. Warnings begin below
150 GiB startup or 200 GiB external. These are free-space thresholds, not quotas;
the external APFS volumes share their container's available capacity.

Each job owns a new scratch directory. Its final build/coverage step is followed
by an `always()` completion step. Only directories with a regular `.completed`
marker and the expected job naming pattern are eligible for cleanup. Preparation
and weekly cleanup remove completed directories older than seven days, then the
oldest completed directories until at most 50 GiB remains per runner. This limit
applies at cleanup time, not continuously during a build. Active or interrupted
jobs without a completion marker, unknown directories, and symlinked directories
are preserved. Inspect abandoned jobs against GitHub and running processes before
removing their scratch manually. A per-runner filesystem lock serializes maintenance.

Coverage uses the same `SCRATCH_PATH` for compilation and report extraction.
Local coverage keeps its `.build` default.

## Runner installation

On the mini's `clawd` account, install the checked-in scripts:

```bash
mkdir -p ~/.local/lib/keypath ~/.config
cp Scripts/ci-storage.py ~/.local/lib/keypath/ci-storage.py
install -m 755 Scripts/runner-cleanup.sh ~/actions-runner-cleanup.sh
```

Create `~/.config/keypath-ci-storage.env` (mode 600) with:

```bash
export KEYPATH_CI_VOLUME="/Volumes/Foot Locker"
export KEYPATH_CI_VOLUME_UUID="<VolumeUUID from diskutil info -plist>"
```

Use the same UUID in the GitHub repository variable. Never derive the expected
UUID dynamically during a job: that would accept an unintended replacement disk.

### macOS removable-volume permission

An SSH probe does not prove that the LaunchAgent runner can access removable
volumes. The first real CI probe hit `Operation not permitted` opening the lock;
TCC logs attributed the request to the runner's bundled Node executable at
`/Users/clawd/actions-runner-2/externals.2.337.0/node20/bin/node`, not Python.
The removable-volume prompt timed out while `malpern` owned the desktop.

Sign into the runner account (`clawd`) and approve its Removable Volumes request
through the normal macOS UI (Privacy & Security → Files & Folders). Rerun CI while
that desktop is active if the prompt needs to be presented again. Do not edit the
TCC database or route writes through SSH to bypass the runner permission. Runner
updates can replace the executable, so verify access again after an update.

The existing `com.keypath.runner-cleanup` LaunchAgent runs Sundays at 03:00 and
logs to `~/Library/Logs/runner-cleanup.log`. It skips maintenance when a runner
worker is active. It prunes only the two configured KeyPath runner scratch roots,
then sends a Pushover warning through the existing `notify-push` wrapper if free
space is below the warning thresholds. CI also reports low headroom as a workflow
warning. No additional scheduler is required.

## Recovery and rollback

If admission fails, verify the mount and free space first. Do not lower the reserve
or create the mount directory by hand. Reconnect the expected volume, or deliberately
configure and verify a replacement UUID. To revert external scratch routing, revert
the workflow changes; keep the startup reserve guard. Retained external scratch can
be inspected and removed after its jobs finish.

The initial September 2026 recovery removed a discarded iPhone restore image and
rebuildable package/Xcode caches, then used `tmutil thinlocalsnapshots` to release
blocks retained by local Time Machine snapshots after confirming a recent network
backup. Startup free space rose from 61 to 104 GiB. Network backups, VM lab volumes,
working trees, installed toolchains, and personal Downloads were preserved. This
cleared the hard gate but did not reach the 150 GiB warning target.

The prior weekly cleanup script was backed up at
`~/runner-storage-backup-20260904/actions-runner-cleanup.sh`. It swept `.build`
directories by age; the replacement deliberately confines deletion to completed CI
scratch. Prefer retaining that safer cleanup even if workflow routing is reverted.

## Validation

```bash
python3 -m unittest discover -s Scripts/tests -p test_ci_storage.py
bash -n Scripts/runner-cleanup.sh Scripts/generate-coverage.sh
```

A live probe must confirm a new directory on the external volume, a completion
marker, and rejection of a wrong UUID without a startup-disk fallback. The final
integration check is a full GitHub `build-and-test` job using the admitted path.
