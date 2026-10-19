#!/usr/bin/env python3
"""Throwaway spike: interleave Caps (read via IOHIDManager) with tap-visible keys
(F19, Left Shift) at 4–16 ms spacing and measure timestamp skew and ordering.

usage: timing.py run <dst-hex> <cycles> <out.ndjson>   (needs drive.py env)
       timing.py analyze <out.ndjson>
"""
from __future__ import annotations

import json
import os
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAPS, F19, LSHIFT_BIT = 0x39, 0x6E, 0x02
GAPS = [4, 8, 12, 16]


def build(cycles: int):
    """Returns (events, truth). truth is the ordered list of (key, down)."""
    ev, truth, t = [], [], 0
    for i in range(cycles):
        g = [GAPS[(i + k) % 4] * 1000 for k in range(4)]
        other_is_shift = i % 2 == 1
        if i % 4 < 2:  # caps encloses other: C↓ O↓ C↑ O↑
            seq = [("caps", 1), ("other", 1), ("caps", 0), ("other", 0)]
        else:          # other encloses caps: O↓ C↓ O↑ C↑
            seq = [("other", 1), ("caps", 1), ("other", 0), ("caps", 0)]
        held = {"caps": False, "other": False}
        for k, (key, down) in enumerate(seq):
            held[key] = bool(down)
            keys = [CAPS] if held["caps"] else []
            mods = 0
            if held["other"]:
                if other_is_shift: mods = LSHIFT_BIT
                else: keys.append(F19)
            ev.append((t, mods, keys))
            truth.append(("caps" if key == "caps" else ("shift" if other_is_shift else "f19"), down))
            t += g[k]
        t += 20_000
    return ev, truth


def observed(rows):
    hw = []
    for r in rows:
        if r.get("kind") == "hidmgr" and "usage" in r and r.get("device") == "1004a62d4":
            name = {CAPS: "caps", F19: "f19", 0xE1: "shift"}.get(r["usage"])
            if name: hw.append({"src": "hidmgr", "key": name, "down": r["value"], "t": r["t"], "recv": r["recv"]})
        elif r.get("kind") == "tap" and "type" in r and r.get("srcState") == 1:
            if r["keycode"] == 80 and r["type"] in (10, 11):
                hw.append({"src": "tap", "key": "f19", "down": 1 if r["type"] == 10 else 0, "t": r["t"], "recv": r["recv"]})
            elif r["keycode"] == 56 and r["type"] == 12:
                hw.append({"src": "tap", "key": "shift", "down": 1 if int(r["flags"], 16) & 0x20000 else 0,
                           "t": r["t"], "recv": r["recv"]})
            elif r["type"] == 12 and r["keycode"] == 57:
                hw.append({"src": "tap", "key": "CAPS-LEAK", "down": -1, "t": r["t"], "recv": r["recv"]})
    return hw


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))]


def stats(xs):
    if not xs: return "n=0"
    us = [x / 1000 for x in xs]
    return f"n={len(us)} min={min(us):.0f}us p50={pct(us,50):.0f}us p95={pct(us,95):.0f}us p99={pct(us,99):.0f}us max={max(us):.0f}us"


