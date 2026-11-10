"""Score keyboard attribution per press against ground truth (no key text, codes only).

Usage: python3 -I score.py run.csv KEYCODE

Ground truth: macOS merges the two keyboards' presses of one key. We rebuild the
tap stream macOS should have produced from the HID stream under two merge
hypotheses, keep the one that matches the observed tap events, and take each
expected tap event's source keyboard as the truth. Then the ADR-048 matcher rules
(30 ms behind / 5 ms ahead, closest candidate consumed, two keyboards -> fallback,
release follows press) run over the real tap events, by both clocks, and are scored.
"""
import csv, sys
from collections import Counter

path, key = sys.argv[1], int(sys.argv[2])
hid, tap = [], []
names = {}
for r in csv.DictReader(open(path)):
    if int(r["keycode"]) != key:
        continue
    d = r["down"] == "true"
    if r["source"] == "hid":
        names[r["device"]] = r["name"]
        hid.append(dict(dev=r["device"], down=d, ev=int(r["event"]), rx=int(r["received"])))
    else:
        tap.append(dict(down=d, rep=r["autorepeat"] == "true", ev=int(r["event"]), rx=int(r["received"])))
hid.sort(key=lambda h: h["ev"]); tap.sort(key=lambda t: t["ev"])
raw = [t for t in tap if not t["rep"]]
# KeyPath's session runtime re-posts each key a few ms later, so the tap sees it twice.
# One stream cannot have two downs (or ups) in a row, so keep the first of each run.
fresh = [t for i, t in enumerate(raw) if i == 0 or raw[i - 1]["down"] != t["down"]]
print(f"key {key}: HID {len(hid)} ({Counter(names[h['dev']] for h in hid)}), tap fresh {len(raw)} -> {len(fresh)} after dropping re-posts, repeats {len(tap)-len(raw)}")

def expected(hyp):
    held, out, owner = set(), [], None
    for h in hid:
        if h["down"]:
            if not held:
                out.append(dict(down=True, dev=h["dev"], ev=h["ev"])); owner = h["dev"]
            held.add(h["dev"])
        else:
            was = bool(held); held.discard(h["dev"])
            if hyp == "union" and was and not held:
                out.append(dict(down=False, dev=h["dev"], ev=h["ev"]))
            if hyp == "any-release" and was:
                out.append(dict(down=False, dev=h["dev"], ev=h["ev"])); held.clear()
    return out

def align(exp, window=30_000_000):
    """Pair each real fresh tap event with the nearest expected event of the same direction."""
    used, truth, misses = set(), [], 0
    j0 = 0
    for t in fresh:
        best = None
        for j in range(j0, len(exp)):
            e = exp[j]
            if e["ev"] > t["ev"] + 10_000_000: break
            if j in used or e["down"] != t["down"] or t["ev"] - e["ev"] > window: continue
            if best is None or abs(t["ev"] - e["ev"]) < abs(t["ev"] - exp[best]["ev"]): best = j
        if best is None: misses += 1; truth.append(None)
        else: used.add(best); truth.append(exp[best]["dev"])
        while j0 < len(exp) and exp[j0]["ev"] < t["ev"] - window: j0 += 1
    return truth, misses, len(exp) - len(used)

best = None
for hyp in ("union", "any-release"):
    exp = expected(hyp)
    truth, miss, extra = align(exp)
    print(f"merge hypothesis {hyp}: expected {len(exp)} fresh tap events, unmatched real {miss}, unmatched expected {extra}")
    if best is None or miss + extra < best[1]: best = (hyp, miss + extra, truth)
hyp, _, truth = best
print(f"using {hyp}")

def matcher(clock, behind=30_000_000, ahead=5_000_000):
    pool = [dict(h) for h in hid]
    alive = [True] * len(pool)
    credit, out = None, []
    for t in fresh:
        tt = t[clock]
        cands = [i for i, h in enumerate(pool) if alive[i] and h["down"] == t["down"] and tt - behind <= h[clock] <= tt + ahead]
        closest = min(cands, key=lambda i: abs(pool[i][clock] - tt)) if cands else None
        if closest is not None: alive[closest] = False
        if t["down"]:
            devs = {pool[i]["dev"] for i in cands}
            credit = next(iter(devs)) if len(devs) == 1 else None
            out.append((credit, "match" if len(devs) == 1 else ("ambiguous" if devs else "none")))
        else:
            out.append((credit, "release"))
            # clear stale presses before the paired HID release
            limit = pool[closest][clock] if closest is not None else tt
            for i, h in enumerate(pool):
                if alive[i] and h["down"] and h[clock] < limit and (closest is not None or credit is None or h["dev"] == credit):
                    alive[i] = False
            credit = None
    return out

def gap(t):
    """Distance from this tap press to the nearest HID press of the same key on each keyboard."""
    near = {}
    for h in hid:
        if h["down"]:
            d = abs(h["ev"] - t["ev"])
            near[h["dev"]] = min(near.get(h["dev"], 1 << 62), d)
    return near

for clock in ("ev", "rx"):
    res = matcher(clock)
    c = Counter()
    bins = Counter(); binwrong = Counter()
    for t, tr, (cr, kind) in zip(fresh, truth, res):
        if tr is None: c["no truth"] += 1; continue
        side = "press" if t["down"] else "release"
        if cr is None: c[f"{side} fallback ({kind})"] += 1; verdict = "fallback"
        elif cr == tr: c[f"{side} correct"] += 1; verdict = "ok"
        elif side == "release": c["release credited to its press, other keyboard released it"] += 1; verdict = "ok"
        else: c["press WRONG"] += 1; verdict = "wrong"
        if t["down"]:
            near = gap(t); others = [v for d, v in near.items() if d != tr]
            g = min(others) // 1_000_000 if others else 999
            b = "<5ms" if g < 5 else "5-15ms" if g < 15 else "15-30ms" if g < 30 else ">=30ms"
            bins[b] += 1
            if verdict != "ok": binwrong[(b, verdict)] += 1
    print(f"\n[{'event timestamps' if clock=='ev' else 'callback arrival'}, 30/5 ms] {dict(c)}")
    for b in ("<5ms", "5-15ms", "15-30ms", ">=30ms"):
        print(f"  presses with other keyboard's press {b} away: {bins[b]}, fallback {binwrong[(b,'fallback')]}, wrong {binwrong[(b,'wrong')]}")
    truthc = Counter(names[tr] for tr in truth if tr)
    print("  truth by keyboard:", dict(truthc))
