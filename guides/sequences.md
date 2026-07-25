---
layout: default
title: "Type Memorable Shortcut Paths"
description: "Create short key sequences for actions you can remember, then tune how long KeyPath waits between keys"
theme: parchment
header_image: header-leader-key.png
permalink: /guides/sequences/
---


# Type Memorable Shortcut Paths

Shortcut combinations are easy to exhaust and hard to remember. Sequences let
you type a short path instead: `Leader → W → L` for window left, or
`Leader → S → M` for Messages. Each key narrows the path until the action is
unambiguous.

---

## Create a Sequence

1. Open KeyPath and click the gear icon.
2. Go to the **Rules** tab.
3. Find **Sequences** and turn it on.
4. Click **Customize…**.
5. Add a sequence, choose its keys in order, and select the layer it activates.
6. Click **Save**.

Screenshot — the timing control in the Sequences editor:

```
┌─ Sequences ────────────────────────────────────────────┐
│ Key Sequence     Leader  →  W  →  L                   │
│ Action           Activate Window                      │
│                                                        │
│ Sequence pause limit                    500 ms          │
│ ├──────────────●──────────────────────────────┤         │
│ The timer restarts after each matching key.            │
└────────────────────────────────────────────────────────┘
```

---

## Tune the Pause Between Keys

**Sequence pause limit** is the longest pause allowed after the most recent
matching key. The timer restarts every time you enter the next correct key.

```
Leader pressed
    │
    ├── W pressed after 300 ms  → timer restarts
    │
    ├── L pressed after 400 ms  → sequence completes
    │
    └── pause longer than the limit → incomplete sequence clears
```

A larger value gives you more time between keys, which is helpful while
learning. It also leaves an incomplete sequence pending longer. A smaller value
clears mistakes sooner but requires a tighter rhythm.

Start with **500 ms**. Increase it if sequences clear before you finish; reduce
it if an incomplete sequence feels slow to get out of the way. KeyPath supports
values from **300 to 2000 ms**.

---

## What Happens When a Sequence Fails?

KeyPath clears the pending path when you pause longer than the Sequence pause
limit or press a key that cannot complete any configured sequence. Start the
path again from your Leader key.

If two sequences overlap—such as `Leader → W` and `Leader → W → L`—the editor
warns you because the shorter path can make the longer one ambiguous.

---

## Tips

- Use two or three keys after Leader; short paths become muscle memory quickly.
- Choose mnemonic letters, such as `W → L` for “window left.”
- Keep related actions under the same first key.
- Raise the pause limit temporarily while learning, then tighten it later.

---

## Next Steps

- **[Choose Your Leader Key]({{ '/guides/leader-key/' | relative_url }})** — Pick the key that starts your shortcut paths
- **[Press Two Keys at Once]({{ '/guides/chords/' | relative_url }})** — Use simultaneous keys instead of an ordered path
- **[What You Can Build]({{ '/guides/use-cases/' | relative_url }})** — See sequences in a complete keyboard workflow
- **[Back to Docs](https://malpern.github.io/KeyPath/docs)**

## External resources

- **[Kanata sequence documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#sequences)** — Engine-level details for advanced configurations ↗
