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
from urllib.parse import urlparse


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


def refresh_issues(command: pathlib.Path, state_path: pathlib.Path) -> None:
    while True:
        subprocess.run([str(command), "--output", str(state_path)], check=False)
        time.sleep(60)


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(
        self,
        *args,
        directory: str,
        automation_state: pathlib.Path,
        issue_state: pathlib.Path,
        **kwargs,
    ) -> None:
        self.automation_state = automation_state
        self.issue_state = issue_state
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        states = {
            "/docs/testing/keypath-test-automation-state.json": self.automation_state,
            "/docs/testing/keypath-github-issues-state.json": self.issue_state,
        }
        state = states.get(path)
        if state is None:
            super().do_GET()
            return
        try:
            body = state.read_bytes()
        except OSError:
            self.send_error(404, "Dashboard state unavailable")
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the live KeyPath automation dashboard")
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--state", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--issue-state",
        type=pathlib.Path,
        default=pathlib.Path("/tmp/keypath-github-issues-state.json"),
    )
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
    issue_state = args.issue_state.resolve()
    issue_refresh = root / "Scripts/lab/update-issue-dashboard"
    threading.Thread(
        target=watch_completion, args=(state, args.celebration_url), daemon=True
    ).start()
    threading.Thread(
        target=refresh_issues, args=(issue_refresh, issue_state), daemon=True
    ).start()
    handler = lambda *handler_args, **handler_kwargs: DashboardHandler(
        *handler_args,
        directory=str(root),
        automation_state=state,
        issue_state=issue_state,
        **handler_kwargs,
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"KeyPath progress dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-test-automation-progress.html")
    print(f"KeyPath issue dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-github-issues-dashboard.html")
    server.serve_forever()


if __name__ == "__main__":
    main()
