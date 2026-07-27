#!/usr/bin/env python3

import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
TOOL = ROOT / "Scripts/lab/pico-hid-fixture-tool"


class FixtureToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temporary.name)
        self.idf = self.directory / "esp-idf"
        self.fake_bin = self.directory / "bin"
        self.fake_bin.mkdir()
        self.idf.mkdir()
        (self.idf / "export.sh").write_text(f'export PATH="{self.fake_bin}:$PATH"\n')
        self.build = self.directory / "build"
        self.sdkconfig = self.directory / "sdkconfig"
        self.device_dir = self.directory / "dev"
        self.device_dir.mkdir()
        self.environment = os.environ.copy()
        self.environment.update({
            "KEYPATH_FIXTURE_HOST_OS": "Darwin",
            "KEYPATH_FIXTURE_IDF_PATH": str(self.idf),
            "KEYPATH_FIXTURE_BUILD_DIR": str(self.build),
            "KEYPATH_FIXTURE_SDKCONFIG": str(self.sdkconfig),
            "KEYPATH_FIXTURE_DEVICE_DIR": str(self.device_dir),
            "KEYPATH_FIXTURE_SECRETS_FILE": str(self.directory / "missing-secrets.env"),
            "KEYPATH_WIFI_SSID_1": "fixture-primary",
            "KEYPATH_WIFI_PASSWORD_1": "fixture-password-one",
            "KEYPATH_WIFI_SSID_2": "fixture-fallback-one",
            "KEYPATH_WIFI_PASSWORD_2": "fixture-password-two",
            "KEYPATH_WIFI_SSID_3": "fixture-fallback-two",
            "KEYPATH_WIFI_PASSWORD_3": "fixture-password-three",
            "KEYPATH_FIXTURE_TOKEN": "fixture-test-token-value",
        })

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_tool(self, *arguments: str, environment=None) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(TOOL), *arguments], text=True, capture_output=True,
                              env=environment or self.environment)

    def test_help_names_the_single_install_command(self) -> None:
        result = self.run_tool("help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install [--port DEV]", result.stdout)
        self.assertIn("never pass it on the command line", result.stdout)

    def test_doctor_accepts_environment_credentials_without_printing_values(self) -> None:
        result = self.run_tool("doctor")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("production credentials (values hidden)", result.stdout)
        self.assertIn("board not connected", result.stdout)
        self.assertNotIn(self.environment["KEYPATH_WIFI_PASSWORD_1"], result.stdout + result.stderr)
        self.assertNotIn(self.environment["KEYPATH_FIXTURE_TOKEN"], result.stdout + result.stderr)

    def test_doctor_rejects_missing_or_placeholder_credentials(self) -> None:
        environment = self.environment.copy()
        environment.pop("KEYPATH_FIXTURE_TOKEN")
        result = self.run_tool("doctor", environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertRegex(result.stderr, r"sops is required|encrypted secrets file is missing")

        environment = self.environment.copy()
        environment["KEYPATH_FIXTURE_TOKEN"] = "fixture-placeholder-token"
        result = self.run_tool("doctor", environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("placeholder", result.stderr)

    def test_build_uses_the_configured_cache_and_checks_for_output(self) -> None:
        idf_log = self.directory / "idf.log"
        fake_idf = self.fake_bin / "idf.py"
        fake_idf.write_text(textwrap.dedent(f"""\
            #!/bin/bash
            set -eu
            printf '%s\\n' "$*" >> {str(idf_log)!r}
            build_dir=
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == -B ]]; then build_dir=$2; shift 2; else shift; fi
            done
            mkdir -p "$build_dir"
            : > "$build_dir/keypath_esp32_s3_hid_fixture.bin"
        """))
        fake_idf.chmod(0o755)

        result = self.run_tool("build")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.build / "keypath_esp32_s3_hid_fixture.bin").is_file())
        invocation = idf_log.read_text()
        self.assertIn(str(self.build), invocation)
        self.assertIn(f"SDKCONFIG={self.sdkconfig}", invocation)
        self.assertNotIn(self.environment["KEYPATH_FIXTURE_TOKEN"], invocation)


if __name__ == "__main__":
    unittest.main()
