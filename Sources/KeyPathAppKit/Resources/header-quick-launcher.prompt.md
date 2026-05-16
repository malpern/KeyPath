# `header-quick-launcher.png` — generation prompt

Source-of-truth prompt for generating `header-quick-launcher.png`.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect)

## Prompt (v1)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: A wide horizontal band showing a row of 5-6 keycaps at the vertical center, each with a faint app icon watercolored inside — a compass (Safari), a terminal prompt cursor, a folder, a globe. The keycaps are rendered as vintage typewriter keys with watercolor blooms behind each one. Between the keycaps, thin dotted ink arrows radiate outward suggesting "launch" motion.

Above the key row, hand-lettered in elegant black ink cursive: "Quick Launcher" — positioned at the vertical center band.

One keycap in the center is slightly larger/emphasized with a star symbol (✦) representing the Hyper key, with graceful ink lines connecting it to the other keycaps.

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, indigo. No people, no photos.
```
