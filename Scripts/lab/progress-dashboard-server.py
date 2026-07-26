#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import http.server
import json
import os
import pathlib
import tempfile
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


def merge_lab_snapshot(state_path: pathlib.Path, seed_path: pathlib.Path, snapshot: dict) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = state_path.with_suffix(state_path.suffix + ".lock")
    with lock_path.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            state = json.loads(
                state_path.read_text() if state_path.exists() else seed_path.read_text()
            )
        except (OSError, json.JSONDecodeError):
            state = json.loads(seed_path.read_text())
        state["host"] = snapshot.get("host", state.get("host", {}))
        state["leases"] = snapshot.get("leases", [])
        resources = {
            item.get("id"): item
            for item in state.get("resources", [])
            if item.get("id")
        }
        for item in snapshot.get("resources", []):
            resources[item["id"]] = {**resources.get(item["id"], {}), **item}
        state["resources"] = list(resources.values())[-12:]
        state["updatedAt"] = snapshot.get("capturedAt", state.get("updatedAt"))
        fd, temporary = tempfile.mkstemp(prefix=state_path.name + ".", dir=state_path.parent)
        try:
            with os.fdopen(fd, "w") as handle:
                json.dump(state, handle, indent=2)
                handle.write("\n")
            os.replace(temporary, state_path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        fcntl.flock(lock, fcntl.LOCK_UN)


def mark_lab_offline(state_path: pathlib.Path, seed_path: pathlib.Path) -> None:
    merge_lab_snapshot(
        state_path,
        seed_path,
        {
            "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "host": {
                "name": "KeyPath lab mini",
                "connectivity": "offline",
                "console": "unknown",
                "power": "unknown",
                "diskFreeGiB": None,
                "osVersion": None,
                "osBuild": None,
                "keyboard": {"name": "Unknown", "state": "unknown"},
            },
            "leases": [],
            "resources": [],
        },
    )


def refresh_lab(
    command: pathlib.Path,
    host: str,
    state_path: pathlib.Path,
    seed_path: pathlib.Path,
    interval: float,
) -> None:
    while True:
        try:
            result = subprocess.run(
                [str(command), "--host", host, "lab-state"],
                check=False,
                capture_output=True,
                text=True,
                timeout=max(10, interval * 2),
            )
            if result.returncode == 0:
                merge_lab_snapshot(state_path, seed_path, json.loads(result.stdout))
            else:
                mark_lab_offline(state_path, seed_path)
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            mark_lab_offline(state_path, seed_path)
        time.sleep(interval)


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(
        self,
        *args,
        directory: str,
        automation_state: pathlib.Path,
        matrix_state: pathlib.Path,
        issue_state: pathlib.Path,
        lab_state: pathlib.Path,
        **kwargs,
    ) -> None:
        self.automation_state = automation_state
        self.matrix_state = matrix_state
        self.issue_state = issue_state
        self.lab_state = lab_state
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        states = {
            "/docs/testing/keypath-test-automation-state.json": self.automation_state,
            "/docs/testing/keypath-matrix-state.json": self.matrix_state,
            "/docs/testing/keypath-github-issues-state.json": self.issue_state,
            "/docs/testing/keypath-lab-state.json": self.lab_state,
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
        "--matrix-state",
        type=pathlib.Path,
        default=pathlib.Path("/tmp/keypath-matrix-state.json"),
    )
    parser.add_argument(
        "--issue-state",
        type=pathlib.Path,
        default=pathlib.Path("/tmp/keypath-github-issues-state.json"),
    )
    parser.add_argument(
        "--lab-state",
        type=pathlib.Path,
        default=pathlib.Path("/tmp/keypath-lab-state.json"),
    )
    parser.add_argument(
        "--lab-host",
        default=os.environ.get("KEYPATH_LAB_HOST", "clawd@keypath-lab-mini"),
    )
    parser.add_argument("--lab-refresh-seconds", type=float, default=5.0)
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
    matrix_state = args.matrix_state.resolve()
    issue_state = args.issue_state.resolve()
    lab_state = args.lab_state.resolve()
    lab_seed = root / "docs/testing/keypath-lab-state.json"
    matrix_seed = root / "docs/testing/keypath-matrix-state.json"
    if not matrix_state.exists():
        matrix_state.write_bytes(matrix_seed.read_bytes())
    issue_refresh = root / "Scripts/lab/update-issue-dashboard"
    lab_refresh = root / "Scripts/lab/keypath-lab"
    threading.Thread(
        target=watch_completion, args=(state, args.celebration_url), daemon=True
    ).start()
    threading.Thread(
        target=refresh_issues, args=(issue_refresh, issue_state), daemon=True
    ).start()
    threading.Thread(
        target=refresh_lab,
        args=(
            lab_refresh,
            args.lab_host,
            lab_state,
            lab_seed,
            args.lab_refresh_seconds,
        ),
        daemon=True,
    ).start()
    handler = lambda *handler_args, **handler_kwargs: DashboardHandler(
        *handler_args,
        directory=str(root),
        automation_state=state,
        matrix_state=matrix_state,
        issue_state=issue_state,
        lab_state=lab_state,
        **handler_kwargs,
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"KeyPath progress dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-test-automation-progress.html")
    print(f"KeyPath issue dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-github-issues-dashboard.html")
    print(f"KeyPath matrix dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-matrix-dashboard.html")
    print(f"KeyPath lab dashboard: http://127.0.0.1:{args.port}/docs/testing/keypath-lab-state-dashboard.html")
    server.serve_forever()


if __name__ == "__main__":
    main()
