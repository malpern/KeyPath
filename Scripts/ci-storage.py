#!/usr/bin/env python3
"""Admit CI scratch on a verified external volume; prune only finished jobs."""
import argparse
import fcntl
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

GIB = 1024 ** 3


def checked_volume(path, expected_uuid):
    if not expected_uuid:
        raise RuntimeError("KEYPATH_CI_VOLUME_UUID is required")
    info = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", str(path)]))
    if (info.get("VolumeUUID", "").upper() != expected_uuid.upper()
            or info.get("MountPoint") != str(path) or path.is_symlink()):
        raise RuntimeError("CI volume identity/mount mismatch; refusing startup-disk fallback")


def component(value):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise RuntimeError("Invalid CI path component")
    return value


def size(path):
    return int(subprocess.check_output(["du", "-sk", str(path)]).split()[0]) * 1024


def prune(root, now=None, budget=50 * GIB, age_days=7):
    """Never touch unmarked, active, or symlinked entries."""
    now = time.time() if now is None else now
    entries = []
    for path in root.iterdir():
        marker = path / ".completed"
        if path.is_symlink() or not path.is_dir() or not re.fullmatch(r"[0-9]+-[0-9]+-[A-Za-z0-9_-]+", path.name):
            continue
        if marker.is_symlink() or not marker.is_file():
            continue
        entries.append((marker.stat().st_mtime, path, size(path)))
    total = sum(item[2] for item in entries)
    for timestamp, path, byte_count in sorted(entries):
        if now - timestamp > age_days * 86400 or total > budget:
            print(f"Removing completed CI scratch: {path} ({byte_count // GIB} GiB)")
            shutil.rmtree(path)
            total -= byte_count


def run(action, env):
    volume = Path(env.get("KEYPATH_CI_VOLUME", "/Volumes/Foot Locker"))
    checked_volume(volume, env.get("KEYPATH_CI_VOLUME_UUID", ""))
    runner = component(env.get("RUNNER_NAME", ""))
    root = volume / "KeyPathCI" / runner
    # No writes until volume identity is verified. Refuse symlink redirects.
    for path in (volume / "KeyPathCI", root):
        if path.is_symlink():
            raise RuntimeError("CI scratch root cannot be a symlink")
        path.mkdir(exist_ok=True)

    lock_path = root / ".maintenance.lock"
    if lock_path.is_symlink():
        raise RuntimeError("CI maintenance lock cannot be a symlink")
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        operate(action, env, root, volume)


def operate(action, env, root, volume):

    if action == "finish":
        value = env.get("SCRATCH_PATH")
        if not value:
            return
        scratch = Path(value)
        if scratch.parent != root or scratch.is_symlink() or not scratch.is_dir():
            raise RuntimeError("Invalid scratch completion path")
        marker = scratch / ".completed"
        if marker.is_symlink():
            raise RuntimeError("CI completion marker cannot be a symlink")
        marker.touch()
        return

    # GitHub assigns one job at a time to a runner. Cleanup is confined to its
    # own completed jobs and never scans worktrees or other runners' directories.
    prune(root)
    if action == "cleanup":
        return
    startup_free = shutil.disk_usage("/System/Volumes/Data").free
    external_free = shutil.disk_usage(volume).free
    if startup_free < 100 * GIB or external_free < 100 * GIB:
        raise RuntimeError("CI requires 100 GiB free on both startup and scratch volumes")
    if startup_free < 150 * GIB or external_free < 200 * GIB:
        print("::warning::CI disk headroom is low; schedule targeted storage maintenance")
    run_id = component(env.get("GITHUB_RUN_ID", ""))
    attempt = component(env.get("GITHUB_RUN_ATTEMPT", ""))
    if not run_id.isdigit() or not attempt.isdigit():
        raise RuntimeError("Run ID and attempt must be numeric")
    output_path = env.get("GITHUB_ENV")
    if not output_path:
        raise RuntimeError("GITHUB_ENV is required for scratch admission")
    scratch = root / f"{run_id}-{attempt}-{component(env.get('GITHUB_JOB', ''))}"
    # Never reuse a previous job's completion marker or adopt unknown data.
    scratch.mkdir()
    with open(output_path, "a") as output:
        output.write(f"SCRATCH_PATH={scratch}\n")
    print(f"CI scratch admitted: {scratch}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "finish", "cleanup"))
    args = parser.parse_args()
    try:
        run(args.action, os.environ)
    except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as error:
        parser.exit(1, f"ci-storage: {error}\n")
