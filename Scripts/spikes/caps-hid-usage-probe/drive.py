#!/usr/bin/env python3
"""Throwaway spike driver: map Caps on the USB HID fixture only, fire real
reports from it, and record what the HID event system, IOHIDManager and a
CGEventTap each see. Restores the fixture's original UserKeyMapping on exit.

Env: KEYPATH_FIXTURE_TOKEN, FIXTURE_HOST/PORT (tunnel), PROBE (binary path).
"""
from __future__ import annotations

import importlib.machinery
import json
import os
import re
import subprocess
import sys
import time
import zlib

FIXTURE_MATCH = '{"VendorID":0xcafe,"ProductID":0x4010}'
CAPS = 0x7_0000_0039
client_path = os.path.expanduser("~/local-code/keypath-pico-hid-fixture/Scripts/lab/pico-hid-fixture-client")
import importlib.util
_loader = importlib.machinery.SourceFileLoader("fixture_client", client_path)
_spec = importlib.util.spec_from_loader("fixture_client", _loader)
fixture = importlib.util.module_from_spec(_spec)
_loader.exec_module(fixture)
client = fixture.FixtureClient(os.environ.get("FIXTURE_HOST", "127.0.0.1"), os.environ["KEYPATH_FIXTURE_TOKEN"],
                               int(os.environ.get("FIXTURE_PORT", "18080")), 15.0)
PROBE = os.environ["PROBE"]


def hidutil(*args: str) -> str:
    return subprocess.run(["hidutil", "property", "--matching", FIXTURE_MATCH, *args],
                          check=True, capture_output=True, text=True).stdout


def get_mapping() -> list[dict[str, int]]:
    out = hidutil("--get", "UserKeyMapping")
    rows = re.findall(r"Dst = (\d+);\s*HIDKeyboardModifierMappingSrc = (\d+);", out)
    return [{"HIDKeyboardModifierMappingSrc": int(s), "HIDKeyboardModifierMappingDst": int(d)} for d, s in rows]


def set_mapping(rows: list[dict[str, int]]) -> None:
    hidutil("--set", json.dumps({"UserKeyMapping": rows}))


def script(run_id: str, events: list[tuple[int, int, list[int]]], cycle_gap_us: int = 200_000) -> str:
    lines = []
    for at_us, mods, keys in events:
        keys = (keys + [0] * 6)[:6]
        lines.append(f"{at_us} {mods} " + " ".join(str(k) for k in keys))
    payload = "\n".join(lines) + "\n"
    crc = zlib.crc32(payload.encode()) & 0xFFFFFFFF
    cycle = events[-1][0] + cycle_gap_us
    return f"KPHID1 {run_id} {len(lines)} 1 {cycle} {crc:08x}\n{payload}"


def fire(run_id: str, events, probe_seconds: float, sender: str | None = "1004a62dc") -> list[dict]:
    state = client.status().get("state")
    if state in ("armed", "running", "typing"):
        raise SystemExit(f"fixture busy: {state}")
    args = [PROBE, "--seconds", str(probe_seconds)]
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, text=True)
    # wait for ready
    rows = []
    for line in proc.stdout:
        rows.append(json.loads(line))
        if rows[-1].get("kind") == "ready":
            break
    client.load_script(script(run_id, events))
    client.arm(run_id)
    client.start(run_id, 300)
    for line in proc.stdout:
        rows.append(json.loads(line))
    proc.wait()
    if sender:
        rows = [r for r in rows if r.get("kind") != "evsys" or "sender" not in r or r["sender"] == sender]
    return rows


def caps_taps(count=3, hold_ms=120, gap_ms=300):
    ev, t = [], 0
    for _ in range(count):
        ev.append((t, 0, [0x39])); ev.append((t + hold_ms * 1000, 0, []))
        t += (hold_ms + gap_ms) * 1000
    return ev


def summarize(rows):
    out = {"evsys": [], "hidmgr": [], "tap": [], "other": []}
    for r in rows:
        k = r.get("kind")
        if k == "evsys" and "usage" in r:
            out["evsys"].append((hex(r["page"]), hex(r["usage"]), r["down"], r["sender"]))
        elif k == "hidmgr" and "usage" in r:
            out["hidmgr"].append((hex(r["usage"]), r["value"], r["device"]))
        elif k == "tap" and "type" in r:
            out["tap"].append((r["type"], r["keycode"], r["flags"]))
        elif k in ("secureInput",) or (k == "tap" and "disabled" in r):
            out["other"].append(r)
    return out


if __name__ == "__main__":
    mode = sys.argv[1]
    original = get_mapping()
    print("original fixture mapping:", original, file=sys.stderr)
    try:
        if mode == "candidates":
            candidates = [int(c, 16) for c in sys.argv[2:]]
            results = {}
            for dst in candidates:
                set_mapping([{"HIDKeyboardModifierMappingSrc": CAPS, "HIDKeyboardModifierMappingDst": dst}])
                applied = get_mapping()
                time.sleep(0.3)
                rows = fire(f"caps-{dst:x}", caps_taps(), 3.0)
                s = summarize(rows)
                results[hex(dst)] = {"applied": applied, **s}
                print(json.dumps({hex(dst): results[hex(dst)]}), flush=True)
                with open(os.environ.get("RAW", "/dev/null"), "a") as f:
                    for r in rows:
                        f.write(json.dumps({"candidate": hex(dst), **r}) + "\n")
        elif mode == "raw":
            dst = int(sys.argv[2], 16)
            set_mapping([{"HIDKeyboardModifierMappingSrc": CAPS, "HIDKeyboardModifierMappingDst": dst}])
            events = json.loads(sys.argv[3])
            seconds = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
            for r in fire(f"raw-{int(time.time())}", [tuple(e) for e in events], seconds):
                print(json.dumps(r))
    finally:
        set_mapping(original)
        print("restored fixture mapping:", get_mapping(), file=sys.stderr)