def analyze(path):
    rows = [json.loads(l) for l in open(path)]
    meta = next(r for r in rows if r.get("kind") == "meta")
    truth = [tuple(x) for x in meta["truth"]]
    hw = observed(rows)
    leaks = [h for h in hw if h["key"] == "CAPS-LEAK"]
    # Build the merged stream that a product would see: caps from hidmgr, others from tap.
    product = [h for h in hw if (h["key"] == "caps" and h["src"] == "hidmgr") or (h["key"] != "caps" and h["src"] == "tap")]
    print(f"truth transitions={len(truth)} product-stream events={len(product)} caps-leaks-to-tap={len(leaks)}")
    for order in ("recv", "t"):
        seq = [(h["key"], h["down"]) for h in sorted(product, key=lambda h: h[order])]
        mismatches = sum(1 for a, b in zip(seq, truth) if a != b)
        print(f"  order by {order:4}: exact={seq == truth} mismatched positions={mismatches}")
    # Same-report skew for tap-visible keys: hidmgr.t vs tap.t, paired in order.
    for key in ("f19", "shift"):
        hm = [h for h in hw if h["src"] == "hidmgr" and h["key"] == key]
        tp = [h for h in hw if h["src"] == "tap" and h["key"] == key]
        if len(hm) == len(tp):
            print(f"  {key}: tap.t - hidmgr.t  {stats([b['t'] - a['t'] for a, b in zip(hm, tp)])}")
            print(f"  {key}: tap.recv - hidmgr.recv {stats([b['recv'] - a['recv'] for a, b in zip(hm, tp)])}")
        else:
            print(f"  {key}: unpaired hidmgr={len(hm)} tap={len(tp)}")
    for src in ("hidmgr", "tap"):
        print(f"  {src} delivery latency (recv - t): {stats([h['recv'] - h['t'] for h in hw if h['src'] == src])}")
    # Worst case for a merger: how late can a caps event arrive after a tap event
    # that physically followed it? (positive = caps arrived after the later key)
    caps = [h for h in product if h["key"] == "caps"]
    others = [h for h in product if h["key"] != "caps"]
    late = []
    for c in caps:
        nxt = next((o for o in others if o["t"] > c["t"]), None)
        if nxt: late.append(c["recv"] - nxt["recv"])
    inversions = sum(1 for x in late if x > 0)
    print(f"  caps arrives after the next tap event: {inversions}/{len(late)}; caps.recv - next.recv {stats(late)}")


def run(dst: str, cycles: int, out: str):
    events, truth = build(cycles)
    seconds = events[-1][0] / 1e6 + 4
    proc = subprocess.run([sys.executable, os.path.join(HERE, "drive.py"), "raw", dst, json.dumps(events), str(seconds)],
                          check=True, capture_output=True, text=True)
    with open(out, "w") as f:
        f.write(json.dumps({"kind": "meta", "dst": dst, "cycles": cycles, "truth": truth}) + "\n")
        f.write(proc.stdout)
    sys.stderr.write(proc.stderr)


def sequencer(path):
    """Offline model of a merger that orders Caps against tap events using the
    IOHIDManager copies of every key as the clock: a Caps event is released once
    each tap-visible key with an earlier HID timestamp has arrived via the tap."""
    rows = [json.loads(l) for l in open(path)]
    meta = next(r for r in rows if r.get("kind") == "meta")
    truth = [tuple(x) for x in meta["truth"]]
    hw = observed(rows)
    hm = [h for h in hw if h["src"] == "hidmgr"]
    print("  order of hidmgr copies by HID t == truth:", [(h["key"], h["down"]) for h in sorted(hm, key=lambda h: h["t"])] == truth)
    taps = {k: [h for h in hw if h["src"] == "tap" and h["key"] == k] for k in ("f19", "shift")}
    hms = {k: [h for h in hm if h["key"] == k] for k in ("f19", "shift")}
    pairs = []  # (hid_t, tap_recv) for tap-visible keys
    for k in taps:
        pairs += [(a["t"], b["recv"]) for a, b in zip(hms[k], taps[k])]
    delays, out = [], []
    for c in (h for h in hm if h["key"] == "caps"):
        gate = max([r for t, r in pairs if t < c["t"]] or [0])
        release = max(c["recv"], gate + 1)
        delays.append(release - c["recv"])
        out.append((release, ("caps", c["down"])))
    for k in taps:
        out += [(b["recv"], (k, b["down"])) for b in taps[k]]
    merged = [e for _, e in sorted(out)]
    print(f"  sequenced merge == truth: {merged == truth}; caps hold-back {stats(delays)}")


if __name__ == "__main__":
    if sys.argv[1] == "run": run(sys.argv[2], int(sys.argv[3]), sys.argv[4])
    elif sys.argv[1] == "sequence": sequencer(sys.argv[2])
    else: analyze(sys.argv[2])
