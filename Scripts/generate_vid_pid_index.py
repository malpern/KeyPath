#!/usr/bin/env python3
"""
Generate qmk-vid-pid-index.json from QMK API data.

Reads the bundled qmk-keyboard-index.json for all keyboard paths,
fetches VID/PID from the QMK API, and outputs the index file.

Usage:
    python3 Scripts/generate_vid_pid_index.py

Rate-limited to ~5 requests/second to be respectful to the QMK API.
Caches responses locally in /tmp/qmk-vid-pid-cache/ to support resuming.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
from collections import defaultdict
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
INDEX_PATH = PROJECT_ROOT / "Sources" / "KeyPathAppKit" / "Resources" / "qmk-keyboard-index.json"
OUTPUT_PATH = PROJECT_ROOT / "Sources" / "KeyPathAppKit" / "Resources" / "qmk-vid-pid-index.json"
CACHE_DIR = Path("/tmp/qmk-vid-pid-cache")
QMK_API_BASE = "https://keyboards.qmk.fm/v1/keyboards"

REQUEST_DELAY = 0.2  # 5 req/s


def load_keyboard_paths():
    """Load all keyboard paths from the bundled index."""
    with open(INDEX_PATH) as f:
        data = json.load(f)
    return data["keyboards"]


def fetch_keyboard_info(path):
    """Fetch info.json for a keyboard path from QMK API, with caching."""
    cache_file = CACHE_DIR / f"{path.replace('/', '__')}.json"

    if cache_file.exists():
        with open(cache_file) as f:
            return json.load(f)

    url = f"{QMK_API_BASE}/{path}/info.json"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "KeyPath/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            with open(cache_file, "w") as f:
                json.dump(data, f)
            return data
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
        print(f"  SKIP {path}: {e}", file=sys.stderr)
        return None


def extract_vid_pid(info):
    """Extract VID and PID from keyboard info.json response."""
    # QMK API wraps in {"keyboards": {"path": {...}}}
    keyboards = info.get("keyboards", info)
    if isinstance(keyboards, dict):
        for _path, kb_info in keyboards.items():
            usb = kb_info.get("usb", {})
            vid = usb.get("vid")
            pid = usb.get("pid")
            if vid and pid:
                return vid, pid
    return None, None


def format_hex(value):
    """Convert QMK hex string (e.g. '0x4653') to uppercase hex without prefix."""
    if isinstance(value, str):
        return value.replace("0x", "").replace("0X", "").upper().zfill(4)
    if isinstance(value, int):
        return f"{value:04X}"
    return None


def main():
    print(f"Loading keyboard paths from {INDEX_PATH}...")
    paths = load_keyboard_paths()
    print(f"Found {len(paths)} keyboard paths")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    # Collect VID:PID -> paths mapping
    vidpid_to_paths = defaultdict(list)
    vid_to_paths = defaultdict(list)

    total = len(paths)
    fetched = 0
    skipped = 0

    for i, path in enumerate(paths):
        if (i + 1) % 100 == 0:
            print(f"  Progress: {i + 1}/{total} (fetched: {fetched}, skipped: {skipped})")

        info = fetch_keyboard_info(path)
        if info is None:
            skipped += 1
            continue

        vid, pid = extract_vid_pid(info)
        if vid is None or pid is None:
            skipped += 1
            continue

        vid_hex = format_hex(vid)
        pid_hex = format_hex(pid)
        if not vid_hex or not pid_hex:
            skipped += 1
            continue

        # Skip 0000:0000
        if vid_hex == "0000" and pid_hex == "0000":
            skipped += 1
            continue

        vidpid_key = f"{vid_hex}:{pid_hex}"
        vidpid_to_paths[vidpid_key].append(path)
        vid_to_paths[vid_hex].append(path)

        fetched += 1
        time.sleep(REQUEST_DELAY)

    print(f"\nDone: {fetched} keyboards with VID:PID, {skipped} skipped")

    # Build output entries: exact VID:PID + VID-only fallback
    entries = {}

    # Add exact VID:PID entries
    for key, paths in sorted(vidpid_to_paths.items()):
        entries[key] = sorted(set(paths))

    # Add VID-only entries (deduplicated)
    for vid, paths in sorted(vid_to_paths.items()):
        unique_paths = sorted(set(paths))
        if len(unique_paths) > 0:
            entries[vid] = unique_paths

    output = {
        "version": "1.0",
        "generated": datetime.utcnow().strftime("%Y-%m-%d"),
        "entries": entries,
    }

    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f, indent=2, sort_keys=False)

    print(f"Wrote {len(entries)} entries to {OUTPUT_PATH}")
    print(f"  VID:PID entries: {len(vidpid_to_paths)}")
    print(f"  VID-only entries: {len(vid_to_paths)}")


if __name__ == "__main__":
    main()
