import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ci_storage", Path(__file__).parents[1] / "ci-storage.py")
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_wrong_volume_refused_without_creating_directory(self):
        volume = self.root / "missing"
        info = plistlib.dumps({"VolumeUUID": "wrong", "MountPoint": str(volume)})
        with patch.object(storage.subprocess, "check_output", return_value=info):
            with self.assertRaises(RuntimeError):
                storage.run("prepare", {"KEYPATH_CI_VOLUME": str(volume), "KEYPATH_CI_VOLUME_UUID": "expected"})
        self.assertFalse(volume.exists())

    def test_parent_filesystem_is_not_accepted_as_mount(self):
        info = plistlib.dumps({"VolumeUUID": "expected", "MountPoint": "/"})
        with patch.object(storage.subprocess, "check_output", return_value=info):
            with self.assertRaises(RuntimeError):
                storage.checked_volume(self.root, "expected")

    def test_unmounted_volume_error_does_not_create_fallback(self):
        env = {**self.environment(), "KEYPATH_CI_VOLUME": str(self.root / "absent")}
        with patch.object(storage.subprocess, "check_output", side_effect=storage.subprocess.CalledProcessError(1, "diskutil")):
            with self.assertRaises(storage.subprocess.CalledProcessError):
                storage.run("prepare", env)
        self.assertFalse((self.root / "absent").exists())

    def test_symlink_root_is_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.root / "KeyPathCI").symlink_to(outside, target_is_directory=True)
        with patch.object(storage, "checked_volume"):
            with self.assertRaises(RuntimeError):
                storage.run("prepare", self.environment())
        self.assertEqual(list(outside.iterdir()), [])

    def test_missing_uuid_refused(self):
        with self.assertRaises(RuntimeError):
            storage.checked_volume(self.root, "")

    def test_pruning_preserves_active_unknown_and_symlinked_data(self):
        old = self.root / "1-1-tests"
        old.mkdir()
        (old / ".completed").touch()
        os.utime(old / ".completed", (0, 0))
        active = self.root / "2-1-tests"
        active.mkdir()
        outside = self.root / "unknown"
        outside.mkdir()
        (outside / ".completed").touch()
        (self.root / "3-1-tests").symlink_to(outside, target_is_directory=True)
        with patch.object(storage, "size", return_value=10):
            storage.prune(self.root, now=10 * 86400)
        self.assertFalse(old.exists())
        self.assertTrue(active.exists())
        self.assertTrue(outside.exists())
        self.assertTrue((self.root / "3-1-tests").is_symlink())

    def test_budget_removes_oldest_completed_only(self):
        for i in [1, 2]:
            path = self.root / f"{i}-1-tests"
            path.mkdir()
            marker = path / ".completed"
            marker.touch()
            os.utime(marker, (i, i))
        with patch.object(storage, "size", return_value=10):
            storage.prune(self.root, now=3, budget=10)
        self.assertFalse((self.root / "1-1-tests").exists())
        self.assertTrue((self.root / "2-1-tests").exists())

    def environment(self):
        return {"KEYPATH_CI_VOLUME": str(self.root), "KEYPATH_CI_VOLUME_UUID": "expected",
                "RUNNER_NAME": "runner", "GITHUB_RUN_ID": "12", "GITHUB_RUN_ATTEMPT": "1",
                "GITHUB_JOB": "tests", "GITHUB_ENV": str(self.root / "env")}

    def test_prepare_finish_and_collision(self):
        env = self.environment()
        with patch.object(storage, "checked_volume"), patch.object(storage.shutil, "disk_usage") as usage:
            usage.return_value.free = 300 * storage.GIB
            storage.run("prepare", env)
            scratch = self.root / "KeyPathCI/runner/12-1-tests"
            self.assertTrue(scratch.is_dir())
            self.assertFalse((scratch / ".completed").exists())
            self.assertEqual((self.root / "env").read_text(), f"SCRATCH_PATH={scratch}\n")
            with self.assertRaises(FileExistsError):
                storage.run("prepare", env)
            storage.run("finish", {**env, "SCRATCH_PATH": str(scratch)})
            self.assertTrue((scratch / ".completed").exists())

    def test_missing_output_file_refused_without_orphan_directory(self):
        env = self.environment()
        del env["GITHUB_ENV"]
        with patch.object(storage, "checked_volume"), patch.object(storage.shutil, "disk_usage") as usage:
            usage.return_value.free = 300 * storage.GIB
            with self.assertRaisesRegex(RuntimeError, "GITHUB_ENV is required"):
                storage.run("prepare", env)
        self.assertFalse((self.root / "KeyPathCI/runner/12-1-tests").exists())

    def test_reserve_failure_does_not_admit_scratch(self):
        env = self.environment()
        with patch.object(storage, "checked_volume"), patch.object(storage.shutil, "disk_usage") as usage:
            usage.return_value.free = 50 * storage.GIB
            with self.assertRaises(RuntimeError):
                storage.run("prepare", env)
        self.assertFalse((self.root / "env").exists())

    def test_completion_rejects_outside_path(self):
        with patch.object(storage, "checked_volume"):
            with self.assertRaises(RuntimeError):
                storage.run("finish", {**self.environment(), "SCRATCH_PATH": str(self.root)})


if __name__ == "__main__":
    unittest.main()
