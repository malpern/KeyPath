#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile


PROBE = pathlib.Path(__file__).resolve().parents[1] / "probe-kanata-tcp"


def probe(stdout: str, exit_code: int = 0, sleep: float = 0):
    with tempfile.TemporaryDirectory() as directory:
        cli = pathlib.Path(directory) / "keypath-cli"
        cli.write_text(
            "#!/bin/bash\n"
            '[[ "$*" == "layer current --json" ]] || exit 64\n'
            f"sleep {sleep}\n"
            f"cat <<'OUT'\n{stdout}\nOUT\n"
            f"exit {exit_code}\n"
        )
        cli.chmod(0o755)
        return subprocess.run([str(PROBE), "--cli", str(cli), "--timeout", "1"],
                              text=True, capture_output=True, check=False)


answer = '{\n  "apiVersion" : 1,\n  "data" : {\n    "layer" : "base"\n  }\n}'
valid = probe(answer)
assert valid.returncode == 0, valid.stderr
assert json.loads(valid.stdout)["CurrentLayerName"]["name"] == "base"

# Log lines before the JSON, as the CLI prints them.
logged = probe("[2026-11-10 20:45:06.437] [INFO] {not json} started\n" + answer)
assert logged.returncode == 0, logged.stderr
assert json.loads(logged.stdout)["CurrentLayerName"]["name"] == "base"

missing = probe('{"apiVersion":1,"data":{}}')
assert missing.returncode != 0 and "layer response missing" in missing.stderr

unreachable = probe('{"apiVersion":1,"error":"unreachable"}', exit_code=3)
assert unreachable.returncode != 0 and "exited 3" in unreachable.stderr

slow = probe(answer, sleep=3)
assert slow.returncode != 0 and "timed out" in slow.stderr

print("probe-kanata-tcp-tests: passed")
