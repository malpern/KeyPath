#!/usr/bin/env python3
import argparse
import hashlib
import http.server
import json
import os
import pathlib
import subprocess
import threading
import time


def watch_completion(state_path: pathlib.Path, celebration_url: str) -> None:
    marker = pathlib.Path("/tmp") / (
        "keypath-progress-celebrated-" + hashlib.sha256(str(state_path).encode()).hexdigest()[:12]
    )
    while True:
        try:
            state = json.loads(state_path.read_text())
            if state.get("complete") is True and not marker.exists():
                subprocess.run(["/usr/bin/open", celebration_url], check=False)
                marker.write_text(str(time.time()))
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the live KeyPath automation dashboard")
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--state", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--celebration-url",
        default=os.environ.get(
            "KEYPATH_PROGRESS_CELEBRATION_URL",
            "raycast://extensions/raycast/raycast/confetti",
        ),
    )
    args = parser.parse_args()
    root = args.root.resolve()
    state = args.state.resolve()
    threading.Thread(
        target=watch_completion, args=(state, args.celebration_url), daemon=True
    ).start()
    handler = lambda *handler_args, **handler_kwargs: http.server.SimpleHTTPRequestHandler(
        *handler_args, directory=str(root), **handler_kwargs
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"KeyPath progress dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-test-automation-progress.html")
    server.serve_forever()


if __name__ == "__main__":
    main()
