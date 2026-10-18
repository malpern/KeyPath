# Private installer layout

`Scripts/package-test-dmg.sh` uses `dmgbuild-settings.py` and
`installer-light@2x.png`. Finder supplies the real app and Applications alias;
the background supplies native system typography and the SF Symbols arrow.

Regenerate artwork after editing its source:

```sh
swift dev-tools/dmg/render-background.swift dev-tools/dmg
```

Artwork is 1320×800 pixels representing 660×400 points. Packaging converts it to
144-DPI TIFF so Finder uses the intended logical size. Native icon centers are
(180, 220) and (480, 220), with 96-point icons. Keep these aligned with the arrow
in the generator. A dark artwork variant is generated for future packaging use;
the current private installer uses the light artwork.

Finder can override hidden tab/path/status bars with a user's saved preferences.
The layout preview was checked with those bars hidden; do not change global
Finder preferences in packaging to force a particular appearance.

Keep `hide_extensions` empty: hiding the app's extension adds Finder metadata to
the signed bundle and can invalidate strict signature verification. Packaging
verifies the actual app inside the mounted image. The older `dmg-background*`
assets remain references for the separate Sparkle/create-dmg release workflow.
