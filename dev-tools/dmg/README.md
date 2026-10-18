# Private installer layout

`Scripts/package-test-dmg.sh` uses `dmgbuild-settings.py` and
`installer-branded@2x.png`. The artwork restores KeyPath's historical dark
palette, amber-lit keyboard, serif wordmark and “Keys that do more.” tagline.
Do not substitute generic light artwork or a new tagline without a brand review.

Finder supplies the real app and Applications alias. The original keyboard artwork with glowing legends
is composed with precise native typography and an SF Symbols arrow:

```sh
swift dev-tools/dmg/render-background.swift dev-tools/dmg
```

Artwork is 1320×800 pixels representing 660×400 points. Packaging converts it to
144-DPI TIFF so Finder uses the intended logical size. Native icon centers are
(205, 208) and (455, 208), with 96-point icons and 13-point native labels. A
single shared installation surface preserves filename contrast without separate
button-like plates; no duplicate filenames are baked into the artwork. Supporting
type is regular system sans serif, while the historical serif wordmark remains.

Finder can override hidden tab/path/status bars with a user's saved preferences.
Do not change global Finder preferences in packaging to force an appearance.

Keep `hide_extensions` empty: hiding the app's extension adds Finder metadata to
the signed bundle and can invalidate strict signature verification. Packaging
verifies the actual app inside the mounted image. Older `dmg-background*` assets
remain references for the separate Sparkle/create-dmg release workflow.

Finder uses dark filenames over image backgrounds. Keep label contrast in the
layout; do not try to suppress labels with an invalid zero-point text size, which
causes Finder to reject the icon-view metadata and lose the background/layout.
Vendor reference: https://c-command.com/downloads/manual/DropDMGManual-3.7.pdf
