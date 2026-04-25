# `header-kindavim.png` — generation prompt

Source-of-truth prompt for regenerating `header-kindavim.png`. Save
the prompt next to the image so future iterations don't lose context.

- **Model:** `gpt-image-2`
- **Size:** `1536x1024` (3:2), center-cropped to `1536x857`, resized to `1376x768`
- **Quality:** `high`
- **Post-processing:** `sips --cropOffset 84 0 --cropToHeightWidth 857 1536` then `sips -z 768 1376`
- **Final dimensions:** `1376x768` (~1.79 aspect) — matches all other header images
- **Display aspect:** standard `.article-header-img` CSS rule handles this image
  with no per-image override needed.

## Iteration history

- **v1–v4** had positional issues (3:2 source mis-rendered as 16:9
  → vertical crop ate the title; later versions placed `H/J` on the
  left and `K/L` on the right instead of the canonical h-left,
  j-down, k-up, l-right layout).
- **v5** — fixed cardinal layout, but 3:2 native dimensions didn't
  match other headers (all ~1.79 aspect). Required a per-image CSS
  override. Cropping to 16:9 clipped K/J keycaps.
- **v6** — regenerated with aggressive margins, matched 1376x768
  dimensions, but laptop hardware aesthetic didn't fit the macOS feel.
- **v7** — macOS window with cardinal keycap cross, but K/J still
  cropped by CSS `object-fit: cover` (top/bottom 28% is invisible).
- **v8** — Mac Mail window concept, but keycaps in cross layout still
  lost K/J to CSS cropping.
- **v9 (current)** — Mac Mail inbox window with all four HJKL keycaps
  in a horizontal row at the vertical center. All elements survive
  the aggressive CSS crop. macOS software aesthetic.

## Prompt (v9)

```
ULTRA-WIDE LANDSCAPE BANNER, watercolor on aged cream parchment. Vintage naturalist field-notebook style.

LAYOUT: Only the middle 40% vertical strip will be visible. Everything important must sit in ONE narrow horizontal band at the exact vertical center.

SCENE: A wide watercolor macOS Mail window, horizontally oriented, sitting dead-center vertically. Classic macOS title bar with red/yellow/green dots. Inside: an inbox list with 5-6 email rows in loose sepia ink — sender, subject, date. One row highlighted with a warm wash.

HJKL KEYS — ALL FOUR positioned in a HORIZONTAL ROW across the vertical center of the canvas, NOT in a cross/plus shape:
  • H keycap (sage green bloom) on the far LEFT, with a left-arrow
  • J keycap (dusty teal bloom) to the left of the Mail window, with a small down-arrow
  • K keycap (warm ochre bloom) also to the left of the Mail window next to J, with a small up-arrow
  • L keycap (faded blue bloom) on the far RIGHT, with a right-arrow
  • Arrange as: H ... J K [Mail Window] ... L — all on the SAME horizontal line at the vertical center
  • Thin dotted ink lines from J/K to the highlighted row showing up/down navigation
  • Thin dotted ink lines from H/L showing left/right movement

ALL FOUR keycaps must be at the SAME vertical position — the exact vertical center. No keycap above or below the center line.

TITLE: Hand-lettered elegant black ink cursive: KindaVim — inside or just above the Mail window title bar, vertically centered in the band.

BACKGROUND: Aged cream parchment edge-to-edge. NO dark edges. Coffee stains and ink splatters as decoration. All edges cream.

Style: classic naturalist watercolor, loose ink lines, pigment pooling, paper grain. Earth tones: cream, sepia, sage, teal, ochre, indigo. No people, no photos.
```
