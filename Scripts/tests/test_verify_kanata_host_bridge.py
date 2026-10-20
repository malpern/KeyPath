"""Failure-contract checks for the bridge packaging gate; no OS input/output."""
import importlib.util
import io
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "verify-kanata-host-bridge.py"
spec = importlib.util.spec_from_file_location("verify_host_bridge", SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def bridge_fixture():
    results = {
        "version": b"test", "default_cfg_count": 0,
        "validate_config": True, "create_runtime": 1,
        "runtime_layer_count": 1, "destroy_runtime": None,
        "create_passthru_runtime": 2, "passthru_runtime_layer_count": 1,
        "passthru_try_recv_output": 0, "destroy_passthru_runtime": None,
        "start_passthru_runtime": True, "passthru_send_input": True,
        "passthru_is_input_mapped": True,
    }
    return SimpleNamespace(**{
        "keypath_kanata_bridge_" + name: mock.Mock(return_value=result)
        for name, result in results.items()
    })


class VerifyHostBridgeTests(unittest.TestCase):
    def run_verifier(self, bridge, *args):
        with mock.patch.object(verifier.sys, "argv", [str(SCRIPT), "bridge.dylib", *args]), \
             mock.patch.object(verifier.os.path, "isfile", return_value=True), \
             mock.patch.object(verifier.ctypes, "CDLL", return_value=bridge), \
             mock.patch.object(verifier.sys, "stdout", io.StringIO()), \
             mock.patch.object(verifier.sys, "stderr", io.StringIO()):
            return verifier.main()

    def test_load_only_remains_available_without_driverless_symbols(self):
        bridge = bridge_fixture()
        del bridge.keypath_kanata_bridge_passthru_is_input_mapped
        self.assertEqual(self.run_verifier(bridge), 0)
        bridge.keypath_kanata_bridge_create_runtime.assert_not_called()

    def test_passthru_requires_config_instead_of_silently_skipping_creation(self):
        self.assertEqual(self.run_verifier(bridge_fixture(), "--passthru"), 2)

    def test_missing_input_map_rejects_before_creating_any_runtime(self):
        bridge = bridge_fixture()
        del bridge.keypath_kanata_bridge_passthru_is_input_mapped
        self.assertEqual(self.run_verifier(bridge, "config.kbd", "--passthru"), 1)
        bridge.keypath_kanata_bridge_create_runtime.assert_not_called()

    def test_invalid_config_and_null_runtimes_refuse_packaging(self):
        for function in ("validate_config", "create_runtime", "create_passthru_runtime"):
            with self.subTest(function=function):
                bridge = bridge_fixture()
                getattr(bridge, "keypath_kanata_bridge_" + function).return_value = 0
                self.assertEqual(self.run_verifier(bridge, "config.kbd", "--passthru"), 1)

    def test_receive_error_refuses_and_destroys_runtime(self):
        bridge = bridge_fixture()
        bridge.keypath_kanata_bridge_passthru_try_recv_output.return_value = -1
        self.assertEqual(self.run_verifier(bridge, "config.kbd", "--passthru"), 1)
        bridge.keypath_kanata_bridge_destroy_passthru_runtime.assert_called_once_with(2)

    def test_success_checks_creation_without_starting_threads_or_posting(self):
        bridge = bridge_fixture()
        self.assertEqual(self.run_verifier(bridge, "config.kbd", "--passthru"), 0)
        self.assertEqual(bridge.keypath_kanata_bridge_create_passthru_runtime.call_args.args[1], 0)
        bridge.keypath_kanata_bridge_destroy_passthru_runtime.assert_called_once_with(2)
        bridge.keypath_kanata_bridge_start_passthru_runtime.assert_not_called()
        bridge.keypath_kanata_bridge_passthru_send_input.assert_not_called()


if __name__ == "__main__":
    unittest.main()
