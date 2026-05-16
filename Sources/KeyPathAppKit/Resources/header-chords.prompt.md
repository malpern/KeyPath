# `header-chords.png` — generation prompt

Source-of-truth prompt for generating `header-chords.png`.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect)

## Prompt (v1)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: Two adjacent keycaps (S and D) at the vertical center, slightly overlapping or pressed together, with a watercolor bloom connecting them — suggesting simultaneous press. A graceful ink arrow curves from the pair toward a third keycap labeled "Esc" with a satisfying checkmark or spark. The aesthetic is "two become one."

A second smaller pair (J and K) sits to the right at the same vertical band, with an arrow to "Enter."

Hand-lettered in elegant black ink cursive: "Chords" — positioned at the vertical center band, to the left of the keycap illustrations.

Thin botanical vine decorations connect the pairs, suggesting the musical harmony metaphor of "chord."

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, indigo. No people, no photos.
```
