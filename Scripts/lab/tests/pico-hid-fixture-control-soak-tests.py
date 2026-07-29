#!/usr/bin/env python3

import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOAK = ROOT / "lab/pico-hid-fixture-control-soak"


class StatusHandler(http.server.BaseHTTPRequestHandler):
    count = 0

    def do_GET(self):
        if self.path != "/v1/status" or self.headers.get("Authorization") != "Bearer test-token":
            self.send_error(403)
            return
        type(self).count += 1
        body = json.dumps({
            "ok": True,
            "build": "abc123",
            "diagnostics": {"uptimeMs": 10_000 + type(self).count, "statusRequests": type(self).count},
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


class ControlSoakTests(unittest.TestCase):
    def test_records_latency_and_continuity_without_exposing_token(self):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), StatusHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory) / "soak.json"
                result = subprocess.run([
                    str(SOAK), "--host", "127.0.0.1", "--port", str(server.server_port),
                    "--requests", "5", "--interval-ms", "0", "--output", str(output),
                ], text=True, capture_output=True,
                    env=os.environ | {"KEYPATH_FIXTURE_TOKEN": "test-token"})
                self.assertEqual(result.returncode, 0, result.stderr)
                artifact = json.loads(output.read_text())
                self.assertEqual(artifact["status"], "pass")
                self.assertEqual(artifact["requests"]["succeeded"], 5)
                self.assertFalse(artifact["continuity"]["resetObserved"])
                self.assertEqual(artifact["target"]["resolvedHost"], "127.0.0.1")
                self.assertIsNotNone(artifact["latencyMs"]["p95"])
                self.assertNotIn("test-token", result.stdout + result.stderr + output.read_text())
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
