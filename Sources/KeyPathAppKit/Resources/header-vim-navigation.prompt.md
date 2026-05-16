# `header-vim-navigation.png` — generation prompt

Source-of-truth prompt for generating `header-vim-navigation.png`.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect)

## Prompt (v1)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: A wide horizontal band showing a keyboard's home row (H, J, K, L keys emphasized) with watercolor arrow symbols blooming from them — left, down, up, right. The keys are rendered as vintage typewriter keys with ink wash halos. Dotted ink lines trace navigation paths between the keys. A faint Space bar silhouette below with the word "hold" in tiny script.

Above the key row, hand-lettered in elegant black ink cursive: "Vim Navigation" — positioned at the vertical center band.

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, burnt orange. No people, no photos.
```
