# Help Video Generation

Python scripts that generate the animated MP4 videos used in the home-row-mods help article.

## Requirements

- Python 3 with Pillow (`pip3 install Pillow`)
- ffmpeg (`brew install ffmpeg`)
- macOS system fonts (Georgia, Helvetica)

## Scripts

### gen-video-tap-hold.py
**"Tap vs Hold"** — Explains the basic concept: quick tap = letter, long press = modifier. Shows a single F key with a stopwatch animation.

### gen-video-opposite-hand.py
**"Opposite-Hand Activation"** — Shows how pressing a key on the other hand short-circuits the timer. Uses D/F (left) and J/K (right) keys with a stopwatch that flashes when the decision resolves early.

## Usage

Each script generates numbered PNG frames in `/tmp/`, then encode with ffmpeg:

```bash
# Generate frames
python3 Scripts/help-videos/gen-video-tap-hold.py
python3 Scripts/help-videos/gen-video-opposite-hand.py

# Encode to MP4 (render at 2x, downscale for crisp text)
ffmpeg -y -framerate 24 -i /tmp/v1-frames/frame_%05d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
  -movflags +faststart -vf "scale=900:500" \
  .worktrees/gh-pages/images/help/video-tap-hold.mp4

ffmpeg -y -framerate 24 -i /tmp/v2-frames/frame_%05d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
  -movflags +faststart -vf "scale=900:500" \
  .worktrees/gh-pages/images/help/video-opposite-hand.mp4
```

Then commit and push the gh-pages branch.
