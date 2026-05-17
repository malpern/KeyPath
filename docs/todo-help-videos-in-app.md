# TODO: Help Videos In-App Support

The home-row-mods help article now uses `<video>` tags for two animated explainers. These work on the gh-pages website but are not yet supported in the in-app help browser.

## What needs to happen

1. **Configure WKWebView for autoplay** — In `MarkdownHelpSheet.swift`, add to the `WKWebViewConfiguration`:
   ```swift
   config.mediaTypesRequiringUserActionForPlayback = []
   ```

2. **Bundle video files in Resources** — Copy `video-tap-hold.mp4` and `video-opposite-hand.mp4` to `Sources/KeyPathAppKit/Resources/`

3. **Update source markdown** — Replace the static image reference in `home-row-mods.md` with `<video>` tags pointing to bundled resources

4. **Update publish script** — `Scripts/publish-help-to-web.sh` needs to handle `.mp4` files in its image path conversion (currently only handles `.png`)

## Files involved

- `Sources/KeyPathAppKit/UI/Help/MarkdownHelpSheet.swift` — WKWebView config
- `Sources/KeyPathAppKit/Resources/home-row-mods.md` — source article
- `Scripts/publish-help-to-web.sh` — publish pipeline
- `Scripts/help-videos/` — Python scripts to regenerate videos

## Video files (on gh-pages)

- `images/help/video-tap-hold.mp4` (97KB) — Tap vs Hold basics with stopwatch
- `images/help/video-opposite-hand.mp4` (123KB) — Opposite-hand short-circuit optimization
