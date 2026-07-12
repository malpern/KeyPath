#!/usr/bin/env python3
import json
import pathlib
import socket
import subprocess
import threading
import time
from typing import Optional


PROBE = pathlib.Path(__file__).resolve().parents[1] / "probe-kanata-tcp"


def run_server(response: Optional[bytes]):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]

    def serve():
        with listener:
            connection, _ = listener.accept()
            with connection:
                request = connection.makefile("rb").readline()
                parsed = json.loads(request)
                assert "RequestCurrentLayerName" in parsed
                if response is None:
                    time.sleep(0.3)
                else:
                    connection.sendall(response + b"\n")

    thread = threading.Thread(target=serve)
    thread.start()
    return port, thread


def probe(response: Optional[bytes]):
    port, thread = run_server(response)
    result = subprocess.run(
        [str(PROBE), "--port", str(port), "--timeout", "0.1"],
        text=True,
        capture_output=True,
        check=False,
    )
    thread.join()
    return result


valid = probe(b'{"CurrentLayerName":{"name":"base","request_id":"keypath-lab-readiness"}}')
assert valid.returncode == 0, valid.stderr
assert json.loads(valid.stdout)["CurrentLayerName"]["name"] == "base"

deployed = probe(b'{"LayerChange":{"new":"base"}}')
assert deployed.returncode == 0, deployed.stderr
assert json.loads(deployed.stdout)["LayerChange"]["new"] == "base"

invalid = probe(b'{"HelloOk":{"protocol_version":1}}')
assert invalid.returncode != 0
assert "layer response missing" in invalid.stderr

silent = probe(None)
assert silent.returncode != 0
assert "timed out" in silent.stderr

print("probe-kanata-tcp-tests: passed")
