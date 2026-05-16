# `header-leader-key.png` — generation prompt

Source-of-truth prompt for generating `header-leader-key.png`.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect)

## Prompt (v1)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: A wide horizontal band showing four keycaps in a row — Space bar, Caps Lock, Tab, and Backtick — each rendered as vintage typewriter keys with watercolor halos. The Space bar is slightly larger and centered, with a small crown or star above it suggesting "default choice." Thin ink lines radiate from each key outward, suggesting they connect to many other functions.

Above the keys, hand-lettered in elegant black ink cursive: "Leader Key" — positioned at the vertical center band.

A small decorative compass rose beneath the keys suggesting "this key points everywhere."

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, indigo. No people, no photos.
```
