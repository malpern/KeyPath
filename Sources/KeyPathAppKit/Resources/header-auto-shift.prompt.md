# `header-auto-shift.png` — generation prompt

Source-of-truth prompt for generating `header-auto-shift.png`.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect)

## Prompt (v1)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: A horizontal row of symbol keycaps at the vertical center: [ . ] [ ; ] [ / ] [ = ] — each shown in a "dual state" with the normal symbol in dark ink on top and the shifted symbol (> : ? +) appearing below in a lighter watercolor wash, as if emerging from the key when held. Thin clock-hand or hourglass motifs between keys suggest "hold longer."

Hand-lettered in elegant black ink cursive: "Auto-Shift" — positioned at the vertical center band.

A faint crossed-out Shift key in the corner suggests "no more reaching for Shift."

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, indigo. No people, no photos.
```
