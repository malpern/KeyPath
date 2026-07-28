#!/usr/bin/env python3

import importlib.util
import importlib.machinery
import hashlib
import hmac
import json
import pathlib
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = pathlib.Path(__file__).resolve().parents[3]
CLIENT_PATH = ROOT / "Scripts/lab/pico-hid-fixture-client"
LOADER = importlib.machinery.SourceFileLoader("pico_hid_fixture_client", str(CLIENT_PATH))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC and SPEC.loader
CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENT)


class RecordingHandler(BaseHTTPRequestHandler):
    requests = []
    received_headers = []
    reported_build = "old-build"
    reported_slot = "ota_0"

    def log_message(self, _format, *_arguments):
        pass

    def _handle(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.__class__.requests.append((self.command, self.path, self.headers.get("Authorization"), body))
        self.__class__.received_headers.append({name.lower(): value for name, value in self.headers.items()})
        if self.path == "/v1/status":
            payload = {"ok": True, "state": "idle", "build": self.__class__.reported_build,
                       "wifiConnected": True, "updateReady": True,
                       "displayHealthy": True, "splashComplete": True,
                       "otaSlot": self.__class__.reported_slot, "otaState": "valid"}
        elif self.path == "/v1/firmware":
            self.__class__.reported_build = self.headers["X-KeyPath-Expected-Build"]
            self.__class__.reported_slot = "ota_1" if self.__class__.reported_slot == "ota_0" else "ota_0"
            payload = {"ok": True, "rebooting": True, "targetSlot": self.__class__.reported_slot}
        elif self.path.startswith("/v1/trace"):
            encoded = b'{"runId":"r","from":0,"available":1}\n{"sequence":1}\n'
            self.send_response(200)
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return
        else:
            payload = {"ok": True}
        encoded = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    do_GET = _handle
    do_POST = _handle


class ClientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        RecordingHandler.requests = []
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), RecordingHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.thread.join()

    def setUp(self):
        RecordingHandler.requests.clear()
        RecordingHandler.received_headers.clear()
        RecordingHandler.reported_build = "old-build"
        RecordingHandler.reported_slot = "ota_0"
        self.client = CLIENT.FixtureClient("127.0.0.1", "test-token", self.server.server_port)

    def test_compile_text_emits_complete_reports_and_crc(self):
        script = CLIENT.compile_text("run-1", "aA 1!\n", 80, 30, 2, 500)
        header, payload = script.split("\n", 1)
        fields = header.split()
        self.assertEqual(fields[:5], ["KPHID1", "run-1", "12", "2", "980000"])
        self.assertEqual(int(fields[5], 16), CLIENT.zlib.crc32(payload.encode("ascii")) & 0xFFFFFFFF)
        lines = payload.splitlines()
        self.assertEqual(lines[0], "0 0 4 0 0 0 0 0")
        self.assertEqual(lines[2], "80000 2 4 0 0 0 0 0")
        self.assertEqual(lines[-1].split()[1:], ["0", "0", "0", "0", "0", "0", "0"])

    def test_compile_rejects_unsupported_text_and_unsafe_timing(self):
        with self.assertRaisesRegex(ValueError, "unsupported"):
            CLIENT.compile_text("run", "🙂", 80, 30, 1, 0)
        with self.assertRaisesRegex(ValueError, "at least 4 ms"):
            CLIENT.compile_text("run", "a", 3, 2, 1, 0)
        with self.assertRaisesRegex(ValueError, "hold duration"):
            CLIENT.compile_text("run", "a", 20, 20, 1, 0)
        with self.assertRaisesRegex(ValueError, "timeout"):
            CLIENT.FixtureClient("fixture", "token", timeout=0)

    def test_compile_text_can_separate_shift_press_and_release(self):
        script = CLIENT.compile_text("shift-order", "A!", 50, 8, 1, 100, 4, 6)
        header, payload = script.split("\n", 1)
        fields = header.split()
        self.assertEqual(fields[:5], ["KPHID1", "shift-order", "8", "1", "200000"])
        self.assertEqual(payload.splitlines(), [
            "0 2 0 0 0 0 0 0",
            "4000 2 4 0 0 0 0 0",
            "12000 2 0 0 0 0 0 0",
            "18000 0 0 0 0 0 0 0",
            "50000 2 0 0 0 0 0 0",
            "54000 2 30 0 0 0 0 0",
            "62000 2 0 0 0 0 0 0",
            "68000 0 0 0 0 0 0 0",
        ])
        with self.assertRaisesRegex(ValueError, "fit inside"):
            CLIENT.compile_text("shift-order", "A", 20, 10, 1, 0, 5, 5)

    def test_client_authenticates_and_uses_expected_endpoints(self):
        self.assertEqual(self.client.status()["state"], "idle")
        self.client.arm("run-2")
        self.client.start("run-2", 2000)
        self.client.abort()
        paths = [(method, path) for method, path, _auth, _body in RecordingHandler.requests]
        self.assertEqual(paths, [("GET", "/v1/status"), ("POST", "/v1/arm"),
                                 ("POST", "/v1/start"), ("POST", "/v1/abort")])
        self.assertTrue(all(auth == "Bearer test-token" for _method, _path, auth, _body in RecordingHandler.requests))

    def test_trace_decodes_ndjson(self):
        trace = self.client.trace(0, 8)
        self.assertEqual(trace[0]["available"], 1)
        self.assertEqual(trace[1]["sequence"], 1)

    def test_presentation_uses_bounded_json_channel(self):
        self.client.present({"phase": "result", "result": "pass", "progress": 1000,
                             "title": "Swift stress", "reportsExpected": 40,
                             "reportsObserved": 40, "safeRelease": True})
        method, path, auth, body = RecordingHandler.requests[-1]
        self.assertEqual((method, path, auth), ("POST", "/v1/presentation", "Bearer test-token"))
        payload = json.loads(body)
        self.assertEqual(payload["result"], "pass")
        self.assertEqual(payload["reportsObserved"], 40)

    def test_firmware_update_authenticates_image_and_verifies_reconnected_build(self):
        firmware = b"esp32-application-image"
        result = self.client.update_firmware(firmware, "a1b2c3d4", wait_seconds=2)

        method, path, auth, body = RecordingHandler.requests[1]
        headers = RecordingHandler.received_headers[1]
        self.assertEqual((method, path, auth, body),
                         ("POST", "/v1/firmware", "Bearer test-token", firmware))
        self.assertEqual(headers["x-keypath-sha256"], hashlib.sha256(firmware).hexdigest())
        self.assertEqual(headers["x-keypath-hmac-sha256"],
                         hmac.new(b"test-token", firmware, hashlib.sha256).hexdigest())
        self.assertEqual(headers["x-keypath-expected-build"], "a1b2c3d4")
        self.assertEqual(result["verifiedBuild"], "a1b2c3d4")
        self.assertEqual(result["previousSlot"], "ota_0")
        self.assertEqual(result["verifiedSlot"], "ota_1")
        self.assertEqual(result["status"]["otaSlot"], "ota_1")

    def test_firmware_update_rejects_empty_images_and_ambiguous_builds(self):
        with self.assertRaisesRegex(ValueError, "empty"):
            self.client.update_firmware(b"", "a1")
        with self.assertRaisesRegex(ValueError, "expected build"):
            self.client.update_firmware(b"image", "not-a-build")


if __name__ == "__main__":
    unittest.main()
