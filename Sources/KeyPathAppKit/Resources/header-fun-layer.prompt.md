# `header-fun-layer.png` — generation prompt

Source-of-truth prompt for generating `header-fun-layer.png`.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect)

## Prompt (v1)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: A wide horizontal band split into two halves. Right side: a 3x4 grid of small keycaps with "F1" through "F12" written in elegant ink inside. Left side: watercolor icons for media controls — a play/pause symbol, musical notes, a sun (brightness), and a speaker with sound waves. A thin decorative divider line separates the two halves.

Above the scene, hand-lettered in elegant black ink cursive: "Function & Media" — positioned at the vertical center band.

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, indigo. No people, no photos.
```
