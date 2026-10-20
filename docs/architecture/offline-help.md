# Offline Help with web updates

Keep one authoring source: `guides/*.md`, `migration/*.md`, and
`assets/css/help-theme.css`. The app's Installation topic uses the current
`installation-wizard` guide, not the older getting-started article. An internal
cross-link can open any bundled guide, even one not listed in the landing cards.
External websites still open in the browser and require connectivity.

## Build and publish

`Scripts/build-offline-help.py --output DIR` uses **pandoc** (build tool only,
`brew install pandoc`) to turn the same web Markdown into self-contained HTML.
It resolves Jekyll links, includes locally referenced illustrations/screenshots,
and fails on missing images, internal links or native Help topics. No runtime
Python, pandoc, Markdown renderer, CDN or JavaScript dependency is added.

The signed app build and quick-deploy generate `Contents/Resources/OfflineHelp`.
The baseline currently contains 43 articles and 106 files (about 54 MiB).
`Scripts/lint-help-content.sh` validates generation without installing the app.

`Scripts/publish-guides.sh` also generates the downloadable snapshot. The
`--publish-root DIR` generator option stages immutable revisions as
`DIR/<major.minor>/<revision>/...` plus `DIR/<major.minor>/manifest.json`.
Publish the entire revision before its manifest; one normal GitHub Pages commit
keeps them together. Never rewrite an existing revision. Keep older version
folders so older apps keep a compatible source. The production root is
`https://malpern.github.io/KeyPath/offline-help/`.

## Runtime behavior

Help opens its local HTML immediately. When an article opens, a background actor checks
for updates (daily after a successful check, with a five-minute retry window after
a failure, within the current process). Downloads never block reading or replace
the page currently being read. A complete compatible revision appears on the next
article navigation/open. Unchanged bundled/downloaded files are reused.

Updates live under `~/Library/Application Support/KeyPath/Help/<major.minor>`;
existing session uninstall cleanup already includes that parent directory.
A manifest names files and SHA-256 hashes. Validate schema, version, paths,
coverage and size, then download into a fresh generation. Commit only by atomically
replacing a small current-generation pointer. Failed/interrupted updates preserve
the previous generation. Invalid cache falls back to the signed bundled baseline.
Old generations are pruned on first use after an app restart, before any page can
be reading them; directory identity is compared by name, not trailing-slash URL
representation. Tests cover the persistence regression this avoided.

This is data-only Help: WebKit loads files with read access limited to the selected
snapshot. Page JavaScript is disabled; generated Content Security Policy permits
local styles/images and prevents network subresources. A guide never needs a new
macOS permission or a privileged service.

## Verification

- Run `TEST_FILTER=OfflineHelpStore Scripts/run-tests-safe.sh` for fresh offline
  use, compatible update persistence, interrupted/hash-mismatched updates,
  incompatible/unsafe manifests, corrupt cache and internal topic routing.
- Run `Scripts/test-offline-help.sh OUTPUT`, then open its `OfflineHelpQA.app`.
  This standalone Help-only fixture never starts the KeyPath runtime. Updates use
  an injected offline transport. Its automatic WebKit sweep uses a new
  nonpersistent data store, explicitly blocks all HTTP(S), and checks every guide's
  text, local CSS and every image's decoded width. Read `OUTPUT/offline-report.json`;
  require `passed:true` and the full article count. Navigation buttons and actual
  article cross-links exercise the production Help view offline.
- Inspect current setup/privacy pages and a cross-link in the fixture. A clean VM
  or network/permission changes on the host are unnecessary for this content test.
- Verify the final app contains the same manifest/revision as the tested snapshot.
